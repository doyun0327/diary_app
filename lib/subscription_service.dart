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
    if (!_configured) {
      await _dispatch(active: false, expiresAtMs: null);
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
    await _pushStatus(result.customerInfo);
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

  Future<void> _pushStatus(CustomerInfo info) async {
    final entitlement =
        info.entitlements.all[SubscriptionConfig.entitlementId];
    final active = entitlement?.isActive == true;
    activeNotifier.value = active;
    int? expiresAtMs;
    final expiration = entitlement?.expirationDate;
    if (expiration != null) {
      expiresAtMs = DateTime.tryParse(expiration)?.millisecondsSinceEpoch;
    }
    await _dispatch(
      active: active,
      expiresAtMs: expiresAtMs,
      productId: entitlement?.productIdentifier,
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
