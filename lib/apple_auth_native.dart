import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'webview_host.dart';

/// iOS 전용. 웹에서 `{type: 'appleSignIn'}` 이 오면 Apple 로그인 시트를 띄우고
/// 결과를 `window.__onDiaryAppleCredential` / `__onDiaryAppleSignInError` 로 돌려준다.
/// 백엔드는 identityToken(JWT)을 Apple 공개키로 검증해야 함 (aud = com.yun.pageby).
Future<void> runNativeAppleSignIn() async {
  if (!Platform.isIOS) {
    await WebViewHost.instance.dispatchAppleSignInError('unsupported');
    return;
  }
  try {
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: const [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
    );
    final identityToken = credential.identityToken;
    if (identityToken == null || identityToken.isEmpty) {
      await WebViewHost.instance.dispatchAppleSignInError('no_identity_token');
      return;
    }
    // 이름/이메일은 최초 로그인 때만 내려오므로 웹(백엔드)이 그때 저장해야 함
    await WebViewHost.instance.dispatchAppleCredential({
      'identityToken': identityToken,
      'authorizationCode': credential.authorizationCode,
      'userIdentifier': credential.userIdentifier,
      'email': credential.email,
      'givenName': credential.givenName,
      'familyName': credential.familyName,
    });
  } on SignInWithAppleAuthorizationException catch (e) {
    debugPrint('[apple] authorization failed: ${e.code} ${e.message}');
    await WebViewHost.instance.dispatchAppleSignInError(
      e.code == AuthorizationErrorCode.canceled ? 'cancelled' : 'failed',
    );
  } catch (e, st) {
    debugPrint('[apple] sign-in failed: $e\n$st');
    await WebViewHost.instance.dispatchAppleSignInError('failed');
  }
}
