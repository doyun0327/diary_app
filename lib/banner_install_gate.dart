import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 설치(첫 실행) 후 이 기간이 지나야 배너 광고 표시
const Duration kBannerGracePeriod = Duration(days: 7);

const String _kFirstOpenFile = 'pageby_first_open_ms.txt';

DateTime? _cachedFirstOpen;

/// 첫 실행 시각을 기록하고 반환. 이미 있으면 저장된 값.
Future<DateTime> ensureFirstOpenAt() async {
  if (_cachedFirstOpen != null) return _cachedFirstOpen!;
  try {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/$_kFirstOpenFile');
    if (await file.exists()) {
      final ms = int.tryParse((await file.readAsString()).trim());
      if (ms != null && ms > 0) {
        _cachedFirstOpen = DateTime.fromMillisecondsSinceEpoch(ms);
        return _cachedFirstOpen!;
      }
    }
    final now = DateTime.now();
    await file.writeAsString('${now.millisecondsSinceEpoch}');
    _cachedFirstOpen = now;
    return now;
  } catch (e, st) {
    debugPrint('[ads] first-open record failed: $e\n$st');
    // 실패 시 배너를 바로 띄우지 않도록 "지금"으로 취급 (유예 시작)
    _cachedFirstOpen = DateTime.now();
    return _cachedFirstOpen!;
  }
}

/// 첫 실행 후 [kBannerGracePeriod] 경과 여부
Future<bool> isBannerGraceElapsed() async {
  final first = await ensureFirstOpenAt();
  return DateTime.now().difference(first) >= kBannerGracePeriod;
}

/// 유예가 끝나는 시각. 이미 지났으면 null.
Future<Duration?> bannerGraceRemaining() async {
  final first = await ensureFirstOpenAt();
  final left = kBannerGracePeriod - DateTime.now().difference(first);
  if (left <= Duration.zero) return null;
  return left;
}
