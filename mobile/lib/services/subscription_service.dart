import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'providers.dart';

class SubscriptionStatus {
  final String tier;
  final bool isTrial;
  final bool trialExpired;
  final DateTime? trialEndDate;
  final DateTime? subscriptionExpiresAt;

  const SubscriptionStatus({
    required this.tier,
    required this.isTrial,
    this.trialExpired = false,
    this.trialEndDate,
    this.subscriptionExpiresAt,
  });

  bool get isPro => tier == 'pro';

  /// Trial expired and no subscription — hard paywall.
  bool get isHardPaywall => trialExpired && !isPro;

  int get trialDaysRemaining {
    if (!isTrial || trialEndDate == null) return 0;
    final remaining = trialEndDate!.difference(DateTime.now()).inDays;
    return remaining.clamp(0, 999);
  }

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) {
    return SubscriptionStatus(
      tier: json['tier'] as String,
      isTrial: json['is_trial'] as bool,
      trialExpired: json['trial_expired'] as bool? ?? false,
      trialEndDate: json['trial_end_date'] != null
          ? DateTime.parse(json['trial_end_date'] as String)
          : null,
      subscriptionExpiresAt: json['subscription_expires_at'] != null
          ? DateTime.parse(json['subscription_expires_at'] as String)
          : null,
    );
  }

  static const free = SubscriptionStatus(tier: 'free', isTrial: false);

  /// Pro state set locally after a confirmed purchase, before the backend
  /// webhook has had time to fire.
  static const confirmedPro = SubscriptionStatus(
    tier: 'pro',
    isTrial: false,
    trialExpired: false,
  );
}

final subscriptionProvider =
    StateNotifierProvider<SubscriptionNotifier, SubscriptionStatus>(
  (ref) => SubscriptionNotifier(ref),
);

class SubscriptionNotifier extends StateNotifier<SubscriptionStatus> {
  SubscriptionNotifier(this._ref) : super(SubscriptionStatus.free) {
    refresh();
  }

  final Ref _ref;

  /// Fetch subscription status from the backend. Also checks RevenueCat's
  /// local customer info as a fallback — this handles the case where the
  /// webhook updated the backend but also catches purchases that the
  /// backend hasn't processed yet.
  Future<void> refresh() async {
    try {
      final api = _ref.read(apiServiceProvider);
      final response = await api.get('/subscription/status');
      if (!mounted) return;
      final backendStatus = SubscriptionStatus.fromJson(response.data);

      // If backend says Pro, trust it and clear the local flag.
      if (backendStatus.isPro) {
        _confirmedPro = false;
        state = backendStatus;
        return;
      }

      // Backend says not Pro — if we have a local purchase confirmation,
      // keep showing Pro (the webhook just hasn't arrived yet).
      if (_confirmedPro) {
        state = SubscriptionStatus.confirmedPro;
        return;
      }

      // Also check RevenueCat locally in case the user has an active
      // purchase the backend doesn't know about yet.
      if (await Purchases.isConfigured) {
        try {
          final info = await Purchases.getCustomerInfo();
          if (info.entitlements.active.isNotEmpty) {
            if (!mounted) return;
            _confirmedPro = true;
            state = SubscriptionStatus.confirmedPro;
            return;
          }
        } catch (_) {}
      }

      if (!mounted) return;
      state = backendStatus;
    } on DioException {
      if (!mounted) return;
      // Don't downgrade if we have a confirmed purchase
      if (_confirmedPro) return;
      state = SubscriptionStatus.free;
    }
  }

  /// Set Pro state immediately after a confirmed purchase (client-side).
  /// This avoids the race condition where the backend webhook hasn't fired
  /// yet but RevenueCat has already confirmed the purchase locally.
  void confirmPurchase() {
    _confirmedPro = true;
    state = SubscriptionStatus.confirmedPro;
  }

  /// Whether the user has a locally confirmed purchase that should not be
  /// overridden by a stale backend response.
  bool _confirmedPro = false;

  /// Identify the current user to RevenueCat.
  Future<void> identifyUser() async {
    if (!await Purchases.isConfigured) return;
    try {
      final api = _ref.read(apiServiceProvider);
      final resp = await api.get('/auth/me');
      final userId = resp.data['id'] as String;
      await Purchases.logIn(userId);
    } catch (_) {}
  }
}
