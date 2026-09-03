/// RevenueCat · 스토어 설정 (대시보드·Play/App Store와 동일하게 맞출 것)
class SubscriptionConfig {
  SubscriptionConfig._();

  /// RevenueCat Public API Key (Google Play 앱)
  /// `--dart-define=REVENUECAT_GOOGLE_KEY=goog_...` 로 덮어쓸 수 있음
  static const googleApiKey = String.fromEnvironment(
    'REVENUECAT_GOOGLE_KEY',
    defaultValue: 'goog_mFwrKRFoWrokuNCgJcnROmjTMlb',
  );

  /// RevenueCat Public API Key (App Store 앱)
  static const appleApiKey = String.fromEnvironment(
    'REVENUECAT_APPLE_KEY',
    defaultValue: 'appl_REPLACE_ME',
  );

  /// RevenueCat Entitlement ID
  static const entitlementId = 'premium';

  /// Play Console / App Store Connect 상품 ID
  static const productId = 'pageby_monthly';

  /// 개발자 츄르(후원) 소모성 상품
  static const tipProductIds = <String>[
    'pageby_churu_1',
    'pageby_churu_3',
    'pageby_churu_box',
  ];

  static bool isTipProduct(String? productId) {
    if (productId == null || productId.isEmpty) return false;
    if (productId.contains('churu')) return true;
    return tipProductIds.contains(productId);
  }
}
