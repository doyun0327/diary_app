import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'banner_install_gate.dart';
import 'file_chooser.dart';
import 'google_auth_native.dart';
import 'google_sign_in_screen.dart';
import 'native_bridge.dart';
import 'push_service.dart';
import 'rewarded_ad_service.dart';
import 'subscription_service.dart';
import 'webview_host.dart';

/// 로컬 개발: `npm run dev` + `adb reverse tcp:5173 tcp:5173`
/// 에뮬레이터: http://10.0.2.2:5173
/// 배포 앱: Cloudflare Workers URL (아래 prod) 또는
///   flutter build appbundle --dart-define=DIARY_WEB_URL=https://...
const String _kDiaryWebUrlDev = 'http://127.0.0.1:5173';
/// `npm run deploy` 후 나온 workers.dev / 커스텀 도메인 (끝 `/` 없이)
const String _kDiaryWebUrlProd = 'https://pageby-diary.idoyun781.workers.dev';

String get kDiaryWebUrl {
  const fromDefine = String.fromEnvironment('DIARY_WEB_URL');
  if (fromDefine.isNotEmpty) return fromDefine;
  if (kReleaseMode && _kDiaryWebUrlProd.isNotEmpty) return _kDiaryWebUrlProd;
  return _kDiaryWebUrlDev;
}

const Color kCalendarHeaderColor = Color(0xFF1A1A1A);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 플러그인 초기화 실패/지연으로 아이콘만 깜빡이고 종료되지 않게 먼저 UI를 띄움
  runApp(const DiaryApp());
  unawaited(_initPlugins());
}

Future<void> _initPlugins() async {
  // Ads first: banner must not load before MobileAds.initialize.
  try {
    await RewardedAdService.instance.init();
  } catch (e, st) {
    debugPrint('[main] ads init failed: $e\n$st');
  }
  try {
    await SubscriptionService.instance.init();
    // WebView가 먼저 로드돼도 Pro 상태를 다시 맞춤
    await SubscriptionService.instance.syncToWeb();
  } catch (e, st) {
    debugPrint('[main] subscription init failed: $e\n$st');
  }
  // Push after first frames so notification permission dialog is safe.
  try {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await initDiaryPush();
  } catch (e, st) {
    debugPrint('[main] push init failed: $e\n$st');
  }
}

class DiaryApp extends StatelessWidget {
  const DiaryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'pageBy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.brown),
        useMaterial3: true,
      ),
      scaffoldMessengerKey: diaryMessengerKey,
      home: const DiaryWebViewPage(),
    );
  }
}

class DiaryWebViewPage extends StatefulWidget {
  const DiaryWebViewPage({super.key});

  @override
  State<DiaryWebViewPage> createState() => _DiaryWebViewPageState();
}

class _DiaryWebViewPageState extends State<DiaryWebViewPage> {
  late final WebViewController _controller;
  var _loading = true;
  var _webLoadFailed = false;
  var _webReady = false;
  var _openingGoogle = false;
  var _edgeDragDx = 0.0;
  BannerAd? _bannerAd;
  bool _bannerLoaded = false;
  bool _bannerGraceChecked = false;
  bool _bannerGraceElapsed = false;
  Timer? _bannerGraceTimer;

  /// Google 샘플 테스트 배너 (디버그 전용)
  static const _androidTestBannerId = 'ca-app-pub-3940256099942544/6300978111';
  /// AdMob 콘솔에서 만든 실제 배너 단위 ID를 넣으세요. (앱: ca-app-pub-4752729386590212~2783667278)
  /// 비어 있으면 릴리스에서 배너가 표시되지 않습니다.
  static const _androidProdBannerId = 'ca-app-pub-4752729386590212/5989921712';

  String? _bannerUnitId() {
    const fromDefine = String.fromEnvironment('ADMOB_BANNER_UNIT_ID');
    if (fromDefine.isNotEmpty) return fromDefine;
    if (!kReleaseMode) return _androidTestBannerId;
    if (_androidProdBannerId.isNotEmpty) return _androidProdBannerId;
    return null;
  }

