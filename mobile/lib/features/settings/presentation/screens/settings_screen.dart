// SettingsScreen — Production-quality settings with Pro banner, profile,
// grouped sections with icons.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../services/providers.dart';
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
  final bool autoMoveTasks;

  const _UserProfile({
    this.email,
    this.name,
    this.subscriptionTier = 'free',
    this.autoMoveTasks = false,
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
        autoMoveTasks: data['auto_move_tasks'] as bool? ?? false,
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
  final int currentStreak;
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

    final weeks = (data['weekly_completions'] as List<dynamic>?) ?? [];
    int totalCompleted = 0;
    for (final w in weeks) {
      totalCompleted += (w['completed_tasks'] as int? ?? 0);
    }

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
            const SizedBox(height: 20),

            // --- Subscription banner ---
            _SubscriptionBanner(sub: sub, onTap: () => context.push('/pro')),
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
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),

            const SizedBox(height: 24),

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
                _AutoMoveRow(
                  isEnabled: profileAsync.valueOrNull?.autoMoveTasks ?? false,
                  onChanged: (value) async {
                    final api = ref.read(apiServiceProvider);
                    await api.put('/auth/me', data: {'auto_move_tasks': value});
                    ref.read(_userProfileProvider.notifier).refresh();
                  },
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
                      useRootNavigator: true,
                      isScrollControlled: true,
                      backgroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(24)),
                      ),
                      builder: (_) => FeedbackModal(
                        api: ref.read(apiServiceProvider),
                        userEmail: profileAsync.valueOrNull?.email,
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

            const SizedBox(height: 24),

            // --- Stay in touch ---
            const _SectionLabel(label: 'STAY IN TOUCH'),
            const SizedBox(height: 10),
            _SettingsCard(
              children: [
                _SettingsRow(
                  icon: Icons.star_outline_rounded,
                  label: 'Rate App',
                  onTap: () {
                    final uri = Platform.isIOS
                        ? Uri.parse(
                            'https://apps.apple.com/us/app/kinwii-focus-goal-planner/id6762843003?action=write-review')
                        : Uri.parse(
                            'https://play.google.com/store/apps/details?id=com.allvii.kinwii');
                    launchUrl(uri, mode: LaunchMode.externalApplication);
                  },
                ),
                _SettingsRow(
                  icon: Icons.ios_share_outlined,
                  label: 'Share App',
                  onTap: () {
                    SharePlus.instance.share(
                      ShareParams(
                        text:
                            'Check out Kinwii — a calm, AI-powered planner that helps you focus on what matters.\nhttps://apps.apple.com/us/app/kinwii-focus-goal-planner/id6762843003',
                      ),
                    );
                  },
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

/// Dynamic subscription banner — shows different states:
/// - Trial active: countdown + upgrade button (like Structured Pro screenshot 2)
/// - Not subscribed (trial expired): upgrade CTA (like screenshot 1)
/// - Subscribed: Pro active + manage subscription
class _SubscriptionBanner extends StatelessWidget {
  const _SubscriptionBanner({required this.sub, required this.onTap});

  final SubscriptionStatus sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // State 1: Active Pro subscriber
    if (sub.isPro && !sub.isTrial) {
      return _buildProActive(context);
    }
    // State 2: Trial active
    if (sub.isTrial) {
      return _buildTrialActive(context);
    }
    // State 3: Not subscribed / trial expired
    return _buildUpgrade(context);
  }

  Widget _buildProActive(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.kiwi50, AppColors.kiwi100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.kiwi200),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.kiwi400,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.workspace_premium,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Kinwii Pro',
                        style:
                            Theme.of(context).textTheme.titleSmall?.copyWith(
                                  color: AppColors.content,
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'All features unlocked',
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppColors.contentSecondary,
                                ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    size: 20, color: AppColors.contentTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrialActive(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.kiwi50, AppColors.kiwi100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.kiwi200),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.kiwi400,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.workspace_premium,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Kinwii Pro Trial',
                        style:
                            Theme.of(context).textTheme.titleSmall?.copyWith(
                                  color: AppColors.content,
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Your trial ends in ${sub.trialDaysRemaining} day${sub.trialDaysRemaining == 1 ? '' : 's'}',
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppColors.contentSecondary,
                                ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.kiwi400,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Upgrade',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUpgrade(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.kiwi300.withValues(alpha: 0.3), AppColors.kiwi100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.kiwi200),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.kiwi400,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.workspace_premium,
                          color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Get Kinwii Pro',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  color: AppColors.content,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Unlock all features and AI coaching',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: AppColors.contentSecondary,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.kiwi400,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Upgrade Now'),
                  ),
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
// Section label
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
          useRootNavigator: true,
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
// Auto-move unfinished tasks row
// ---------------------------------------------------------------------------

class _AutoMoveRow extends StatelessWidget {
  const _AutoMoveRow({
    required this.isEnabled,
    required this.onChanged,
  });

  final bool isEnabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.redo_rounded,
              size: 20, color: AppColors.contentSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Auto-move unfinished tasks',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.content,
                      ),
                ),
                Text(
                  'Move unfinished tasks to next day',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.contentTertiary,
                      ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: isEnabled,
            onChanged: onChanged,
            activeTrackColor: AppColors.kiwi400,
          ),
        ],
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
