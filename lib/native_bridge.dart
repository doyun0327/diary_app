import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'google_auth_native.dart';

const kDiaryNativeChannel = 'DiaryNative';
const kDiaryFilesChannel = MethodChannel('diary/files');

final GlobalKey<ScaffoldMessengerState> diaryMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

void Function(String uri, String mime)? savedFileNotice;

Future<void> handleDiaryNativeMessage(JavaScriptMessage message) async {
  try {
    final decoded = jsonDecode(message.message);
    if (decoded is! Map) return;
    final data = decoded.cast<String, dynamic>();
    final type = data['type'] as String? ?? 'share';

    if (type == 'googleSignIn') {
      enqueueNativeGoogleSignIn();
      return;
    }
    if (type == 'googleSignOut') {
      await nativeGoogleSignOut();
      return;
    }

    final title = (data['title'] as String?)?.trim() ?? '';
    final text = (data['text'] as String?)?.trim() ?? '';
    final url = (data['url'] as String?)?.trim() ?? '';

    if (type == 'saveFile') {
      final name = (data['name'] as String?)?.trim();
      final mime = (data['mime'] as String?)?.trim();
      final base64 = data['base64'] as String?;
      if (name == null || name.isEmpty || base64 == null || base64.isEmpty) {
        return;
      }
      await _saveFileLocally(
        name,
        mime == null || mime.isEmpty ? 'application/octet-stream' : mime,
        base64Decode(base64),
      );
      return;
    }

    if (type == 'shareFile') {
      final name = (data['name'] as String?)?.trim();
      final mime = (data['mime'] as String?)?.trim();
      final base64 = data['base64'] as String?;
      if (name == null || name.isEmpty || base64 == null || base64.isEmpty) {
        return;
      }
      final file = await _fileFromBase64(
        base64,
        name,
        mime == null || mime.isEmpty ? 'application/octet-stream' : mime,
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [file],
          text: _shareBody(text: text, url: url),
          title: title.isEmpty ? null : title,
          subject: title.isEmpty ? null : title,
        ),
      );
      return;
    }

    final body = _shareBody(text: text, url: url);
    if (body == null) return;
    await SharePlus.instance.share(
      ShareParams(
        text: body,
        title: title.isEmpty ? null : title,
        subject: title.isEmpty ? null : title,
      ),
    );
  } catch (e, st) {
    debugPrint('DiaryNative share failed: $e\n$st');
  }
}

String? _shareBody({required String text, required String url}) {
  final parts = <String>[
    if (text.isNotEmpty) text,
    if (url.isNotEmpty) url,
  ];
  if (parts.isEmpty) return null;
  return parts.join('\n\n');
}

Future<XFile> _fileFromBase64(String base64, String name, String mime) async {
  final bytes = base64Decode(base64);
  final safeName = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$safeName');
  await file.writeAsBytes(bytes, flush: true);
  return XFile(file.path, mimeType: mime, name: safeName);
}

Future<void> _saveFileLocally(String name, String mime, Uint8List bytes) async {
  final safeName = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  if (Platform.isAndroid) {
    Future<String?> trySave() async {
      try {
        return await kDiaryFilesChannel.invokeMethod<String>('saveToDownloads', {
          'name': safeName,
          'mime': mime,
          'bytes': bytes,
        });
      } catch (e) {
        debugPrint('saveToDownloads failed: $e');
        return null;
      }
    }

    var uri = await trySave();
    if (uri == null || uri.isEmpty) {
      final status = await Permission.storage.request();
      if (status.isGranted) uri = await trySave();
    }
    if (uri != null && uri.isNotEmpty) {
      _announceSavedFile(uri: uri, mime: mime);
      return;
    }
  }

  final dir = Platform.isIOS
      ? await getApplicationDocumentsDirectory()
      : await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/$safeName');
  await file.writeAsBytes(bytes, flush: true);
  _announceSavedFile(uri: file.path, mime: mime);
}

Future<void> openSavedFile(String uri, String mime) async {
  try {
    await kDiaryFilesChannel.invokeMethod<bool>('openSavedFile', {
      'uri': uri,
      'mime': mime,
    });
  } catch (e) {
    debugPrint('openSavedFile failed: $e');
    _snack('파일을 열 수 없어요.');
  }
}

bool handleSavedFileNotification(String? payload) {
  if (payload == null || payload.isEmpty) return false;
  try {
    final decoded = jsonDecode(payload);
    if (decoded is! Map) return false;
    if (decoded['type']?.toString() != 'openFile') return false;
    final uri = decoded['uri']?.toString() ?? '';
    final mime = decoded['mime']?.toString() ?? 'application/octet-stream';
    if (uri.isEmpty) return false;
    openSavedFile(uri, mime);
    return true;
  } catch (_) {
    return false;
  }
}

void _announceSavedFile({required String uri, required String mime}) {
  diaryMessengerKey.currentState?.hideCurrentMaterialBanner();
  savedFileNotice?.call(uri, mime);
}

void _snack(String message) {
  diaryMessengerKey.currentState?.showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
  );
}
