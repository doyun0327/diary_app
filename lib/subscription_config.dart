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
  static const monthlyProductId = 'pageby_monthly';
  static const yearlyProductId = 'pageby_yearly';

  /// 하위 호환 (월간)
  static const productId = monthlyProductId;

  static const subscriptionProductIds = <String>[
    monthlyProductId,
    yearlyProductId,
  ];

  static bool isSubscriptionProduct(String? productId) {
    if (productId == null || productId.isEmpty) return false;
    return subscriptionProductIds.any(
      (id) => productId == id || productId.startsWith('$id:'),
    );
  }

  /// 개발자 츄르(후원) 소모성 상품
  static const tipProductIds = <String>[
    'pageby_churu_1',
    'pageby_churu_3',
    'pageby_churu_box',
  ];

  /// AI 그림 추가 구매 (소모성). 웹 `AI_PACK_PRODUCTS` 와 동일 ID·장수.
  /// Play / RevenueCat 에 같은 ID로 등록 필요.
  /// - pageby_ai_draw_3  → 3장 (₩500)
  /// - pageby_ai_draw_10 → 10장
  /// - pageby_ai_draw_20 → 20장
  /// - pageby_ai_draw_50 → 50장
  static const aiPackProducts = <AiPackProduct>[
    AiPackProduct(id: 'pageby_ai_draw_3', credits: 3),
    AiPackProduct(id: 'pageby_ai_draw_10', credits: 10),
    AiPackProduct(id: 'pageby_ai_draw_20', credits: 20),
    AiPackProduct(id: 'pageby_ai_draw_50', credits: 50),
  ];

  static List<String> get aiPackProductIds =>
      aiPackProducts.map((p) => p.id).toList(growable: false);

  static int aiPackCreditsForProduct(String? productId) {
    final id = productId?.trim() ?? '';
    if (id.isEmpty) return 0;
    for (final pack in aiPackProducts) {
      if (id == pack.id || id.startsWith('${pack.id}:')) {
        return pack.credits;
      }
    }
    return 0;
  }

  static bool isTipProduct(String? productId) {
    if (productId == null || productId.isEmpty) return false;
    if (productId.contains('churu')) return true;
    return tipProductIds.contains(productId);
  }

  static bool isAiPackProduct(String? productId) {
    if (productId == null || productId.isEmpty) return false;
    if (aiPackCreditsForProduct(productId) > 0) return true;
    if (productId.contains('ai_draw')) return true;
    return false;
  }

  /// 츄르·AI 팩 등 구독이 아닌 소모성 IAP
  static bool isConsumableProduct(String? productId) {
    return isTipProduct(productId) || isAiPackProduct(productId);
  }
}

class AiPackProduct {
  const AiPackProduct({required this.id, required this.credits});

  final String id;
  final int credits;
}
