import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'native_bridge.dart';

/// Android WebView의 &lt;input type="file"&gt; 을 네이티브 선택기로 연결
Future<void> attachAndroidFileChooser(WebViewController controller) async {
  if (WebViewPlatform.instance is! AndroidWebViewPlatform) return;
  final android = controller.platform as AndroidWebViewController;
  await android.setOnShowFileSelector(_pickFiles);
}

Future<List<String>> _pickFiles(FileSelectorParams params) async {
  try {
    final imagesOnly = params.acceptTypes.any(
      (type) => type.contains('image'),
    );
    final allowMultiple = params.mode == FileSelectorMode.openMultiple;

    if (imagesOnly) {
      // 시스템 Photo Picker는 갤러리 앱에 있는 사진(카톡 등)을 빼먹는 경우가 많음.
      // 기기 갤러리 앱(ACTION_PICK)을 열어 갤러리에 보이는 사진을 전부 고르게 함.
      return _pickImagesFromDeviceGallery(allowMultiple: allowMultiple);
    }

    if (allowMultiple) {
      final files = await FilePicker.pickFiles(type: FileType.any);
      return _platformFilesToUris(files);
    }

    final file = await FilePicker.pickFile(type: FileType.any);
    if (file == null) return const [];
    return _platformFilesToUris([file]);
  } catch (e, st) {
    debugPrint('file chooser failed: $e\n$st');
    return const [];
  }
}

Future<List<String>> _pickImagesFromDeviceGallery({
  required bool allowMultiple,
}) async {
  if (!allowMultiple) {
    try {
      final path = await kDiaryFilesChannel.invokeMethod<String>(
        'pickGalleryImage',
      );
      if (path != null && path.isNotEmpty) {
        return [Uri.file(path).toString()];
      }
      return const [];
    } on PlatformException catch (e) {
      debugPrint('pickGalleryImage failed: $e — fallback FilePicker');
    } catch (e) {
      debugPrint('pickGalleryImage error: $e — fallback FilePicker');
    }
  }

  if (allowMultiple) {
    final files = await FilePicker.pickFiles(type: FileType.image);
    return _platformFilesToUris(files);
  }

  final file = await FilePicker.pickFile(type: FileType.image);
  if (file == null) return const [];
  return _platformFilesToUris([file]);
}

Future<List<String>> _platformFilesToUris(List<PlatformFile> files) async {
  final uris = <String>[];
  for (final file in files) {
    final local = await _ensureLocalFilePath(file);
    if (local == null || local.isEmpty) continue;
    uris.add(Uri.file(local).toString());
  }
  return uris;
}

Future<String?> _ensureLocalFilePath(PlatformFile file) async {
  final path = file.path;
  if (path != null && path.isNotEmpty) {
    try {
      if (await File(path).exists()) return path;
    } catch (_) {
      // fall through
    }
  }

  try {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    final dir = await getTemporaryDirectory();
    final safeName = file.name.replaceAll(RegExp(r'[^\w.\-]+'), '_');
    final out = File(
      '${dir.path}/webview_pick_${DateTime.now().millisecondsSinceEpoch}_$safeName',
    );
    await out.writeAsBytes(bytes, flush: true);
    return out.path;
  } catch (e) {
    debugPrint('materialize pick failed (${file.name}): $e');
    return null;
  }
}
