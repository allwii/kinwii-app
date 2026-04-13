// SettingsScreen — Production-quality settings with Pro banner, profile,
// grouped sections with icons.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../features/auth/presentation/screens/login_screen.dart';
import '../../../../services/subscription_service.dart';
import '../widgets/edit_name_modal.dart';
import '../widgets/feedback_modal.dart';
import '../widgets/password_reset_modal.dart';

// Re-export for other files that import from here
export '../providers/reminder_settings_provider.dart';

// ---------------------------------------------------------------------------
// First day of week preference
// ---------------------------------------------------------------------------

final firstDayOfWeekProvider =
    StateNotifierProvider<_FirstDayNotifier, String>(
  (ref) => _FirstDayNotifier(),
);

class _FirstDayNotifier extends StateNotifier<String> {
  _FirstDayNotifier() : super('Monday') {
    _load();
  }

  Future<void> _load() async {
    final box = await Hive.openBox('kinwii_settings');
    state = box.get('first_day_of_week', defaultValue: 'Monday');
  }

  Future<void> set(String day) async {
    state = day;
    final box = await Hive.openBox('kinwii_settings');
    await box.put('first_day_of_week', day);
  }
}

// ---------------------------------------------------------------------------
// User profile provider
// ---------------------------------------------------------------------------

class _UserProfile {
  final String? email;
  final String? name;
  final String subscriptionTier;

  const _UserProfile({
    this.email,
    this.name,
    this.subscriptionTier = 'free',
  });
}

final _userProfileProvider =
    StateNotifierProvider<_UserProfileNotifier, AsyncValue<_UserProfile>>(
  (ref) => _UserProfileNotifier(ref),
);

class _UserProfileNotifier extends StateNotifier<AsyncValue<_UserProfile>> {
  _UserProfileNotifier(this._ref) : super(const AsyncValue.loading()) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    try {
      final api = _ref.read(apiServiceProvider);
      final resp = await api.get('/auth/me');
      final data = resp.data as Map<String, dynamic>;
      state = AsyncValue.data(_UserProfile(
        email: data['email'] as String?,
        name: data['name'] as String?,
        subscriptionTier: data['subscription_tier'] as String? ?? 'free',
      ));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void refresh() => _load();
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(_userProfileProvider);
    final sub = ref.watch(subscriptionProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
          children: [
            Text(
              'Settings',
              style: Theme.of(context)
                  .textTheme
                  .headlineLarge
                  ?.copyWith(color: AppColors.content),
            ),
            const SizedBox(height: 24),

            // --- Profile card ---
            _SettingsCard(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.kiwi100,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: const Icon(Icons.person,
                            color: AppColors.kiwi600, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: profileAsync.when(
                          data: (profile) => Text(
                            profile.name ?? 'Kinwii member',
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(
                                  color: AppColors.content,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          loading: () => Text(
                            'Loading...',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: AppColors.contentTertiary),
                          ),
                          error: (_, __) => Text(
                            'Kinwii member',
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(color: AppColors.content),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // --- Get Kinwii Pro banner ---
            if (!sub.isPro) ...[
              _ProBanner(onTap: () => context.push('/pro')),
              const SizedBox(height: 20),
            ],

            // --- General ---
            const _SectionLabel(label: 'GENERAL'),
            const SizedBox(height: 10),
            _SettingsCard(
              children: [
                _FirstDayRow(),
                _SettingsRow(
                  icon: Icons.notifications_outlined,
                  label: 'Notifications',
                  onTap: () => context.push('/notifications'),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // --- Account ---
            const _SectionLabel(label: 'ACCOUNT'),
            const SizedBox(height: 10),
            _SettingsCard(
              children: [
                _SettingsRow(
                  icon: Icons.person_outline,
                  label: 'Edit name',
                  onTap: () {
                    final name =
                        profileAsync.valueOrNull?.name;
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(24)),
                      ),
                      builder: (_) => EditNameModal(
                        api: ref.read(apiServiceProvider),
                        currentName: name,
                        onSaved: () =>
                            ref.read(_userProfileProvider.notifier).refresh(),
                      ),
                    );
                  },
                ),
                _SettingsRow(
                  icon: Icons.lock_outline,
                  label: 'Change password',
                  onTap: () {
                    final email = profileAsync.valueOrNull?.email;
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(24)),
                      ),
                      builder: (_) => PasswordResetModal(
                        api: ref.read(apiServiceProvider),
                        initialEmail: email,
                      ),
                    );
                  },
                ),
                _SettingsRow(
                  icon: Icons.delete_outline,
                  label: 'Delete account',
                  showChevron: false,
                  onTap: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Delete account?'),
                        content: const Text(
                            'This will permanently delete your account and all data. This cannot be undone.'),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.of(context).pop(false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () =>
                                Navigator.of(context).pop(true),
                            child: const Text('Delete',
                                style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true && context.mounted) {
                      try {
                        await ref.read(apiServiceProvider).delete('/auth/me');
                        await ref.read(authServiceProvider).logout();
                        if (context.mounted) context.go('/auth/login');
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Could not delete account. Try again.')),
                          );
                        }
                      }
                    }
                  },
                ),
                _SettingsRow(
                  icon: Icons.logout,
                  label: 'Sign out',
                  showChevron: false,
                  onTap: () async {
                    await ref.read(authServiceProvider).logout();
                    if (context.mounted) context.go('/auth/login');
                  },
                ),
              ],
            ),

            const SizedBox(height: 24),

            // --- Support ---
            const _SectionLabel(label: 'SUPPORT'),
            const SizedBox(height: 10),
            _SettingsCard(
              children: [
                _SettingsRow(
                  icon: Icons.help_outline,
                  label: 'Help & Feedback',
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(24)),
                      ),
                      builder: (_) => FeedbackModal(
                        api: ref.read(apiServiceProvider),
                      ),
                    );
                  },
                ),
                _SettingsRow(
                  icon: Icons.shield_outlined,
                  label: 'Privacy & Permissions',
                  onTap: () => context.push('/privacy'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pro banner
// ---------------------------------------------------------------------------

class _ProBanner extends StatelessWidget {
  const _ProBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.kiwi400, AppColors.kiwi600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.kiwi400.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.workspace_premium,
                        color: Colors.white, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      'Get Kinwii Pro',
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                    ),
                    const Spacer(),
                    Icon(Icons.arrow_forward_ios,
                        color: Colors.white.withValues(alpha: 0.7),
                        size: 16),
                  ],
                ),
                const SizedBox(height: 14),
                const _BenefitRow(text: 'Plan and focus better'),
                const SizedBox(height: 6),
                const _BenefitRow(text: 'Access to all features'),
                const SizedBox(height: 6),
                const _BenefitRow(text: 'Plan smarter with AI'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.check_circle,
            color: Colors.white.withValues(alpha: 0.8), size: 16),
        const SizedBox(width: 8),
        Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.9),
              ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section label
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: AppColors.contentSecondary,
            letterSpacing: 1.2,
          ),
    );
  }
}

