import 'dart:convert';

import 'package:webview_flutter/webview_flutter.dart';

import 'install_device_key.dart';

class WebViewHost {
  WebViewHost._();
  static final WebViewHost instance = WebViewHost._();

  WebViewController? controller;
  String? _cachedInstallDeviceKey;

  Future<void> runJs(String js) async {
    final web = controller;
    if (web == null) return;
    await web.runJavaScript(js);
  }

  Future<void> markFlutter() async {
    _cachedInstallDeviceKey ??= await getInstallDeviceKey();
    final keyJson = jsonEncode(_cachedInstallDeviceKey ?? '');
    await runJs('''
      window.__DIARY_FLUTTER__ = true;
      window.__DIARY_NATIVE_DEVICE_KEY__ = $keyJson;
      window.dispatchEvent(new Event('diary-flutter-ready'));
      window.dispatchEvent(new Event('diary-native-device-key'));
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

  Future<void> dispatchAppleCredential(Map<String, Object?> credential) async {
    final payload = jsonEncode(credential);
    await runJs('''
      window.__DIARY_FLUTTER__ = true;
      if (typeof window.__onDiaryAppleCredential === 'function') {
        window.__onDiaryAppleCredential($payload);
      }
    ''');
  }

  Future<void> dispatchAppleSignInError(String reason) async {
    final payload = jsonEncode(reason);
    await runJs('''
      window.__DIARY_FLUTTER__ = true;
      if (typeof window.__onDiaryAppleSignInError === 'function') {
        window.__onDiaryAppleSignInError($payload);
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

  /// 구매 복원 결과 (웹 `__onDiarySubscriptionRestore`)
  Future<void> dispatchSubscriptionRestoreResult({
    required bool ok,
    required bool active,
    String? error,
  }) async {
    final payload = jsonEncode({
      'ok': ok,
      'active': active,
      'error': error,
    });
    await runJs('''
      window.__DIARY_FLUTTER__ = true;
      if (typeof window.__onDiarySubscriptionRestore === 'function') {
        window.__onDiarySubscriptionRestore($payload);
      }
      window.dispatchEvent(new CustomEvent('diary-subscription-restore', { detail: $payload }));
    ''');
  }

  Future<void> dispatchRewardedAdResult({
    required bool ok,
    String reason = 'aiDraw',
    String? error,
  }) async {
    final payload = jsonEncode({
      'ok': ok,
      'reason': reason,
      // 실패 시 웹이 안내 문구를 고를 수 있게: no_ad | dismissed
      if (!ok && error != null) 'error': error,
    });
    await runJs('''
      window.__DIARY_FLUTTER__ = true;
      if (typeof window.__onDiaryRewardedAd === 'function') {
        window.__onDiaryRewardedAd($payload);
      }
      window.dispatchEvent(new CustomEvent('diary-rewarded-ad-result', { detail: $payload }));
    ''');
  }

  Future<void> dispatchTipPurchaseComplete({
    required bool ok,
    bool cancelled = false,
    String? productId,
    String? error,
  }) async {
    final payload = jsonEncode({
      'ok': ok,
      'cancelled': cancelled,
      'productId': productId,
      'error': error,
    });
    Future<void> send() => runJs('''
      window.__DIARY_FLUTTER__ = true;
      if (typeof window.__onDiaryTipPurchaseComplete === 'function') {
        window.__onDiaryTipPurchaseComplete($payload);
      }
      window.dispatchEvent(new CustomEvent('diary-tip-purchase-complete', { detail: $payload }));
    ''');
    await send();
    // 결제 UI 직후 WebView가 잠깐 준비 안 된 경우 대비
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await send();
  }

  Future<void> dispatchTipProducts({
    required List<Map<String, String>> products,
  }) async {
    final payload = jsonEncode({'products': products});
    await runJs('''
      window.__DIARY_FLUTTER__ = true;
      if (typeof window.__onDiaryTipProducts === 'function') {
        window.__onDiaryTipProducts($payload);
      }
      window.dispatchEvent(new CustomEvent('diary-tip-products', { detail: $payload }));
    ''');
  }
}
