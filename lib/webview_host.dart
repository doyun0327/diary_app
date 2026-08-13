import 'dart:convert';

import 'package:webview_flutter/webview_flutter.dart';

class WebViewHost {
  WebViewHost._();
  static final WebViewHost instance = WebViewHost._();

  WebViewController? controller;

  Future<void> runJs(String js) async {
    final web = controller;
    if (web == null) return;
    await web.runJavaScript(js);
  }

  Future<void> dispatchEvent(String name, [Object? detail]) async {
    if (detail == null) {
      await runJs("window.dispatchEvent(new Event(${jsonEncode(name)}));");
      return;
    }
    final payload = jsonEncode(detail);
    await runJs(
      "window.dispatchEvent(new CustomEvent(${jsonEncode(name)}, { detail: $payload }));",
    );
  }
}
