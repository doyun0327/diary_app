import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'firebase_options.dart';

const kDiaryPushChannelId = 'diary_room';

final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

final DiaryPushBridge diaryPush = DiaryPushBridge();

class DiaryPushBridge {
  WebViewController? controller;
  String? token;
  Map<String, String>? pendingOpen;

  Future<void> injectToken() async {
    final value = token;
    final web = controller;
    if (value == null || value.isEmpty || web == null) return;
    final jsToken = jsonEncode(value);
    await web.runJavaScript('''
      window.__diaryPushToken = $jsToken;
      window.dispatchEvent(new Event('diary-push-token'));
    ''');
  }

  Future<void> injectOpen(Map<String, String> payload) async {
    final web = controller;
    if (web == null) {
      pendingOpen = payload;
      return;
    }
    final js = jsonEncode(payload);
    await web.runJavaScript('''
      window.__diaryOpenFromPush = $js;
      window.dispatchEvent(new CustomEvent('diary-push-open', { detail: $js }));
    ''');
    pendingOpen = null;
  }

  Future<void> flushPending() async {
    await injectToken();
    final open = pendingOpen;
    if (open != null) {
      await injectOpen(open);
    }
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // 백그라운드는 FCM notification 페이로드로 시스템 알림이 뜹니다.
}

Future<void> initDiaryPush() async {
  final options = DiaryFirebaseOptions.toOptions();
  if (options == null) {
    debugPrint(
      '[push] Firebase options empty. '
      'Set FIREBASE_* or fill DiaryFirebaseOptions / google-services.json',
    );
    return;
  }

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: options);
    }
  } catch (e) {
    debugPrint('[push] Firebase.initializeApp failed: $e');
    return;
  }

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await _local.initialize(
    const InitializationSettings(android: androidInit),
    onDidReceiveNotificationResponse: (response) {
      final payload = _parsePayload(response.payload);
      if (payload != null) {
        diaryPush.injectOpen(payload);
      }
    },
  );

  const channel = AndroidNotificationChannel(
    kDiaryPushChannelId,
    '친구 방',
    description: '일기 공유와 댓글 알림',
    importance: Importance.high,
  );
  await _local
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);

  final notif = await Permission.notification.request();
  if (!notif.isGranted) {
    debugPrint('[push] notification permission denied');
  }

  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  try {
    diaryPush.token = await FirebaseMessaging.instance.getToken();
    debugPrint('[push] token=${diaryPush.token}');
    await diaryPush.injectToken();
  } catch (e) {
    debugPrint('[push] getToken failed: $e');
  }

  FirebaseMessaging.instance.onTokenRefresh.listen((value) {
    diaryPush.token = value;
    diaryPush.injectToken();
  });

  FirebaseMessaging.onMessage.listen(_showForeground);
  FirebaseMessaging.onMessageOpenedApp.listen((message) {
    final payload = _dataFromMessage(message);
    if (payload != null) {
      diaryPush.injectOpen(payload);
    }
  });

  final initial = await FirebaseMessaging.instance.getInitialMessage();
  if (initial != null) {
    final payload = _dataFromMessage(initial);
    if (payload != null) {
      diaryPush.pendingOpen = payload;
    }
  }
}

void _showForeground(RemoteMessage message) {
  final title = message.notification?.title ?? message.data['title'] ?? 'PageBy';
  final body =
      message.notification?.body ?? message.data['body'] ?? '';
  final payload = _dataFromMessage(message);
  _local.show(
    message.hashCode,
    title,
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        kDiaryPushChannelId,
        '친구 방',
        channelDescription: '일기 공유와 댓글 알림',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
    ),
    payload: payload == null ? null : jsonEncode(payload),
  );
}

Map<String, String>? _dataFromMessage(RemoteMessage message) {
  final roomId = message.data['roomId']?.toString().trim();
  if (roomId == null || roomId.isEmpty) return null;
  return {
    'type': message.data['type']?.toString() ?? '',
    'roomId': roomId,
    'postId': message.data['postId']?.toString() ?? '',
  };
}

Map<String, String>? _parsePayload(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final roomId = decoded['roomId']?.toString().trim();
    if (roomId == null || roomId.isEmpty) return null;
    return {
      'type': decoded['type']?.toString() ?? '',
      'roomId': roomId,
      'postId': decoded['postId']?.toString() ?? '',
    };
  } catch (_) {
    return null;
  }
}