  bool _isDiaryAppUrl(String url) {
    try {
      final loaded = Uri.parse(url);
      final home = Uri.parse(kDiaryWebUrl);
      return loaded.host == home.host && loaded.scheme == home.scheme;
    } catch (_) {
      return false;
    }
  }

  void _retryWebLoad() {
    setState(() {
      _loading = true;
      _webLoadFailed = false;
      _webReady = false;
    });
    unawaited(_controller.loadRequest(Uri.parse(kDiaryWebUrl)));
  }

  void _onMainFrameLoadFailed() {
    if (!mounted || _webReady) return;
    setState(() {
      _webLoadFailed = true;
      _webReady = false;
      _loading = false;
    });
  }

  bool _isOfflineWebError(WebResourceError error) {
    final code = error.errorCode;
    final desc = error.description.toLowerCase();
    final type = error.errorType;
    if (code == -2 ||
        code == -6 ||
        code == -7 ||
        code == -21 ||
        code == -102 ||
        code == -105 ||
        code == -106 ||
        code == -109 ||
        code == -118) {
      return true;
    }
    if (type == WebResourceErrorType.hostLookup ||
        type == WebResourceErrorType.connect ||
        type == WebResourceErrorType.timeout) {
      return true;
    }
    return desc.contains('internet') ||
        desc.contains('disconnected') ||
        desc.contains('name_not_resolved') ||
        desc.contains('timed out') ||
        desc.contains('network') ||
        desc.contains('connection');
  }

  Future<bool> _isDiaryShellLoaded() async {
    try {
      final raw = await _controller.runJavaScriptReturningResult('''
        (function(){
          try {
            if (location.protocol === 'chrome-error:') return 'fail';
            if (document.getElementById('root')) return 'ok';
            var t = ((document.body && document.body.innerText) || '').toString();
            if (/ERR_[A-Z_]+/.test(t)) return 'fail';
            if (t.indexOf('웹 페이지를 사용할 수 없음') >= 0) return 'fail';
            return 'fail';
          } catch (e) {
            return 'fail';
          }
        })()
      ''');
      return raw.toString().replaceAll('"', '').toLowerCase().contains('ok');
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    googleSignInRequests.addListener(_onGoogleSignInRequested);
    SubscriptionService.instance.activeNotifier.addListener(_onSubscriptionChanged);
    RewardedAdService.instance.readyNotifier.addListener(_onSubscriptionChanged);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        kDiaryNativeChannel,
        onMessageReceived: handleDiaryNativeMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() {
              _loading = true;
              _webReady = false;
            });
            unawaited(_controller.runJavaScript('''
              window.__DIARY_FLUTTER__ = true;
            '''));
          },
          onPageFinished: (url) {
            unawaited(() async {
              final ok = _isDiaryAppUrl(url) && await _isDiaryShellLoaded();
              if (!mounted) return;
              if (!ok) {
                _onMainFrameLoadFailed();
                return;
              }
              setState(() {
                _loading = false;
                _webLoadFailed = false;
                _webReady = true;
              });
              WebViewHost.instance.controller = _controller;
              diaryPush.controller = _controller;
              diaryPush.flushPending();
              await WebViewHost.instance.markFlutter();
              await _syncHeaderFromWeb();
              if (mounted) await _pushSafeAreaInsets(context);
              await SubscriptionService.instance.syncToWeb();
            }());
          },
          onWebResourceError: (error) {
            debugPrint('WebView error: ${error.errorCode} ${error.description}');
            final mainFrame = error.isForMainFrame;
            if (mainFrame == true || (mainFrame != false && _isOfflineWebError(error))) {
              _onMainFrameLoadFailed();
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(kDiaryWebUrl));
    WebViewHost.instance.controller = _controller;
    attachAndroidFileChooser(_controller);
    unawaited(_initBannerGrace());
  }

