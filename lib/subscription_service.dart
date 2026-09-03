import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'subscription_config.dart';
import 'webview_host.dart';

class SubscriptionService {
  SubscriptionService._();
  static final SubscriptionService instance = SubscriptionService._();

  var _configured = false;
  final ValueNotifier<bool> activeNotifier = ValueNotifier(false);

  Future<void> init() async {
    if (_configured) return;
    if (kIsWeb) return;

    final apiKey = Platform.isIOS
        ? SubscriptionConfig.appleApiKey
        : SubscriptionConfig.googleApiKey;

    if (apiKey.contains('REPLACE_ME')) {
      debugPrint(
        '[subscription] RevenueCat API key not set. '
        'See docs/REVENUECAT_SETUP.md',
      );
      return;
    }

    await Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.warn);
    final config = PurchasesConfiguration(apiKey);
    try {
      await Purchases.configure(config);
      _configured = true;
    } catch (e, st) {
      debugPrint('[subscription] configure failed: $e\n$st');
      return;
    }

    Purchases.addCustomerInfoUpdateListener((info) {
      unawaited(_pushStatus(info));
    });

    try {
      final info = await Purchases.getCustomerInfo();
      await _pushStatus(info);
    } catch (e, st) {
      debugPrint('[subscription] getCustomerInfo failed: $e\n$st');
    }
  }

  Future<void> identify(String userId) async {
    if (!_configured || userId.trim().isEmpty) return;
    try {
      final result = await Purchases.logIn(userId.trim());
      await _pushStatus(result.customerInfo);
    } catch (e, st) {
      debugPrint('[subscription] identify failed: $e\n$st');
    }
  }

  Future<void> syncToWeb() async {
    // 초기화 전 false 푸시는 웹의 기존 Pro 상태를 지워 버림 → 무시
    if (!_configured) {
      debugPrint('[subscription] sync skipped (not configured yet)');
      return;
    }
    try {
      final info = await Purchases.getCustomerInfo();
      await _pushStatus(info);
    } catch (e, st) {
      debugPrint('[subscription] sync failed: $e\n$st');
    }
  }

  Future<void> purchaseMonthly() async {
    if (!_configured) {
      throw PlatformException(
        code: 'not_configured',
        message: 'RevenueCat is not configured',
      );
    }

    // 이미 활성 구독이면 Play "이미 가입됨" 시트 대신 Pro만 동기화
    if (await _refreshAndPushIfPremium(reason: 'pre-purchase')) {
      return;
    }

    final offerings = await Purchases.getOfferings();
    final current = offerings.current;
    Package? package;
    if (current != null) {
      for (final p in current.availablePackages) {
        if (p.storeProduct.identifier == SubscriptionConfig.productId) {
          package = p;
          break;
        }
      }
      package ??= current.monthly;
      if (package == null && current.availablePackages.isNotEmpty) {
        package = current.availablePackages.first;
      }
    }

    if (package == null) {
      throw PlatformException(
        code: 'no_package',
        message: 'No subscription package found in RevenueCat offerings',
      );
    }

    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      await _applyPurchasedInfo(result.customerInfo);
      if (!_isPremium(result.customerInfo)) {
        // 결제 성공인데 entitlement 지연이면 Play 기준 Pro 강제 반영
        await _forceProToWeb(info: result.customerInfo);
      }
    } catch (e, st) {
      final code = _safeErrorCode(e);
      final alreadyOwned = code == PurchasesErrorCode.productAlreadyPurchasedError ||
          _looksLikeAlreadyOwned(e);
      final cancelled = code == PurchasesErrorCode.purchaseCancelledError;

      debugPrint(
        '[subscription] purchase error code=$code alreadyOwned=$alreadyOwned '
        'cancelled=$cancelled: $e\n$st',
      );

      // Play "이미 가입" 시트를 닫으면 대개 purchaseCancelled 로 떨어짐 → 반드시 동기화.
      if (alreadyOwned || cancelled) {
        final ok = await _syncOwnedSubscription(
          forceEvenWithoutRc: alreadyOwned,
        );
        if (ok) return;
        if (cancelled) return;
      }

      // 그 외 오류도 한 번 동기화 시도 (스토어엔 있는데 RC만 늦은 경우)
      final recovered = await _syncOwnedSubscription(forceEvenWithoutRc: false);
      if (recovered) return;
      rethrow;
    }
  }

  /// 츄르 상품 스토어 가격 조회 (현지 통화 priceString)
  Future<void> fetchTipProducts() async {
    if (!_configured) {
      await WebViewHost.instance.dispatchTipProducts(products: const []);
      return;
    }

    final Map<String, Map<String, String>> byId = {};

    try {
      final offerings = await Purchases.getOfferings();
      for (final offering in offerings.all.values) {
        for (final package in offering.availablePackages) {
          final product = package.storeProduct;
          if (!SubscriptionConfig.isTipProduct(product.identifier)) continue;
          byId[product.identifier] = {
            'productId': product.identifier,
            'priceString': product.priceString,
            'currencyCode': product.currencyCode,
          };
        }
      }
    } catch (e, st) {
      debugPrint('[tip] offerings price lookup failed: $e\n$st');
    }

    final missing = SubscriptionConfig.tipProductIds
        .where((id) => !byId.containsKey(id))
        .toList();
    if (missing.isNotEmpty) {
      try {
        final products = await Purchases.getProducts(
          missing,
          productCategory: ProductCategory.nonSubscription,
        );
        for (final product in products) {
          byId[product.identifier] = {
            'productId': product.identifier,
            'priceString': product.priceString,
            'currencyCode': product.currencyCode,
          };
        }
      } catch (e, st) {
        debugPrint('[tip] getProducts price lookup failed: $e\n$st');
      }
    }

    // 앱이 기대하는 순서로 정렬
    final ordered = <Map<String, String>>[];
    for (final id in SubscriptionConfig.tipProductIds) {
      final row = byId[id];
      if (row != null) ordered.add(row);
    }
    for (final entry in byId.entries) {
      if (!SubscriptionConfig.tipProductIds.contains(entry.key)) {
        ordered.add(entry.value);
      }
    }

    debugPrint('[tip] products for web: $ordered');
    await WebViewHost.instance.dispatchTipProducts(products: ordered);
  }

  /// 츄르(후원) 소모성 상품 구매
  Future<void> purchaseTip(String productId) async {
    if (!_configured) {
      await WebViewHost.instance.dispatchTipPurchaseComplete(
        ok: false,
        productId: productId,
        error: 'not_configured',
      );
      return;
    }
    if (!SubscriptionConfig.isTipProduct(productId)) {
      await WebViewHost.instance.dispatchTipPurchaseComplete(
        ok: false,
        productId: productId,
        error: 'invalid_product',
      );
      return;
    }

    Package? tipPackage;
    StoreProduct? storeProduct;

    try {
      final offerings = await Purchases.getOfferings();
      for (final offering in offerings.all.values) {
        for (final package in offering.availablePackages) {
          final id = package.storeProduct.identifier;
          if (id == productId || id.startsWith('$productId:')) {
            tipPackage = package;
            storeProduct = package.storeProduct;
            break;
          }
        }
        if (tipPackage != null) break;
      }
    } catch (e, st) {
      debugPrint('[tip] offerings lookup failed: $e\n$st');
    }

    if (storeProduct == null) {
      for (final category in [
        ProductCategory.nonSubscription,
        ProductCategory.subscription,
      ]) {
        try {
          final products = await Purchases.getProducts(
            [productId],
            productCategory: category,
          );
          if (products.isNotEmpty) {
            storeProduct = products.first;
            debugPrint(
              '[tip] getProducts hit category=$category id=${storeProduct.identifier}',
            );
            break;
          }
        } catch (e, st) {
          debugPrint('[tip] getProducts($category) failed: $e\n$st');
        }
      }
    }

    if (tipPackage == null && storeProduct == null) {
      debugPrint('[tip] product not found: $productId');
      await WebViewHost.instance.dispatchTipPurchaseComplete(
        ok: false,
        productId: productId,
        error: 'no_product',
      );
      return;
    }

    try {
      if (tipPackage != null) {
        debugPrint(
          '[tip] purchase via package ${tipPackage.identifier} '
          '→ ${tipPackage.storeProduct.identifier}',
        );
        await Purchases.purchase(PurchaseParams.package(tipPackage));
      } else {
        debugPrint('[tip] purchase via storeProduct ${storeProduct!.identifier}');
        await Purchases.purchase(PurchaseParams.storeProduct(storeProduct));
      }
      debugPrint('[tip] purchase ok product=$productId');
      await WebViewHost.instance.dispatchTipPurchaseComplete(
        ok: true,
        productId: productId,
      );
    } catch (e, st) {
      final code = _safeErrorCode(e);
      final cancelled = code == PurchasesErrorCode.purchaseCancelledError;
      debugPrint(
        '[tip] purchase error code=$code cancelled=$cancelled: $e\n$st',
      );
      await WebViewHost.instance.dispatchTipPurchaseComplete(
        ok: false,
        cancelled: cancelled,
        productId: productId,
        error: cancelled ? 'cancelled' : (code?.name ?? 'purchase_failed'),
      );
    }
  }

  Future<void> restore() async {
    if (!_configured) {
      throw PlatformException(
        code: 'not_configured',
        message: 'RevenueCat is not configured',
      );
    }
    await Purchases.syncPurchases();
    final info = await Purchases.restorePurchases();
    await _applyPurchasedInfo(info);
    if (!_isPremium(info)) {
      // 복원 결과가 비어도 스토어 구독이 있으면 아래에서 잡힘
      await _refreshAndPushIfPremium(reason: 'restore-fallback');
    }
  }

  Future<void> _applyPurchasedInfo(CustomerInfo info) async {
    await _pushPurchaseComplete(info);
    await _pushStatus(info);
    try {
      await Purchases.invalidateCustomerInfoCache();
      final refreshed = await Purchases.getCustomerInfo();
      await _pushStatus(refreshed);
    } catch (_) {}
  }

  /// Play/RevenueCat 구독을 다시 읽고 Pro면 웹에 반영.
  /// [forceEvenWithoutRc]: Play가 이미 가입됨을 확정한 경우 RC entitlement가 비어도 Pro 부여.
  Future<bool> _syncOwnedSubscription({required bool forceEvenWithoutRc}) async {
    try {
      await Purchases.syncPurchases();
    } catch (e, st) {
      debugPrint('[subscription] syncPurchases failed: $e\n$st');
    }

    CustomerInfo? info;
    try {
      info = await Purchases.restorePurchases();
      await _applyPurchasedInfo(info);
      if (_isPremium(info)) return true;
    } catch (e, st) {
      debugPrint('[subscription] restore after purchase-exit failed: $e\n$st');
    }

    try {
      await Purchases.invalidateCustomerInfoCache();
      info = await Purchases.getCustomerInfo();
      await _applyPurchasedInfo(info);
      if (_isPremium(info)) return true;
    } catch (e, st) {
      debugPrint('[subscription] getCustomerInfo after purchase-exit failed: $e\n$st');
    }

    // 취소 후에도 만료 전 pageby 기록이 있으면 Pro
    if (info != null && _hasUnexpiredPageby(info)) {
      await _forceProToWeb(info: info);
      return true;
    }

    if (forceEvenWithoutRc) {
      debugPrint('[subscription] Play already-owned → force Pro to web');
      await _forceProToWeb(info: info);
      return true;
    }
    return false;
  }

  bool _hasUnexpiredPageby(CustomerInfo info) {
    if (_isPremium(info)) return true;
    final now = DateTime.now();
    for (final entry in info.allExpirationDates.entries) {
      final id = entry.key;
      if (SubscriptionConfig.isTipProduct(id)) continue;
      if (!(id.contains('pageby') ||
          id == SubscriptionConfig.productId ||
          id.contains('premium'))) {
        continue;
      }
      final raw = entry.value;
      if (raw == null || raw.isEmpty) {
        // 만료일 없으면 활성으로 간주
        return true;
      }
      final exp = DateTime.tryParse(raw);
      if (exp != null && exp.isAfter(now)) return true;
    }
    return false;
  }

  Future<bool> _refreshAndPushIfPremium({required String reason}) async {
    try {
      await Purchases.syncPurchases();
    } catch (_) {}
    try {
      await Purchases.invalidateCustomerInfoCache();
      final info = await Purchases.getCustomerInfo();
      if (_isPremium(info)) {
        debugPrint('[subscription] premium found ($reason) — push to web');
        await _applyPurchasedInfo(info);
        return true;
      }
    } catch (e, st) {
      debugPrint('[subscription] refresh ($reason) failed: $e\n$st');
    }
    return false;
  }

  /// RevenueCat entitlement가 비어도 Play가 소유를 확인한 경우 웹 Pro 활성
  Future<void> _forceProToWeb({CustomerInfo? info}) async {
    final entitlement = info == null ? null : _pickEntitlement(info);
    int? expiresAtMs;
    final expiration = entitlement?.expirationDate;
    if (expiration != null) {
      expiresAtMs = DateTime.tryParse(expiration)?.millisecondsSinceEpoch;
    }
    expiresAtMs ??= DateTime.now()
        .add(const Duration(days: 30))
        .millisecondsSinceEpoch;
    final productId = entitlement?.productIdentifier ??
        (info != null && info.activeSubscriptions.isNotEmpty
            ? info.activeSubscriptions.first
            : SubscriptionConfig.productId);

    activeNotifier.value = true;
    debugPrint(
      '[subscription] force Pro active product=$productId expires=$expiresAtMs',
    );
    await WebViewHost.instance.dispatchSubscriptionPurchaseComplete(
      active: true,
      expiresAtMs: expiresAtMs,
      productId: productId,
    );
    await WebViewHost.instance.dispatchSubscriptionStatus(
      active: true,
      expiresAtMs: expiresAtMs,
      productId: productId,
    );
  }

  PurchasesErrorCode? _safeErrorCode(Object e) {
    if (e is! PlatformException) return null;
    try {
      return PurchasesErrorHelper.getErrorCode(e);
    } catch (_) {
      return null;
    }
  }

  bool _looksLikeAlreadyOwned(Object e) {
    final text = e.toString().toLowerCase();
    if (text.contains('productalreadypurchased') ||
        text.contains('already_purchased') ||
        text.contains('item_already_owned') ||
        text.contains('item already owned') ||
        text.contains('already owned') ||
        text.contains('already subscribed')) {
      return true;
    }
    if (e is PlatformException) {
      final message = (e.message ?? '').toLowerCase();
      final details = '${e.details ?? ''}'.toLowerCase();
      final code = e.code.toLowerCase();
      if (message.contains('already') ||
          details.contains('already') ||
          details.contains('item_already_owned') ||
          code.contains('already')) {
        return true;
      }
      // Google Play BillingResponseCode.ITEM_ALREADY_OWNED == 7
      if (code == '7' || details.contains('responsecode: 7')) {
        return true;
      }
    }
    final raw = e.toString();
    return raw.contains('이미') &&
        (raw.contains('가입') || raw.contains('구독') || raw.contains('구매'));
  }

  /// entitlement `premium` 뿐 아니라 활성 구독/만료 전 구매도 Pro로 인정
  bool _isPremium(CustomerInfo info) {
    final named = info.entitlements.all[SubscriptionConfig.entitlementId];
    if (named?.isActive == true) return true;
    if (info.entitlements.active.isNotEmpty) {
      for (final ent in info.entitlements.active.values) {
        if (!SubscriptionConfig.isTipProduct(ent.productIdentifier)) {
          return true;
        }
      }
    }
    if (info.activeSubscriptions.contains(SubscriptionConfig.productId)) {
      return true;
    }
    for (final id in info.activeSubscriptions) {
      if (SubscriptionConfig.isTipProduct(id)) continue;
      if (id.contains('pageby') || id.contains('premium')) return true;
    }
    // entitlement 미연결이어도 스토어 구독 만료 전이면 Pro
    final now = DateTime.now();
    for (final entry in info.allExpirationDates.entries) {
      final id = entry.key;
      if (SubscriptionConfig.isTipProduct(id)) continue;
      if (!(id.contains('pageby') ||
          id.contains('premium') ||
          id == SubscriptionConfig.productId)) {
        continue;
      }
      final raw = entry.value;
      if (raw == null || raw.isEmpty) continue;
      final exp = DateTime.tryParse(raw);
      if (exp != null && exp.isAfter(now)) return true;
    }
    return false;
  }

  EntitlementInfo? _pickEntitlement(CustomerInfo info) {
    final named = info.entitlements.all[SubscriptionConfig.entitlementId];
    if (named?.isActive == true) return named;
    if (info.entitlements.active.isNotEmpty) {
      return info.entitlements.active.values.first;
    }
    return named;
  }

  Future<void> _pushStatus(CustomerInfo info) async {
    final snapshot = _snapshotFromInfo(info);
    activeNotifier.value = snapshot.active;
    debugPrint(
      '[subscription] push active=${snapshot.active} '
      'product=${snapshot.productId} '
      'subs=${info.activeSubscriptions} '
      'entitlements=${info.entitlements.active.keys.toList()}',
    );
    await _dispatch(
      active: snapshot.active,
      expiresAtMs: snapshot.expiresAtMs,
      productId: snapshot.productId,
    );
  }

  Future<void> _pushPurchaseComplete(CustomerInfo info) async {
    final snapshot = _snapshotFromInfo(info);
    activeNotifier.value = snapshot.active;
    debugPrint(
      '[subscription] purchase complete active=${snapshot.active} '
      'product=${snapshot.productId}',
    );
    await WebViewHost.instance.dispatchSubscriptionPurchaseComplete(
      active: snapshot.active,
      expiresAtMs: snapshot.expiresAtMs,
      productId: snapshot.productId,
    );
  }

  _SubscriptionSnapshot _snapshotFromInfo(CustomerInfo info) {
    final active = _isPremium(info);
    final entitlement = _pickEntitlement(info);
    int? expiresAtMs;
    final expiration = entitlement?.expirationDate;
    if (expiration != null) {
      expiresAtMs = DateTime.tryParse(expiration)?.millisecondsSinceEpoch;
    }
    return _SubscriptionSnapshot(
      active: active,
      expiresAtMs: expiresAtMs,
      productId: entitlement?.productIdentifier ??
          (info.activeSubscriptions.isNotEmpty
              ? info.activeSubscriptions.first
              : null),
    );
  }

  Future<void> _dispatch({
    required bool active,
    required int? expiresAtMs,
    String? productId,
  }) async {
    activeNotifier.value = active;
    await WebViewHost.instance.dispatchSubscriptionStatus(
      active: active,
      expiresAtMs: expiresAtMs,
      productId: productId,
    );
  }
}

class _SubscriptionSnapshot {
  const _SubscriptionSnapshot({
    required this.active,
    required this.expiresAtMs,
    this.productId,
  });

  final bool active;
  final int? expiresAtMs;
  final String? productId;
}
