import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

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
    final result = await FilePicker.pickFiles(
      type: imagesOnly ? FileType.image : FileType.any,
      allowMultiple: params.mode == FileSelectorMode.openMultiple,
    );
    if (result == null || result.isEmpty) return const [];
    return [
      for (final file in result)
        if (file.path != null && file.path!.isNotEmpty)
          Uri.file(file.path!).toString(),
    ];
  } catch (e, st) {
    debugPrint('file chooser failed: $e\n$st');
    return const [];
  }
}
