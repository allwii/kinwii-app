// SettingsScreen — Production-quality settings with Pro banner, profile,
// grouped sections with icons.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../features/auth/presentation/screens/login_screen.dart';
import '../../../../services/subscription_service.dart';
import '../widgets/feedback_modal.dart';

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
// Stats provider — lightweight summary for profile badges
// ---------------------------------------------------------------------------

class _UserStats {
  final int totalCompleted;
  final int currentStreak; // consecutive rhythm weeks
  final int goalCount;

  const _UserStats({
    this.totalCompleted = 0,
    this.currentStreak = 0,
    this.goalCount = 0,
  });
}

final _userStatsProvider = FutureProvider.autoDispose<_UserStats>((ref) async {
  final api = ref.read(apiServiceProvider);
  try {
    final resp =
        await api.get('/analytics/progress', queryParameters: {'weeks': 12});
    final data = resp.data as Map<String, dynamic>;

    // Total completed tasks across all weeks
    final weeks = (data['weekly_completions'] as List<dynamic>?) ?? [];
    int totalCompleted = 0;
    for (final w in weeks) {
      totalCompleted += (w['completed_tasks'] as int? ?? 0);
    }

    // Current streak of consecutive rhythm weeks (from most recent back)
    final rhythmWeeks = (data['rhythm_weeks'] as List<dynamic>?) ?? [];
    int streak = 0;
    for (int i = rhythmWeeks.length - 1; i >= 0; i--) {
      if (rhythmWeeks[i]['is_rhythm_week'] == true) {
        streak++;
      } else {
        break;
      }
    }

    final goals = (data['goal_progress'] as List<dynamic>?) ?? [];

    return _UserStats(
      totalCompleted: totalCompleted,
      currentStreak: streak,
      goalCount: goals.length,
    );
  } catch (_) {
    return const _UserStats();
  }
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(_userProfileProvider);
    final statsAsync = ref.watch(_userStatsProvider);
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

            // --- Profile header: avatar + name + badges ---
            Center(
              child: Column(
                children: [
                  // Avatar
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.kiwi100,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person,
                        color: AppColors.kiwi600, size: 36),
                  ),
                  const SizedBox(height: 12),

                  // Name
                  profileAsync.when(
                    data: (profile) => Text(
                      profile.name ?? 'Kinwii member',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(
                            color: AppColors.content,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    loading: () => const SizedBox(height: 24),
                    error: (_, __) => Text(
                      'Kinwii member',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(color: AppColors.content),
                    ),
                  ),
                  const SizedBox(height: 4),

                  // Subscription tier chip
                  if (sub.isPro)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.kiwi400,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'PRO',
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                            ),
                      ),
                    )
                  else if (sub.isTrial)
                    Text(
                      '${sub.trialDaysRemaining} days left on trial',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.contentSecondary,
                          ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // --- Badges row ---
            statsAsync.when(
              data: (stats) => Row(
                children: [
                  _BadgeItem(
                    icon: Icons.check_circle_outline,
                    value: '${stats.totalCompleted}',
                    label: 'Completed',
                    color: AppColors.kiwi500,
                  ),
                  _BadgeItem(
                    icon: Icons.local_fire_department_outlined,
                    value: '${stats.currentStreak}',
                    label: 'Week streak',
                    color: const Color(0xFFEF8C3A),
                  ),
                  _BadgeItem(
                    icon: Icons.flag_outlined,
                    value: '${stats.goalCount}',
                    label: stats.goalCount == 1 ? 'Goal' : 'Goals',
                    color: const Color(0xFF6B8AFF),
                  ),
                ],
              ),
              loading: () => const SizedBox(height: 72),
              error: (_, __) => const SizedBox.shrink(),
            ),

            const SizedBox(height: 24),

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
                _SettingsRow(
                  icon: Icons.person_outline,
                  label: 'Account',
                  onTap: () => context.push('/account'),
                ),
                _FirstDayRow(),
                _SettingsRow(
                  icon: Icons.notifications_outlined,
                  label: 'Notifications',
                  onTap: () => context.push('/notifications'),
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
// Badge item — one stat in the profile badges row
// ---------------------------------------------------------------------------

class _BadgeItem extends StatelessWidget {
  const _BadgeItem({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 14),
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
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.content,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.contentSecondary,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
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
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.contentSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.content,
                    ),
              ),
            ),
            if (onTap != null)
              const Icon(Icons.chevron_right,
                  size: 20, color: AppColors.contentTertiary),
          ],
        ),
      ),
    );
  }
}
