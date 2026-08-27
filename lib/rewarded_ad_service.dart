import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class RewardedAdService {
  RewardedAdService._();
  static final RewardedAdService instance = RewardedAdService._();

  RewardedAd? _ad;
  bool _loading = false;
  bool _ready = false;

  /// MobileAds 초기화 완료 여부 (배너는 이 이후에만 로드)
  bool get isReady => _ready;
  final ValueNotifier<bool> readyNotifier = ValueNotifier(false);

  static const _androidTestRewardedId = 'ca-app-pub-3940256099942544/5224354917';
  static const _androidProdRewardedId = 'ca-app-pub-4752729386590212/8307456691';

  static String _rewardedUnitId() {
    const fromDefine = String.fromEnvironment('ADMOB_REWARDED_UNIT_ID');
    if (fromDefine.isNotEmpty) return fromDefine;
    return kReleaseMode ? _androidProdRewardedId : _androidTestRewardedId;
  }

  Future<void> init() async {
    try {
      await MobileAds.instance.initialize();
      _ready = true;
      readyNotifier.value = true;
      unawaited(_preload());
    } catch (e, st) {
      debugPrint('[ads] MobileAds.initialize failed: $e\n$st');
      _ready = false;
      readyNotifier.value = false;
    }
  }

  Future<void> _preload() async {
    if (_loading || _ad != null) return;
    _loading = true;
    try {
      await RewardedAd.load(
        adUnitId: _rewardedUnitId(),
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            _ad = ad;
            _loading = false;
          },
          onAdFailedToLoad: (error) {
            debugPrint('rewarded load failed: $error');
            _loading = false;
          },
        ),
      );
    } catch (e, st) {
      debugPrint('rewarded load threw: $e\n$st');
      _loading = false;
    }
  }

  /// 로드가 콜백 경유라, await load 직후에도 _ad 가 비어 있을 수 있어 짧게 대기.
  Future<RewardedAd?> _awaitLoadedAd({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (_ad != null) return _ad;
    if (!_loading) {
      unawaited(_preload());
    }
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_ad != null) return _ad;
      if (!_loading && _ad == null) {
        // 로드 실패로 끝난 경우
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return _ad;
  }

  Future<bool> showForAiDraw() async {
    final loaded = await _awaitLoadedAd();
    if (loaded == null) {
      debugPrint('rewarded: no ad ready');
      return false;
    }

    final ad = loaded;
    _ad = null;
    var rewarded = false;
    final completer = Completer<bool>();

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        // onUserEarnedReward 와 dismiss 경합 대비
        unawaited(_completeAfterDismiss(completer, () => rewarded));
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('rewarded show failed: $error');
        ad.dispose();
        if (!completer.isCompleted) completer.complete(false);
        unawaited(_preload());
      },
    );

    try {
      await ad.show(
        onUserEarnedReward: (_, rewardItem) {
          // amount 가 0인 네트워크도 있어 콜백 자체로 성공 처리
          rewarded = true;
          debugPrint(
            'rewarded earned: type=${rewardItem.type} amount=${rewardItem.amount}',
          );
        },
      );
    } catch (e, st) {
      debugPrint('rewarded show threw: $e\n$st');
      ad.dispose();
      if (!completer.isCompleted) completer.complete(false);
      unawaited(_preload());
      return false;
    }

    // 닫히거나 실패할 때까지 대기 (연속 광고여도 시간 제한 없음)
    return completer.future;
  }

  Future<void> _completeAfterDismiss(
    Completer<bool> completer,
    bool Function() earned,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final ok = earned();
    if (!completer.isCompleted) {
      debugPrint('rewarded dismiss: earned=$ok');
      completer.complete(ok);
    }
    unawaited(_preload());
  }
}