  Future<void> _initBannerGrace() async {
    final elapsed = await isBannerGraceElapsed();
    if (!mounted) return;
    _bannerGraceChecked = true;
    if (elapsed) {
      setState(() => _bannerGraceElapsed = true);
      _onSubscriptionChanged();
      return;
    }
    setState(() => _bannerGraceElapsed = false);
    final remaining = await bannerGraceRemaining();
    if (remaining != null) {
      debugPrint('[ads] banner grace remaining: ${remaining.inMinutes}m ${remaining.inSeconds % 60}s');
      _bannerGraceTimer = Timer(remaining, () {
        if (!mounted) return;
        setState(() => _bannerGraceElapsed = true);
        _onSubscriptionChanged();
      });
    }
  }

  Future<void> _syncHeaderFromWeb() async {
    try {
      final raw = await _controller.runJavaScriptReturningResult('''
        (function(){
          return window.__diaryHideNativeChrome === true ? 'hide' : 'show';
        })()
      ''');
      final text = raw.toString().replaceAll('"', '').toLowerCase();
      if (text.contains('hide') && diaryAppBar.value.visible) {
        diaryAppBar.value = const DiaryAppBarState(
          visible: false,
          showMenu: false,
        );
      }
    } catch (e) {
      debugPrint('[header] sync from web failed: $e');
    }
  }

  /// Android WebView는 env(safe-area-inset-*)가 0인 경우가 많아 Flutter inset을 넘김.
  Future<void> _pushSafeAreaInsets(BuildContext context) async {
    final padding = MediaQuery.paddingOf(context);
    final hideChrome = !diaryAppBar.value.visible;
    final top = hideChrome ? padding.top : 0.0;
    final bottom = padding.bottom;
    try {
      await _controller.runJavaScript('''
        (function(){
          var r = document.documentElement.style;
          r.setProperty('--diary-safe-top', '${top}px');
          r.setProperty('--diary-safe-bottom', '${bottom}px');
        })();
      ''');
    } catch (e) {
      debugPrint('[safe-area] push failed: $e');
    }
  }

  @override
  void dispose() {
    googleSignInRequests.removeListener(_onGoogleSignInRequested);
    SubscriptionService.instance.activeNotifier.removeListener(_onSubscriptionChanged);
    RewardedAdService.instance.readyNotifier.removeListener(_onSubscriptionChanged);
    _bannerGraceTimer?.cancel();
    _disposeBanner();
    super.dispose();
  }

  void _onSubscriptionChanged() {
    final active = SubscriptionService.instance.activeNotifier.value;
    if (active) {
      _disposeBanner();
      return;
    }
    if (!_bannerGraceChecked || !_bannerGraceElapsed) return;
    _ensureBanner();
  }

  void _disposeBanner() {
    _bannerAd?.dispose();
    _bannerAd = null;
    if (_bannerLoaded && mounted) {
      setState(() => _bannerLoaded = false);
    } else {
      _bannerLoaded = false;
    }
  }

