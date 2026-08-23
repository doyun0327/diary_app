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
  }

  Future<bool> showForAiDraw() async {
    if (_ad == null) {
      await _preload();
      if (_ad == null) return false;
    }

    final ad = _ad!;
    _ad = null;
    var rewarded = false;
    final completer = Completer<bool>();

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!completer.isCompleted) completer.complete(rewarded);
        unawaited(_preload());
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('rewarded show failed: $error');
        ad.dispose();
        if (!completer.isCompleted) completer.complete(false);
        unawaited(_preload());
      },
    );

    ad.show(
      onUserEarnedReward: (_, rewardItem) {
        rewarded = rewardItem.amount >= 0;
      },
    );

    return completer.future.timeout(
      const Duration(seconds: 70),
      onTimeout: () => false,
    );
  }
}
