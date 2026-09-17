import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 친구방 초대 딥링크 → WebView에 `__diaryOpenFromInvite` 주입
final DiaryInviteBridge diaryInvite = DiaryInviteBridge();

class DiaryInviteBridge {
  WebViewController? controller;
  String? pendingCode;
  StreamSubscription<Uri>? _sub;
  final AppLinks _appLinks = AppLinks();

  Future<void> start() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        _handleUri(initial);
      }
    } catch (e) {
      debugPrint('[invite] getInitialLink failed: $e');
    }
    await _sub?.cancel();
    _sub = _appLinks.uriLinkStream.listen(
      _handleUri,
      onError: (Object e) => debugPrint('[invite] stream error: $e'),
    );
  }

  void dispose() {
    unawaited(_sub?.cancel());
    _sub = null;
  }

  void _handleUri(Uri uri) {
    final code = extractInviteCode(uri);
    if (code == null) return;
    debugPrint('[invite] deep link code=$code uri=$uri');
    unawaited(injectOpen(code));
  }

  /// https://…/join?code= / pageby://join?code= / /join/CODE
  static String? extractInviteCode(Uri uri) {
    final fromQuery = _normalize(uri.queryParameters['code']);
    if (_isValid(fromQuery)) return fromQuery;

    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    // /join/CODE 또는 host=join 이고 path에 코드
    if (segments.isNotEmpty && segments.first.toLowerCase() == 'join') {
      if (segments.length >= 2) {
        final c = _normalize(segments[1]);
        if (_isValid(c)) return c;
      }
    }
    if (uri.scheme == 'pageby' && uri.host.toLowerCase() == 'join') {
      final pathCode =
          uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
      final c = _normalize(uri.queryParameters['code'] ?? pathCode);
      if (_isValid(c)) return c;
    }
    return null;
  }

  static String _normalize(String? raw) {
    if (raw == null) return '';
    return raw.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
  }

  static bool _isValid(String code) {
    return code.length == 8 || RegExp(r'^\d{6}$').hasMatch(code);
  }

  Future<void> injectOpen(String code) async {
    final c = _normalize(code);
    if (!_isValid(c)) return;
    final web = controller;
    if (web == null) {
      pendingCode = c;
      return;
    }
    final js = jsonEncode({'code': c});
    await web.runJavaScript('''
      window.__diaryOpenFromInvite = $js;
      window.dispatchEvent(new CustomEvent('diary-invite-open', { detail: $js }));
    ''');
    pendingCode = null;
  }

  Future<void> flushPending() async {
    final code = pendingCode;
    if (code != null) {
      await injectOpen(code);
    }
  }
}
