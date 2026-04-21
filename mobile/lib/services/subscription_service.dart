import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'providers.dart';

class SubscriptionStatus {
  final String tier;
  final bool isTrial;
  final bool aiTrialExpired;
  final bool trialExpired;
  final DateTime? trialEndDate;
  final DateTime? subscriptionExpiresAt;

  const SubscriptionStatus({
    required this.tier,
    required this.isTrial,
    this.aiTrialExpired = false,
    this.trialExpired = false,
    this.trialEndDate,
    this.subscriptionExpiresAt,
  });

  bool get isPro => tier == 'pro';

  /// User can access AI features (Pro subscriber OR within first 3 days of trial).
  bool get hasAiAccess => isPro || !aiTrialExpired;

  /// Full trial (7 days) expired and no subscription — hard paywall.
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
      aiTrialExpired: json['ai_trial_expired'] as bool? ?? false,
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
}

/// Provider for the current subscription status.
/// Fetches from the backend and caches the result.
final subscriptionProvider =
    StateNotifierProvider<SubscriptionNotifier, SubscriptionStatus>(
  (ref) => SubscriptionNotifier(ref),
);

class SubscriptionNotifier extends StateNotifier<SubscriptionStatus> {
  SubscriptionNotifier(this._ref) : super(SubscriptionStatus.free) {
    refresh();
  }

  final Ref _ref;

  Future<void> refresh() async {
    try {
      final api = _ref.read(apiServiceProvider);
      final response = await api.get('/subscription/status');
      state = SubscriptionStatus.fromJson(response.data);
    } on DioException {
      // If not logged in or network error, default to free
      state = SubscriptionStatus.free;
    }
  }

  /// Identify the current user to RevenueCat so purchases are linked
  /// to the correct backend user_id. Call after registration or sign-in.
  Future<void> identifyUser() async {
    try {
      final api = _ref.read(apiServiceProvider);
      final resp = await api.get('/auth/me');
      final userId = resp.data['id'] as String;
      await Purchases.logIn(userId);
    } catch (_) {
      // Non-critical — purchases still work with anonymous RC user
    }
  }
}
