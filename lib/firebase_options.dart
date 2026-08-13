import 'package:firebase_core/firebase_core.dart';

/// Firebase 콘솔 값으로 채우세요. 비어 있으면 푸시를 건너뜁니다.
/// Android는 `android/app/google-services.json` 도 같이 넣어야 getToken 이 됩니다.
class DiaryFirebaseOptions {
  static const _apiKey = 'AIzaSyDpfX8hFwxtwsL0Bvp1kRHZcSfneDgiMU0';
  static const _appId = '1:511504695762:android:2dc39a8eb5e3a6ec8c480b';
  static const _messagingSenderId = '511504695762';
  static const _projectId = 'project-71a14b25-7c8b-4ead-a73';
  static const _storageBucket = 'project-71a14b25-7c8b-4ead-a73.firebasestorage.app';

  static const apiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: _apiKey,
  );
  static const appId = String.fromEnvironment(
    'FIREBASE_APP_ID',
    defaultValue: _appId,
  );
  static const messagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
    defaultValue: _messagingSenderId,
  );
  static const projectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: _projectId,
  );
  static const storageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
    defaultValue: _storageBucket,
  );

  static bool get configured =>
      apiKey.isNotEmpty &&
      appId.isNotEmpty &&
      messagingSenderId.isNotEmpty &&
      projectId.isNotEmpty;

  static FirebaseOptions? toOptions() {
    if (!configured) return null;
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      storageBucket: storageBucket.isEmpty ? null : storageBucket,
    );
  }
}