  void _ensureBanner() {
    if (_bannerAd != null) return;
    if (!RewardedAdService.instance.isReady) return;
    final unitId = _bannerUnitId();
    if (unitId == null || unitId.isEmpty) return;

    try {
      final ad = BannerAd(
        size: AdSize.banner,
        adUnitId: unitId,
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (!mounted) return;
            setState(() => _bannerLoaded = true);
          },
          onAdFailedToLoad: (ad, error) {
            ad.dispose();
            _bannerAd = null;
            if (!mounted) return;
            setState(() => _bannerLoaded = false);
          },
        ),
        request: const AdRequest(),
      );
      _bannerAd = ad;
      unawaited(ad.load());
    } catch (e, st) {
      debugPrint('[ads] banner create failed: $e\n$st');
      _bannerAd = null;
    }
  }

  void _onGoogleSignInRequested() {
    if (!mounted || _openingGoogle) return;
    _openingGoogle = true;
    // 같은 프레임에서 바로 푸시 — 지연하면 계정 선택창이 다음 탭까지 안 뜸
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (!mounted) return;
        final result = await Navigator.of(context).push<String>(
          MaterialPageRoute(builder: (_) => const GoogleSignInScreen()),
        );
        if (result == null || result.isEmpty) {
          // 화면에서 이미 에러를 웹으로 보냈으면 중복 cancelled 는 무시됨
          await WebViewHost.instance.dispatchGoogleSignInError('cancelled');
        } else {
          await WebViewHost.instance.dispatchGoogleIdToken(result);
        }
      } catch (e, st) {
        debugPrint('open Google sign-in failed: $e\n$st');
        await WebViewHost.instance.dispatchGoogleSignInError(
          friendlyGoogleError(e),
        );
      } finally {
        _openingGoogle = false;
      }
    });
  }

  Future<bool> _goBackInWeb() async {
    try {
      final raw = await _controller.runJavaScriptReturningResult('''
        (function(){
          try {
            if (typeof window.diaryGoBack === 'function') {
              return !!window.diaryGoBack();
            }
            window.dispatchEvent(new Event('diary-native-back'));
            return false;
          } catch (e) {
            return false;
          }
        })()
      ''');
      return raw.toString().replaceAll('"', '').toLowerCase() == 'true';
    } catch (e) {
      debugPrint('web goBack failed: $e');
      return false;
    }
  }

  Future<void> _runHeaderAction(String action) async {
    await _controller.runJavaScript(
      "if (typeof window.diaryHeaderAction === 'function') window.diaryHeaderAction('$action');",
    );
  }

  Future<void> _handleSystemBack() async {
    final handled = await _goBackInWeb();
    if (!handled) {
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_handleSystemBack());
      },
      child: ValueListenableBuilder<DiaryAppBarState>(
        valueListenable: diaryAppBar,
        builder: (context, header, _) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            unawaited(_pushSafeAreaInsets(context));
          });
          return ValueListenableBuilder<DiaryThemeState>(
            valueListenable: diaryTheme,
            builder: (context, theme, _) {
              final centeredHeader = header.showSave ||
                  (header.showBack &&
                      !header.showMenu &&
                      !header.showCalendar);
              return Scaffold(
                backgroundColor: theme.background,
                // AppBar 없을 때 상태바 뒤로 콘텐츠가 깔리도록
                extendBodyBehindAppBar: !header.visible,
                appBar: header.visible
                    ? AppBar(
                        toolbarHeight: 44,
                        automaticallyImplyLeading: false,
                        backgroundColor: theme.background,
                        foregroundColor: theme.accent,
                        elevation: 0,
                        scrolledUnderElevation: 0,
                        surfaceTintColor: Colors.transparent,
                        centerTitle: centeredHeader,
                        titleSpacing: centeredHeader ? 0 : 4,
                        leading: centeredHeader
                            ? IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                onPressed: () =>
                                    unawaited(_runHeaderAction('back')),
                                icon: Icon(
                                  Icons.chevron_left,
                                  color: theme.accent,
                                  size: 26,
                                ),
                              )
                            : null,
                        leadingWidth: centeredHeader ? 44 : null,
                        shape: Border(
                          bottom: BorderSide(
                            color: theme.accent.withOpacity(0.12),
                          ),
                        ),
                        title: header.showSave || centeredHeader
                            ? Text(
                                header.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: kCalendarHeaderColor,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2,
                                ),
                              )
                            : header.showBack
                                ? TextButton(
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: () => unawaited(
                                      _runHeaderAction('back'),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.chevron_left,
                                          color: theme.accent,
                                          size: 26,
                                        ),
                                        Flexible(
                                          child: Text(
                                            header.label,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: kCalendarHeaderColor,
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: -0.2,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : header.showCalendar
                                    ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 36,
                                          minHeight: 40,
                                        ),
                                        onPressed: () => unawaited(
                                          _runHeaderAction('prevMonth'),
                                        ),
                                        icon: Icon(
                                          Icons.chevron_left,
                                          color: kCalendarHeaderColor,
                                        ),
                                      ),
                                      TextButton(
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 2,
                                          ),
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        onPressed: () => unawaited(
                                          _runHeaderAction('openMonthPicker'),
                                        ),
                                        child: Text(
                                          header.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: kCalendarHeaderColor,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: -0.2,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 36,
                                          minHeight: 40,
                                        ),
                                        onPressed: () => unawaited(
                                          _runHeaderAction('nextMonth'),
                                        ),
                                        icon: Icon(
                                          Icons.chevron_right,
                                          color: kCalendarHeaderColor,
                                        ),
                                      ),
                                    ],
                                  )
                                : null,
                        actions: [
                          if (header.showSave)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: TextButton(
                                onPressed: header.saveEnabled
                                    ? () => unawaited(
                                          _runHeaderAction('save'),
                                        )
                                    : null,
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  header.saveLabel.isNotEmpty
                                      ? header.saveLabel
                                      : 'Save',
                                  style: TextStyle(
                                    color: header.saveEnabled
                                        ? theme.accent
                                        : theme.accent.withOpacity(0.38),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            )
                          else ...[
                            if (header.showSearch)
                              IconButton(
                                onPressed: () => unawaited(
                                  _runHeaderAction('openSearch'),
                                ),
                                icon: Icon(Icons.search, color: theme.accent),
                              ),
                            if (header.showMenu)
                              IconButton(
                                onPressed: () => unawaited(
                                  _runHeaderAction('openMenu'),
                                ),
                                icon: Icon(Icons.menu, color: theme.accent),
                              ),
                          ],
                        ],
                      )
                    : null,
                // AppBar 숨김 화면(친구방·상세)은 웹 툴바가 safe-area를 담당.
                // top SafeArea를 켜면 빈 앱헤더 자리가 남음.
                body: SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      Expanded(
                        child: Stack(
                          children: [
                            Opacity(
                              opacity: _webReady && !_webLoadFailed ? 1 : 0,
                              child: IgnorePointer(
                                ignoring: !_webReady || _webLoadFailed,
                                child: WebViewWidget(controller: _controller),
                              ),
                            ),
                            Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              width: 28,
                              child: GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onHorizontalDragStart: (_) => _edgeDragDx = 0,
                                onHorizontalDragUpdate: (details) {
                                  _edgeDragDx += details.delta.dx;
                                },
                                onHorizontalDragEnd: (details) {
                                  final velocity = details.primaryVelocity ?? 0;
                                  if (velocity > 180 || _edgeDragDx > 40) {
                                    unawaited(_goBackInWeb());
                                  }
                                },
                              ),
                            ),
                            if (_loading && !_webLoadFailed)
                              const Center(child: CircularProgressIndicator()),
                            if (_webLoadFailed)
                              Positioned.fill(
                                child: ColoredBox(
                                  color: theme.background,
                                  child: SafeArea(
                                    child: Center(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 32,
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              '네트워크를 확인해 주세요.',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: kCalendarHeaderColor
                                                    .withOpacity(0.88),
                                                fontSize: 17,
                                                fontWeight: FontWeight.w600,
                                                height: 1.45,
                                              ),
                                            ),
                                            const SizedBox(height: 20),
                                            TextButton(
                                              onPressed: _retryWebLoad,
                                              style: TextButton.styleFrom(
                                                foregroundColor: theme.accent,
                                                textStyle: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              child: const Text('다시 시도'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      // Flutter AppBar 쓰는 화면(홈·쓰기)만 배너 자리 예약.
                      // 친구방·상세(웹 툴바)에서는 넣지 않음 → 웹/앱 크롬 겹침·이중 배너 방지
                      if (header.visible &&
                          _bannerGraceElapsed &&
                          !SubscriptionService.instance.activeNotifier.value)
                        SizedBox(
                          height: AdSize.banner.height.toDouble(),
                          width: double.infinity,
                          child: _bannerLoaded && _bannerAd != null
                              ? Center(
                                  child: SizedBox(
                                    height: _bannerAd!.size.height.toDouble(),
                                    width: _bannerAd!.size.width.toDouble(),
                                    child: AdWidget(ad: _bannerAd!),
                                  ),
                                )
                              : ColoredBox(color: theme.background),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
