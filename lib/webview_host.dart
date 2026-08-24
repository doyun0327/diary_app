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
    await runJs('''
      window.__DIARY_FLUTTER__ = true;
      window.dispatchEvent(new Event('diary-flutter-ready'));
      if (window.__diaryHideNativeChrome === true && window.DiaryNative) {
        window.DiaryNative.postMessage(JSON.stringify({
          type: 'headerState',
          visible: false,
          showCalendar: false,
          showBack: false,
          showSave: false,
          showMenu: false,
          showSearch: false
        }));
      }
    ''');
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

  Future<void> dispatchSubscriptionStatus({
    required bool active,
    int? expiresAtMs,
    String? productId,
  }) async {
    final payload = jsonEncode({
      'active': active,
      'expiresAt': expiresAtMs,
      'productId': productId,
    });
    await runJs('''
      window.__DIARY_FLUTTER__ = true;
      if (typeof window.__onDiarySubscriptionStatus === 'function') {
        window.__onDiarySubscriptionStatus($payload);
      }
      window.dispatchEvent(new CustomEvent('diary-subscription-status', { detail: $payload }));
    ''');
  }

  Future<void> dispatchRewardedAdResult({
    required bool ok,
    String reason = 'aiDraw',
  }) async {
    final payload = jsonEncode({
      'ok': ok,
      'reason': reason,
    });
    await runJs('''
      window.__DIARY_FLUTTER__ = true;
      if (typeof window.__onDiaryRewardedAd === 'function') {
        window.__onDiaryRewardedAd($payload);
      }
      window.dispatchEvent(new CustomEvent('diary-rewarded-ad-result', { detail: $payload }));
    ''');
  }
}
