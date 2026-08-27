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
    return 'developer_error:10';
  }
  if (text.contains('ApiException: 7') || text.contains('NETWORK_ERROR')) {
    return 'network';
  }
  if (text.contains('ApiException: 12501') ||
      text.contains('SIGN_IN_CANCELLED')) {
    return 'cancelled';
  }
  // 12500: 동의화면/브랜딩/OAuth 구성 미완료에서도 자주 발생
  if (text.contains('ApiException: 12500')) {
    return 'developer_error:12500';
  }
  if (text.contains('sign_in_failed')) {
    return 'developer_error:sign_in_failed';
  }
  if (text.contains('TimeoutException')) {
    return 'timeout';
  }
  if (text.contains('no_id_token')) {
    return 'no_id_token';
  }
  return text;
}

/// 화면에 보여줄 원본 오류 문자열 (디버깅용)
String googleErrorDebugDump(Object e) {
  final text = e.toString();
  if (text.length <= 400) return text;
  return '${text.substring(0, 400)}…';
}

/// 성공 시 idToken, 취소 시 null. 실패는 throw.
Future<String?> obtainGoogleIdToken() async {
  debugPrint('[google] native sign-in start');
  // 이전 실패 세션이 남아 있으면 12500이 반복될 수 있어 정리
  try {
    await googleSignIn.signOut();
  } catch (_) {}
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
