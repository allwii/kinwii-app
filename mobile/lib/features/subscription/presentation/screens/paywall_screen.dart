// PaywallScreen — Clear free-vs-pro comparison with no dark patterns.
// Shows monthly/annual toggle and upgrade button.
// Integrated with RevenueCat for IAP.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../services/subscription_service.dart';

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  bool _isAnnual = true;
  bool _purchasing = false;
  Offering? _offering;

  // Fallback prices if RevenueCat isn't configured or fails
  static const _fallbackMonthly = '\$6.99';
  static const _fallbackAnnual = '\$49.99';
  static const _fallbackAnnualMonthly = '\$4.17';

  @override
  void initState() {
    super.initState();
    _loadOfferings();
  }

  Future<void> _loadOfferings() async {
    if (!await Purchases.isConfigured) return;
    try {
      final offerings = await Purchases.getOfferings();
      if (mounted && offerings.current != null) {
        setState(() => _offering = offerings.current);
      }
    } catch (_) {
      // RevenueCat not configured — use fallback prices
    }
  }

  String get _monthlyPrice {
    return _offering?.monthly?.storeProduct.priceString ?? _fallbackMonthly;
  }

  String get _annualPrice {
    return _offering?.annual?.storeProduct.priceString ?? _fallbackAnnual;
  }

  String get _annualMonthlyPrice {
    final annual = _offering?.annual?.storeProduct;
    if (annual != null) {
      final monthly = annual.price / 12;
      return '\$${monthly.toStringAsFixed(2)}';
    }
    return _fallbackAnnualMonthly;
  }

  Future<void> _purchase() async {
    final package = _isAnnual ? _offering?.annual : _offering?.monthly;
    if (package == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Store not available. Please try again later.')),
        );
      }
      return;
    }

    setState(() => _purchasing = true);
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      // Check if any entitlement is active (covers 'pro', 'Kinwii Pro', etc.)
      final hasActiveEntitlement = result.customerInfo.entitlements.active.isNotEmpty;
      if (hasActiveEntitlement) {
        ref.read(subscriptionProvider.notifier).confirmPurchase();
        if (mounted) context.pop();
      }
    } on PlatformException catch (e) {
      if (mounted) {
        final errorCode = PurchasesErrorHelper.getErrorCode(e);
        if (errorCode != PurchasesErrorCode.purchaseCancelledError) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Purchase failed. Please try again.')),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  Future<void> _restore() async {
    if (!await Purchases.isConfigured) return;
    setState(() => _purchasing = true);
    try {
      final customerInfo = await Purchases.restorePurchases();
      if (mounted) {
        if (customerInfo.entitlements.active.isNotEmpty) {
          ref.read(subscriptionProvider.notifier).confirmPurchase();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Purchases restored!')),
          );
          context.pop();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No active subscription found.')),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not restore purchases.')),
        );
      }
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  Future<void> _manageSubscription() async {
    try {
      if (await Purchases.isConfigured) {
        final info = await Purchases.getCustomerInfo();
        final managementUrl = info.managementURL;
        if (managementUrl != null) {
          await launchUrl(
            Uri.parse(managementUrl),
            mode: LaunchMode.externalApplication,
          );
          return;
        }
      }
    } catch (_) {}
    await launchUrl(
      Uri.parse('https://apps.apple.com/account/subscriptions'),
      mode: LaunchMode.externalApplication,
    );
  }

  Widget _buildProManagement(BuildContext context, SubscriptionStatus sub) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.content),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pro badge
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.kiwi400,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.workspace_premium,
                    color: Colors.white, size: 32),
              ),
              const SizedBox(height: 20),
              Text(
                'Kinwii Pro',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppColors.content,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'You have full access to all features.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.contentSecondary,
                    ),
              ),
              const SizedBox(height: 32),

              // Features included
              _ProFeature(icon: Icons.today, label: 'Smart daily focus'),
              _ProFeature(icon: Icons.flag, label: 'Unlimited goals'),
              _ProFeature(icon: Icons.auto_awesome, label: 'AI coaching & insights'),
              _ProFeature(icon: Icons.insights, label: 'Progress analytics'),

              if (sub.subscriptionExpiresAt != null) ...[
                const SizedBox(height: 32),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Subscription',
                        style:
                            Theme.of(context).textTheme.titleSmall?.copyWith(
                                  color: AppColors.content,
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Renews ${_formatDate(sub.subscriptionExpiresAt!)}',
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppColors.contentSecondary,
                                ),
                      ),
                    ],
                  ),
                ),
              ],

              const Spacer(),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _manageSubscription,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.content,
                    side: const BorderSide(color: AppColors.borderSubtle),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Manage subscription'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final sub = ref.watch(subscriptionProvider);
    final isHardPaywall = sub.isHardPaywall;

    // If user is already Pro (not on trial), show management view
    if (sub.isPro && !sub.isTrial) {
      return _buildProManagement(context, sub);
    }

    return PopScope(
      canPop: !isHardPaywall,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: !isHardPaywall,
          leading: isHardPaywall
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, color: AppColors.content),
                  onPressed: () => context.pop(),
                ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Unlock Kinwii Pro',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: AppColors.content,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'You have full access to all features.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.contentSecondary,
                      ),
                ),
                const SizedBox(height: 28),

                // Features with icons (matches Pro management view)
                _ProFeature(icon: Icons.today, label: 'Smart daily focus'),
                _ProFeature(icon: Icons.flag, label: 'Unlimited goals'),
                _ProFeature(icon: Icons.auto_awesome, label: 'AI coaching & insights'),
                _ProFeature(icon: Icons.insights, label: 'Progress analytics'),
                const SizedBox(height: 24),

                // Plan toggle
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      _PlanTab(
                        label: 'Annual',
                        sublabel: '$_annualMonthlyPrice/mo',
                        isSelected: _isAnnual,
                        badge: 'Save 40%',
                        onTap: () => setState(() => _isAnnual = true),
                      ),
                      _PlanTab(
                        label: 'Monthly',
                        sublabel: '$_monthlyPrice/mo',
                        isSelected: !_isAnnual,
                        onTap: () => setState(() => _isAnnual = false),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Price display
                Center(
                  child: Column(
                    children: [
                      Text(
                        _isAnnual ? _annualPrice : _monthlyPrice,
                        style:
                            Theme.of(context).textTheme.headlineLarge?.copyWith(
                                  color: AppColors.content,
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                      Text(
                        _isAnnual ? 'per year' : 'per month',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.contentSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Subscribe button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _purchasing ? null : _purchase,
                    child: _purchasing
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            sub.isTrial
                                ? 'Subscribe now'
                                : 'Start 5-day free trial',
                          ),
                  ),
                ),
                const SizedBox(height: 12),

                // Fine print
                Center(
                  child: Text(
                    _isAnnual
                        ? 'Billed annually. Cancel anytime.'
                        : 'Billed monthly. Cancel anytime.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.contentTertiary,
                        ),
                  ),
                ),

                if (sub.isTrial) ...[
                  const SizedBox(height: 16),
                  Center(
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.kiwi50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${sub.trialDaysRemaining} days left on your trial',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.kiwi700,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ),
                  ),
                ],

                // Restore purchases
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: _purchasing ? null : _restore,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.contentSecondary,
                    ),
                    child: const Text('Restore purchases'),
                  ),
                ),

                if (!isHardPaywall) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: () => context.pop(),
                      child: const Text('Continue with Free plan'),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      'Your trial has ended. Subscribe to keep using Kinwii.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.contentSecondary,
                          ),
                    ),
                  ),
                ],

                // Legal links (required by App Store)
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => launchUrl(
                        Uri.parse('https://kinwii.com/terms'),
                        mode: LaunchMode.externalApplication,
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.contentTertiary,
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      child: const Text('Terms of Use'),
                    ),
                    Text('  ·  ',
                        style: TextStyle(color: AppColors.contentTertiary, fontSize: 12)),
                    TextButton(
                      onPressed: () => launchUrl(
                        Uri.parse('https://kinwii.com/privacy'),
                        mode: LaunchMode.externalApplication,
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.contentTertiary,
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      child: const Text('Privacy Policy'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Plan toggle tab
// ---------------------------------------------------------------------------

class _PlanTab extends StatelessWidget {
  const _PlanTab({
    required this.label,
    required this.sublabel,
    required this.isSelected,
    required this.onTap,
    this.badge,
  });

  final String label;
  final String sublabel;
  final bool isSelected;
  final String? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: isSelected
                              ? AppColors.content
                              : AppColors.contentSecondary,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w400,
                        ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.kiwi400,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        badge!,
                        style:
                            Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 10,
                                ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                sublabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.contentTertiary,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pro feature row (for management view)
// ---------------------------------------------------------------------------

class _ProFeature extends StatelessWidget {
  const _ProFeature({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.kiwi50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: AppColors.kiwi600),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.content,
                ),
          ),
          const Spacer(),
          const Icon(Icons.check_circle, size: 20, color: AppColors.kiwi400),
        ],
      ),
    );
  }
}
