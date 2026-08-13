import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'file_chooser.dart';
import 'google_auth_native.dart';
import 'google_sign_in_screen.dart';
import 'native_bridge.dart';
import 'push_service.dart';
import 'webview_host.dart';

/// Android 에뮬레이터 → PC의 Vite (5173)
/// 배포본을 보려면 Cloudflare URL로 바꾸세요. 예: https://pageby-diary.<계정>.workers.dev
const String kDiaryWebUrl = 'http://10.161.172.7:5173';

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
      title: 'Diary',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.brown),
        useMaterial3: true,
      ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_loading)
              const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}
