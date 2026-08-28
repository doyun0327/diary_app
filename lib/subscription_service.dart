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

    final result = await Purchases.purchase(PurchaseParams.package(package));
    await _pushPurchaseComplete(result.customerInfo);
    await _pushStatus(result.customerInfo);
    // 결제 직후 entitlement 반영 지연 대비 한 번 더
    try {
      final info = await Purchases.getCustomerInfo();
      await _pushStatus(info);
    } catch (_) {}
  }

  Future<void> restore() async {
    if (!_configured) {
      throw PlatformException(
        code: 'not_configured',
        message: 'RevenueCat is not configured',
      );
    }
    final info = await Purchases.restorePurchases();
    await _pushStatus(info);
  }

  /// entitlement `premium` 뿐 아니라 활성 구독/다른 entitlement도 Pro로 인정
  bool _isPremium(CustomerInfo info) {
    final named = info.entitlements.all[SubscriptionConfig.entitlementId];
    if (named?.isActive == true) return true;
    if (info.entitlements.active.isNotEmpty) return true;
    if (info.activeSubscriptions.contains(SubscriptionConfig.productId)) {
      return true;
    }
    for (final id in info.activeSubscriptions) {
      if (id.contains('pageby') || id.contains('premium')) return true;
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
