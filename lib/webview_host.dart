import 'dart:convert';

import 'package:webview_flutter/webview_flutter.dart';

class WebViewHost {
  WebViewHost._();
  static final WebViewHost instance = WebViewHost._();

  WebViewController? controller;

  Future<void> runJs(String js) async {
    final web = controller;
    if (web == null) return;
    await web.runJavaScript(js);
  }

  Future<void> markFlutter() async {
    await runJs('window.__DIARY_FLUTTER__ = true;');
  }

  Future<void> dispatchGoogleIdToken(String idToken) async {
    final payload = jsonEncode(idToken);
    await runJs('''
      window.__DIARY_FLUTTER__ = true;
      if (typeof window.__onDiaryGoogleIdToken === 'function') {
        window.__onDiaryGoogleIdToken($payload);
      }
    ''');
  }

  Future<void> dispatchGoogleSignInError(String reason) async {
    final payload = jsonEncode(reason);
    await runJs('''
      window.__DIARY_FLUTTER__ = true;
      if (typeof window.__onDiaryGoogleSignInError === 'function') {
        window.__onDiaryGoogleSignInError($payload);
      }
    ''');
  }
}
