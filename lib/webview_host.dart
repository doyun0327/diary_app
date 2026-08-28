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

  /// 결제 완료 직후 Pro 상태 즉시 반영 (웹 `__onDiarySubscriptionPurchaseComplete`)
  Future<void> dispatchSubscriptionPurchaseComplete({
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
      if (typeof window.__onDiarySubscriptionPurchaseComplete === 'function') {
        window.__onDiarySubscriptionPurchaseComplete($payload);
      }
      window.dispatchEvent(new CustomEvent('diary-subscription-purchase-complete', { detail: $payload }));
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
