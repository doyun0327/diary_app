import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'webview_host.dart';

/// 백엔드 `auth.google.client-ids` / VITE_GOOGLE_CLIENT_ID 와 같아야 idToken audience 가 맞음
const kGoogleWebClientId =
    '511504695762-a5ldsnm5evd835k4vkdo02peon5c2b3j.apps.googleusercontent.com';

final GoogleSignIn _googleSignIn = GoogleSignIn(
  scopes: const ['email', 'profile'],
  serverClientId: kGoogleWebClientId,
);

Future<void> nativeGoogleSignIn() async {
  try {
    final account = await _googleSignIn.signIn();
    if (account == null) {
      await WebViewHost.instance.dispatchEvent(
        'diary-google-sign-in-error',
        'cancelled',
      );
      return;
    }
    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null || idToken.isEmpty) {
      await WebViewHost.instance.dispatchEvent(
        'diary-google-sign-in-error',
        'no_id_token',
      );
      return;
    }
    await WebViewHost.instance.dispatchEvent('diary-google-id-token', idToken);
  } catch (e, st) {
    debugPrint('native Google sign-in failed: $e\n$st');
    await WebViewHost.instance.dispatchEvent(
      'diary-google-sign-in-error',
      e.toString(),
    );
  }
}

Future<void> nativeGoogleSignOut() async {
  try {
    await _googleSignIn.signOut();
  } catch (e) {
    debugPrint('native Google sign-out failed: $e');
  }
}