// ---------------------------------------------------------------------------
// Settings card container
// ---------------------------------------------------------------------------

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Settings row (icon + label + chevron)
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// First day of week row
// ---------------------------------------------------------------------------

class _FirstDayRow extends ConsumerWidget {
  const _FirstDayRow();

  static const _days = ['Monday', 'Sunday', 'Saturday'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(firstDayOfWeekProvider);

    return InkWell(
      onTap: () {
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (_) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('First Day of the Week',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                ..._days.map((day) => ListTile(
                      title: Text(day),
                      trailing: day == selected
                          ? const Icon(Icons.check,
                              color: AppColors.kiwi500)
                          : null,
                      onTap: () {
                        ref.read(firstDayOfWeekProvider.notifier).set(day);
                        Navigator.of(context).pop();
                      },
                    )),
              ],
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_outlined,
                size: 20, color: AppColors.contentSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'First Day of the Week',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.content,
                    ),
              ),
            ),
            Text(
              selected,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.kiwi500,
                  ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.unfold_more,
                size: 16, color: AppColors.contentTertiary),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Settings row (icon + label + chevron)
// ---------------------------------------------------------------------------

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    this.onTap,
    this.trailing,
    this.iconColor,
    this.labelColor,
    this.showChevron = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? iconColor;
  final Color? labelColor;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon,
                size: 20, color: iconColor ?? AppColors.contentSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: labelColor ?? AppColors.content,
                    ),
              ),
            ),
            if (trailing != null)
              trailing!
            else if (showChevron && onTap != null)
              const Icon(Icons.chevron_right,
                  size: 20, color: AppColors.contentTertiary),
          ],
        ),
      ),
    );
  }
}
