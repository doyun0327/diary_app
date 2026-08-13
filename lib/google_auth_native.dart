import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// 웹에서 로그인 요청이 오면 Flutter 화면에서 처리하기 위한 신호
final ValueNotifier<int> googleSignInRequests = ValueNotifier<int>(0);

void enqueueNativeGoogleSignIn() {
  googleSignInRequests.value++;
}

/// 백엔드 `auth.google.client-ids` / VITE_GOOGLE_CLIENT_ID 와 같아야 idToken audience 가 맞음
const kGoogleWebClientId =
    '511504695762-a5ldsnm5evd835k4vkdo02peon5c2b3j.apps.googleusercontent.com';

final GoogleSignIn googleSignIn = GoogleSignIn(
  scopes: const ['email', 'profile'],
  serverClientId: kGoogleWebClientId,
);

String friendlyGoogleError(Object e) {
  final text = e.toString();
  if (text.contains('ApiException: 10') || text.contains('DEVELOPER_ERROR')) {
    return 'developer_error';
  }
  if (text.contains('ApiException: 7') || text.contains('NETWORK_ERROR')) {
    return 'network';
  }
  if (text.contains('ApiException: 12501') ||
      text.contains('SIGN_IN_CANCELLED')) {
    return 'cancelled';
  }
  if (text.contains('ApiException: 12500') ||
      text.contains('sign_in_failed')) {
    return 'play_services';
  }
  if (text.contains('TimeoutException')) {
    return 'timeout';
  }
  return text;
}

/// 성공 시 idToken, 취소 시 null. 실패는 throw.
Future<String?> obtainGoogleIdToken() async {
  debugPrint('[google] native sign-in start');
  final account = await googleSignIn.signIn().timeout(
    const Duration(seconds: 40),
  );
  if (account == null) {
    debugPrint('[google] cancelled / null account');
    return null;
  }
  final auth = await account.authentication;
  final idToken = auth.idToken;
  if (idToken == null || idToken.isEmpty) {
    debugPrint('[google] missing idToken (check Web client id / SHA-1)');
    throw StateError('no_id_token');
  }
  debugPrint('[google] idToken length=${idToken.length}');
  return idToken;
}

Future<void> nativeGoogleSignOut() async {
  try {
    await googleSignIn.signOut();
  } catch (e) {
    debugPrint('native Google sign-out failed: $e');
  }
}
