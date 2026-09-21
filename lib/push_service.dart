import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'firebase_options.dart';
import 'native_bridge.dart';

const kDiaryPushChannelId = 'diary_room';
const kDiaryDownloadChannelId = 'diary_download';
const kDiaryAiDrawChannelId = 'diary_ai_draw';

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
  // AI 그림 완료는 data-only 로 오므로, 백그라운드에서만 로컬 알림 표시
  final type = message.data['type']?.toString() ?? '';
  if (type != 'ai_draw_done') {
    // 그 외(방 알림 등)는 notification 페이로드로 시스템 알림
    return;
  }
  try {
    WidgetsFlutterBinding.ensureInitialized();
    final title = (message.data['title'] ?? '그림이 완성되었어요!').toString();
    final body = (message.data['body'] ?? '그림을 확인해 보세요.💛').toString();
    final plugin = FlutterLocalNotificationsPlugin();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await plugin.initialize(const InitializationSettings(android: androidInit));
    const channel = AndroidNotificationChannel(
      kDiaryAiDrawChannelId,
      'AI 그림',
      description: '그림 완성 알림',
      importance: Importance.high,
    );
    await plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
    await plugin.show(
      DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          kDiaryAiDrawChannelId,
          'AI 그림',
          channelDescription: '그림 완성 알림',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: jsonEncode({'type': 'ai_draw_done'}),
    );
  } catch (e, st) {
    debugPrint('[push] ai_draw_done background notify failed: $e\n$st');
  }
}

Future<void> initDiaryPush() async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await _local.initialize(
    const InitializationSettings(android: androidInit),
    onDidReceiveNotificationResponse: (response) {
      if (handleSavedFileNotification(response.payload)) return;
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

  const downloadChannel = AndroidNotificationChannel(
    kDiaryDownloadChannelId,
    '다운로드',
    description: '일기장 PDF 저장',
    importance: Importance.high,
  );
  await _local
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(downloadChannel);

  const aiDrawChannel = AndroidNotificationChannel(
    kDiaryAiDrawChannelId,
    'AI 그림',
    description: '그림 완성 알림',
    importance: Importance.high,
  );
  await _local
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(aiDrawChannel);

  savedFileNotice = showSavedFileNotification;
  aiDrawCompleteNotice = showAiDrawCompleteNotification;

  final notif = await Permission.notification.request();
  if (!notif.isGranted) {
    debugPrint('[push] notification permission denied');
  }

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

Future<void> showSavedFileNotification(String uri, String mime) async {
  await _local.show(
    uri.hashCode & 0x7fffffff,
    '일기를 저장했어요.',
    '소중한 추억을 오래 간직해보세요. 💛',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        kDiaryDownloadChannelId,
        '다운로드',
        channelDescription: '일기장 PDF 저장',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
    ),
    payload: jsonEncode({
      'type': 'openFile',
      'uri': uri,
      'mime': mime,
    }),
  );
}

Future<void> showAiDrawCompleteNotification(String title, String body) async {
  await _local.show(
    DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
    title,
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        kDiaryAiDrawChannelId,
        'AI 그림',
        channelDescription: '그림 완성 알림',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    ),
    payload: jsonEncode({'type': 'aiDrawComplete'}),
  );
}

void _showForeground(RemoteMessage message) {
  final type = message.data['type']?.toString() ?? '';
  // AI 그림 완료: 포그라운드면 쓰기 화면에서 이미 결과를 보여 주므로 알림 생략
  // (백그라운드/종료는 FCM notification 페이로드로 시스템 알림)
  if (type == 'ai_draw_done') {
    debugPrint('[push] skip foreground ai_draw_done');
    return;
  }

  final title = (message.notification?.title ??
          message.data['title']?.toString() ??
          '')
      .trim();
  final body = (message.notification?.body ??
          message.data['body']?.toString() ??
          message.data['pushBody']?.toString() ??
          '')
      .trim();

  // 본문 없는 "pageBy" 알림은 만들지 않음.
  // (OEM이 FCM 시스템 알림 + 로컬 알림을 같이 띄운 뒤,
  //  내용 있는 쪽을 밀면 빈 알림만 남는 현상 방지)
  if (body.isEmpty) {
    debugPrint(
      '[push] skip empty foreground notification '
      'title="$title" data=${message.data}',
    );
    return;
  }

  final displayTitle = title.isEmpty ? 'pageBy' : title;
  final payload = _dataFromMessage(message);
  final id = _notificationIdFor(message);
  final tag = _notificationTagFor(message);

  _local.show(
    id,
    displayTitle,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        kDiaryPushChannelId,
        '친구 방',
        channelDescription: '일기 공유와 댓글 알림',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        autoCancel: true,
        tag: tag,
      ),
    ),
    payload: payload == null ? null : jsonEncode(payload),
  );
}

/// 같은 방/게시글 알림은 덮어써서 스택·빈 요약 알림을 줄임
int _notificationIdFor(RemoteMessage message) {
  final roomId = message.data['roomId']?.toString() ?? '';
  final postId = message.data['postId']?.toString() ?? '';
  final type = message.data['type']?.toString() ?? '';
  final key = '$type|$roomId|$postId';
  if (key == '||') {
    final mid = message.messageId;
    if (mid != null && mid.isNotEmpty) return mid.hashCode & 0x7fffffff;
    return message.hashCode & 0x7fffffff;
  }
  return key.hashCode & 0x7fffffff;
}

String? _notificationTagFor(RemoteMessage message) {
  final roomId = message.data['roomId']?.toString().trim() ?? '';
  final postId = message.data['postId']?.toString().trim() ?? '';
  if (roomId.isEmpty) return null;
  return postId.isEmpty ? 'room_$roomId' : 'room_${roomId}_$postId';
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
