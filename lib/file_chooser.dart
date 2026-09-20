import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
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

    // 사진만 필요할 때는 시스템 앨범(Photo Picker)을 연다.
    // file_picker(FileType.image)는 문서/파일 UI로 열려 앨범이 바로 안 보이는 경우가 많음.
    if (imagesOnly) {
      return _pickImagesFromGallery(
        allowMultiple: params.mode == FileSelectorMode.openMultiple,
      );
    }

    final allowMultiple = params.mode == FileSelectorMode.openMultiple;
    if (allowMultiple) {
      final files = await FilePicker.pickFiles(type: FileType.any);
      return [
        for (final file in files)
          if (file.path != null && file.path!.isNotEmpty)
            Uri.file(file.path!).toString(),
      ];
    }

    final file = await FilePicker.pickFile(type: FileType.any);
    final path = file?.path;
    if (path == null || path.isEmpty) return const [];
    return [Uri.file(path).toString()];
  } catch (e, st) {
    debugPrint('file chooser failed: $e\n$st');
    return const [];
  }
}

Future<List<String>> _pickImagesFromGallery({required bool allowMultiple}) async {
  final picker = ImagePicker();
  if (allowMultiple) {
    final files = await picker.pickMultiImage(
      // WebView로 넘기기 전 과도한 원본을 줄임 (AI/아바타 모두 충분)
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 92,
    );
    return [
      for (final file in files)
        if (file.path.isNotEmpty) Uri.file(file.path).toString(),
    ];
  }

  final file = await picker.pickImage(
    source: ImageSource.gallery,
    maxWidth: 2048,
    maxHeight: 2048,
    imageQuality: 92,
  );
  if (file == null || file.path.isEmpty) return const [];
  return [Uri.file(file.path).toString()];
}
