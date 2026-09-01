import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 설치(첫 실행) 후 이 기간이 지나야 배너 광고 표시
const Duration kBannerGracePeriod = Duration(days: 7);

DateTime? _cachedGraceStart;

/// 배너 유예 시작 시각. 재설치 시 갱신되는 OS 설치 시각 우선.
Future<DateTime> bannerGraceStartAt() async {
  if (_cachedGraceStart != null) return _cachedGraceStart!;
  try {
    final info = await PackageInfo.fromPlatform();
    final installTime = info.installTime;
    if (installTime != null) {
      _cachedGraceStart = installTime;
      debugPrint(
        '[ads] banner grace start (installTime): $_cachedGraceStart',
      );
      return _cachedGraceStart!;
    }
  } catch (e, st) {
    debugPrint('[ads] installTime read failed: $e\n$st');
  }

  final now = DateTime.now();
  _cachedGraceStart = now;
  debugPrint('[ads] banner grace start (fallback now): $now');
  return now;
}

/// 설치 후 [kBannerGracePeriod] 경과 여부
Future<bool> isBannerGraceElapsed() async {
  final start = await bannerGraceStartAt();
  final elapsed = DateTime.now().difference(start) >= kBannerGracePeriod;
  debugPrint(
    '[ads] banner grace elapsed=$elapsed '
    '(started $start, period ${kBannerGracePeriod.inMinutes}m)',
  );
  return elapsed;
}

/// 유예가 끝나는 시각. 이미 지났으면 null.
Future<Duration?> bannerGraceRemaining() async {
  final start = await bannerGraceStartAt();
  final left = kBannerGracePeriod - DateTime.now().difference(start);
  if (left <= Duration.zero) return null;
  return left;
}
