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
import 'rewarded_ad_service.dart';
import 'subscription_service.dart';
import 'webview_host.dart';

const kDiaryNativeChannel = 'DiaryNative';
const kDiaryFilesChannel = MethodChannel('diary/files');

class DiaryAppBarState {
  const DiaryAppBarState({
    this.visible = false,
    this.showBanner = false,
    this.showCalendar = false,
    this.showBack = false,
    this.showSave = false,
    this.showMenu = true,
    this.showSearch = false,
    this.label = '',
    this.saveLabel = '',
    this.saveEnabled = true,
  });

  final bool visible;
  /// 무료 사용자 하단 배너 — AppBar(visible)와 별개 (PageBy·쓰기·상세 포함)
  final bool showBanner;
  final bool showCalendar;
  final bool showBack;
  final bool showSave;
  final bool showMenu;
  final bool showSearch;
  final String label;
  final String saveLabel;
  final bool saveEnabled;
}

final ValueNotifier<DiaryAppBarState> diaryAppBar =
    ValueNotifier(const DiaryAppBarState());

final GlobalKey<ScaffoldMessengerState> diaryMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

void Function(String uri, String mime)? savedFileNotice;
Future<void> Function(String title, String body)? aiDrawCompleteNotice;

Future<void> handleDiaryNativeMessage(JavaScriptMessage message) async {
  // 릴리스에서도 logcat에 보이도록 print 사용 (debugPrint는 필터에 안 잡힐 수 있음)
  print('[DiaryNative] ${message.message}');
  try {
    final decoded = jsonDecode(message.message);
    if (decoded is! Map) return;
    final data = decoded.cast<String, dynamic>();
    final type = data['type'] as String? ?? 'share';
    print('[DiaryNative] type=$type');

    if (type == 'googleSignIn') {
      enqueueNativeGoogleSignIn();
      return;
    }
    if (type == 'googleSignOut') {
      await nativeGoogleSignOut();
      return;
    }
    if (type == 'headerState') {
      final next = DiaryAppBarState(
        visible: data['visible'] == true,
        // 구버전 웹: showBanner 없으면 AppBar 보일 때만 배너
        showBanner: data.containsKey('showBanner')
            ? data['showBanner'] == true
            : data['visible'] == true,
        showCalendar: data['showCalendar'] == true,
        showBack: data['showBack'] == true,
        showSave: data['showSave'] == true,
        showMenu: data['showMenu'] != false,
        showSearch: data['showSearch'] == true,
        label: (data['label'] as String?)?.trim() ?? '',
        saveLabel: (data['saveLabel'] as String?)?.trim() ?? '',
        saveEnabled: data['saveEnabled'] != false,
      );
      debugPrint(
        '[headerState] visible=${next.visible} banner=${next.showBanner} '
        'back=${next.showBack} label="${next.label}"',
      );
      diaryAppBar.value = next;
      return;
    }
    if (type == 'subscriptionIdentify') {
      final userId = (data['userId'] as String?)?.trim() ?? '';
      if (userId.isNotEmpty) {
        await SubscriptionService.instance.identify(userId);
      }
      return;
    }
    if (type == 'subscriptionSync') {
      await SubscriptionService.instance.syncToWeb();
      return;
    }
    if (type == 'subscriptionPurchase') {
      final productId = (data['productId'] as String?)?.trim();
      try {
        await SubscriptionService.instance.purchaseSubscription(
          productId: productId,
        );
      } catch (e, st) {
        debugPrint('subscription purchase failed: $e\n$st');
      } finally {
        // 결제창/이미가입 시트 닫힌 뒤에도 Pro 상태 한 번 더 맞춤
        try {
          await SubscriptionService.instance.syncToWeb();
        } catch (_) {}
      }
      return;
    }
    if (type == 'subscriptionRestore') {
      try {
        await SubscriptionService.instance.restore();
      } catch (e, st) {
        debugPrint('subscription restore failed: $e\n$st');
      }
      return;
    }
    if (type == 'tipPurchase') {
      final productId = (data['productId'] as String?)?.trim() ?? '';
      print('[iap] tipPurchase from web productId=$productId');
      debugPrint('[iap] tipPurchase from web productId=$productId');
      if (productId.isEmpty) {
        await WebViewHost.instance.dispatchTipPurchaseComplete(
          ok: false,
          error: 'invalid_product',
        );
        return;
      }
      try {
        final handled =
            await SubscriptionService.instance.purchaseTip(productId);
        if (!handled) {
          await WebViewHost.instance.dispatchTipPurchaseComplete(
            ok: false,
            productId: productId,
            error: 'purchase_failed',
          );
        }
      } catch (e, st) {
        debugPrint('tip purchase failed: $e\n$st');
        try {
          await WebViewHost.instance.dispatchTipPurchaseComplete(
            ok: false,
            productId: productId,
            error: 'purchase_failed',
          );
        } catch (_) {}
      }
      return;
    }
    if (type == 'tipProducts') {
      try {
        await SubscriptionService.instance.fetchTipProducts();
      } catch (e, st) {
        debugPrint('tip products fetch failed: $e\n$st');
        try {
          await WebViewHost.instance.dispatchTipProducts(products: const []);
        } catch (_) {}
      }
      return;
    }
    if (type == 'rewardedAdShow') {
      final reason = (data['reason'] as String?)?.trim() ?? 'aiDraw';
      final ok = await RewardedAdService.instance.showForAiDraw();
      await WebViewHost.instance.dispatchRewardedAdResult(ok: ok, reason: reason);
      if (!ok) {
        // 웹 쪽에서 모달로 안내 (중복 스낵 방지)
      }
      return;
    }
    if (type == 'aiDrawComplete') {
      final title = (data['title'] as String?)?.trim();
      final body = (data['body'] as String?)?.trim();
      final notify = aiDrawCompleteNotice;
      if (notify != null) {
        await notify(
          title == null || title.isEmpty ? '그림이 완성되었어요!' : title,
          body == null || body.isEmpty
              ? '그림을 확인해 보세요.💛'
              : body,
        );
      }
      return;
    }
    if (type == 'theme') {
      final themeId = (data['themeId'] as String?)?.trim() ?? 'paper';
      final accentHex = (data['accent'] as String?)?.trim() ?? '#2A2A2A';
      final backgroundHex = (data['background'] as String?)?.trim() ?? '#FFFFFF';
      try {
        diaryTheme.value = DiaryThemeState(
          themeId: themeId,
          accent: _hexToColor(accentHex),
          background: _hexToColor(backgroundHex),
        );
      } catch (_) {
        diaryTheme.value = DiaryThemeState(themeId: themeId);
      }
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
      // WebView 모달 닫힘과 겹치면 첫 공유 시트가 바로 닫히는 기기 있음
      await Future<void>.delayed(const Duration(milliseconds: 120));
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
    await Future<void>.delayed(const Duration(milliseconds: 80));
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

class DiaryThemeState {
  const DiaryThemeState({
    this.themeId = 'paper',
    this.accent = const Color(0xFF2A2A2A),
    this.background = const Color(0xFFFFFFFF),
  });

  final String themeId;
  final Color accent;
  final Color background;
}

final ValueNotifier<DiaryThemeState> diaryTheme =
    ValueNotifier(const DiaryThemeState());

Color _hexToColor(String value) {
  final hex = value.trim();
  if (hex.startsWith('#')) {
    final body = hex.substring(1);
    final normalized = body.length == 3
        ? body.split('').expand((c) => [c, c]).join()
        : body;
    final parsed = int.tryParse(normalized, radix: 16);
    if (parsed == null) return const Color(0xFF2A2A2A);
    return Color((0xFF000000 | parsed));
  }
  return const Color(0xFF2A2A2A);
}
