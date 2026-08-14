import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'file_chooser.dart';
import 'google_auth_native.dart';
import 'google_sign_in_screen.dart';
import 'native_bridge.dart';
import 'push_service.dart';
import 'webview_host.dart';

/// USB 실기기: `adb reverse tcp:5173 tcp:5173` 후 이 주소
/// 에뮬레이터: http://10.0.2.2:5173  (또는 노트북 LAN IP)
/// 배포본: Cloudflare URL
const String kDiaryWebUrl = 'http://127.0.0.1:5173';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initDiaryPush();
  runApp(const DiaryApp());
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
  var _openingGoogle = false;
  var _edgeDragDx = 0.0;

  @override
  void initState() {
    super.initState();
    googleSignInRequests.addListener(_onGoogleSignInRequested);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        kDiaryNativeChannel,
        onMessageReceived: handleDiaryNativeMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _loading = true),
          onPageFinished: (_) {
            setState(() => _loading = false);
            WebViewHost.instance.controller = _controller;
            diaryPush.controller = _controller;
            diaryPush.flushPending();
            WebViewHost.instance.markFlutter();
          },
          onWebResourceError: (error) {
            debugPrint('WebView error: ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse(kDiaryWebUrl));
    WebViewHost.instance.controller = _controller;
    attachAndroidFileChooser(_controller);
  }

  @override
  void dispose() {
    googleSignInRequests.removeListener(_onGoogleSignInRequested);
    super.dispose();
  }

  void _onGoogleSignInRequested() {
    if (!mounted || _openingGoogle) return;
    _openingGoogle = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (!mounted) return;
        final result = await Navigator.of(context).push<String>(
          MaterialPageRoute(builder: (_) => const GoogleSignInScreen()),
        );
        if (result == null || result.isEmpty) {
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
      child: Scaffold(
          body: SafeArea(
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
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
                if (_loading)
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
        ),
    );
  }
}
