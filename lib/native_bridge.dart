import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'google_auth_native.dart';

const kDiaryNativeChannel = 'DiaryNative';

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
