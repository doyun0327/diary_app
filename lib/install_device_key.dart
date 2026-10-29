import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'native_bridge.dart';

/// 재설치에도 가능한 한 유지되는 네이티브 기기 키.
/// Android: ANDROID_ID (`a:…`), iOS: Keychain UUID (`i:…`).
Future<String?> getInstallDeviceKey() async {
  if (kIsWeb) return null;
  try {
    if (!Platform.isAndroid && !Platform.isIOS) return null;
    final key = await kDiaryFilesChannel.invokeMethod<String>('getInstallDeviceKey');
    final trimmed = key?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    return trimmed;
  } on PlatformException catch (e) {
    debugPrint('[installDeviceKey] $e');
    return null;
  } catch (e) {
    debugPrint('[installDeviceKey] $e');
    return null;
  }
}
