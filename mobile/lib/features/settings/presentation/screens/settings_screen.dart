// SettingsScreen — Production-quality settings with profile, reminders, account.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../features/auth/presentation/screens/login_screen.dart';
import '../../../../main.dart';
import '../widgets/password_reset_modal.dart';

// ---------------------------------------------------------------------------
// Settings persistence via Hive
// ---------------------------------------------------------------------------

class ReminderSettings {
  final bool dailyPlanningEnabled;
  final TimeOfDay dailyPlanningTime;
  final bool dailyReflectionEnabled;
  final TimeOfDay dailyReflectionTime;
  final bool weeklyReflectionEnabled;
  final TimeOfDay weeklyReflectionTime;

  const ReminderSettings({
    this.dailyPlanningEnabled = true,
    this.dailyPlanningTime = const TimeOfDay(hour: 9, minute: 0),
    this.dailyReflectionEnabled = true,
    this.dailyReflectionTime = const TimeOfDay(hour: 17, minute: 30),
    this.weeklyReflectionEnabled = true,
    this.weeklyReflectionTime = const TimeOfDay(hour: 9, minute: 15),
  });

  ReminderSettings copyWith({
    bool? dailyPlanningEnabled,
    TimeOfDay? dailyPlanningTime,
    bool? dailyReflectionEnabled,
    TimeOfDay? dailyReflectionTime,
    bool? weeklyReflectionEnabled,
    TimeOfDay? weeklyReflectionTime,
  }) =>
      ReminderSettings(
        dailyPlanningEnabled:
            dailyPlanningEnabled ?? this.dailyPlanningEnabled,
        dailyPlanningTime: dailyPlanningTime ?? this.dailyPlanningTime,
        dailyReflectionEnabled:
            dailyReflectionEnabled ?? this.dailyReflectionEnabled,
        dailyReflectionTime:
            dailyReflectionTime ?? this.dailyReflectionTime,
        weeklyReflectionEnabled:
            weeklyReflectionEnabled ?? this.weeklyReflectionEnabled,
        weeklyReflectionTime:
            weeklyReflectionTime ?? this.weeklyReflectionTime,
      );
}

final reminderSettingsProvider =
    StateNotifierProvider<ReminderSettingsNotifier, ReminderSettings>(
  (ref) => ReminderSettingsNotifier(),
);

class ReminderSettingsNotifier extends StateNotifier<ReminderSettings> {
  ReminderSettingsNotifier() : super(const ReminderSettings()) {
    _load();
  }

  static const _boxName = 'kinwii_settings';

  Future<void> _load() async {
    final box = await Hive.openBox(_boxName);
    state = ReminderSettings(
      dailyPlanningEnabled: box.get('dp_enabled', defaultValue: true),
      dailyPlanningTime: TimeOfDay(
        hour: box.get('dp_hour', defaultValue: 9),
        minute: box.get('dp_min', defaultValue: 0),
      ),
      dailyReflectionEnabled: box.get('dr_enabled', defaultValue: true),
      dailyReflectionTime: TimeOfDay(
        hour: box.get('dr_hour', defaultValue: 17),
        minute: box.get('dr_min', defaultValue: 30),
      ),
      weeklyReflectionEnabled: box.get('wr_enabled', defaultValue: true),
      weeklyReflectionTime: TimeOfDay(
        hour: box.get('wr_hour', defaultValue: 9),
        minute: box.get('wr_min', defaultValue: 15),
      ),
    );
  }

  Future<void> update(ReminderSettings settings) async {
    state = settings;
    final box = await Hive.openBox(_boxName);
    await box.put('dp_enabled', settings.dailyPlanningEnabled);
    await box.put('dp_hour', settings.dailyPlanningTime.hour);
    await box.put('dp_min', settings.dailyPlanningTime.minute);
    await box.put('dr_enabled', settings.dailyReflectionEnabled);
    await box.put('dr_hour', settings.dailyReflectionTime.hour);
    await box.put('dr_min', settings.dailyReflectionTime.minute);
    await box.put('wr_enabled', settings.weeklyReflectionEnabled);
    await box.put('wr_hour', settings.weeklyReflectionTime.hour);
    await box.put('wr_min', settings.weeklyReflectionTime.minute);
  }
}

// User email provider
final _userEmailProvider = FutureProvider<String?>((ref) async {
  final api = ref.read(apiServiceProvider);
  try {
    final resp = await api.get('/auth/me');
    return resp.data['email'] as String?;
  } catch (_) {
    return null;
  }
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  void _updateAndSchedule(WidgetRef ref, ReminderSettings settings) {
    ref.read(reminderSettingsProvider.notifier).update(settings);
    final ns = ref.read(localNotificationProvider);
    if (settings.dailyPlanningEnabled) {
      ns.scheduleDailyPlanningReminder(settings.dailyPlanningTime);
    } else {
      ns.cancelDailyPlanning();
    }
    if (settings.dailyReflectionEnabled) {
      ns.scheduleDailyReflectionReminder(settings.dailyReflectionTime);
    } else {
      ns.cancelDailyReflection();
    }
    if (settings.weeklyReflectionEnabled) {
      ns.scheduleWeeklyReflectionReminder(settings.weeklyReflectionTime);
    } else {
      ns.cancelWeeklyReflection();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(reminderSettingsProvider);
    final emailAsync = ref.watch(_userEmailProvider);

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

            // --- Profile section ---
            Container(
              padding: const EdgeInsets.all(16),
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
              child: Row(
                children: [
                  // Avatar
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        emailAsync.when(
                          data: (email) => Text(
                            email ?? 'User',
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
                            'User',
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(color: AppColors.content),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Kinwii member',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.contentTertiary,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // --- Reminders section ---
            _SectionLabel(label: 'REMINDERS'),
            const SizedBox(height: 10),
            _SettingsCard(
              children: [
                _ReminderRow(
                  label: 'Daily planning',
                  sublabel: 'Weekdays',
                  time: settings.dailyPlanningTime,
                  enabled: settings.dailyPlanningEnabled,
                  onToggle: (v) => _updateAndSchedule(
                      ref, settings.copyWith(dailyPlanningEnabled: v)),
                  onTimeTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: settings.dailyPlanningTime,
                    );
                    if (picked != null) {
                      _updateAndSchedule(
                          ref, settings.copyWith(dailyPlanningTime: picked));
                    }
                  },
                ),
                const SizedBox(height: 2),
                _ReminderRow(
                  label: 'Daily reflection',
                  sublabel: 'Weekdays',
                  time: settings.dailyReflectionTime,
                  enabled: settings.dailyReflectionEnabled,
                  onToggle: (v) => _updateAndSchedule(
                      ref, settings.copyWith(dailyReflectionEnabled: v)),
                  onTimeTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: settings.dailyReflectionTime,
                    );
                    if (picked != null) {
                      _updateAndSchedule(ref,
                          settings.copyWith(dailyReflectionTime: picked));
                    }
                  },
                ),
                const SizedBox(height: 2),
                _ReminderRow(
                  label: 'Weekly review',
                  sublabel: 'Monday',
                  time: settings.weeklyReflectionTime,
                  enabled: settings.weeklyReflectionEnabled,
                  onToggle: (v) => _updateAndSchedule(
                      ref, settings.copyWith(weeklyReflectionEnabled: v)),
                  onTimeTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: settings.weeklyReflectionTime,
                    );
                    if (picked != null) {
                      _updateAndSchedule(ref,
                          settings.copyWith(weeklyReflectionTime: picked));
                    }
                  },
                ),
              ],
            ),

            const SizedBox(height: 28),

            // --- Account section ---
            const _SectionLabel(label: 'ACCOUNT'),
            const SizedBox(height: 10),
            _SettingsCard(
              children: [
                _SettingsRow(
                  icon: Icons.lock_outline,
                  label: 'Change password',
                  onTap: () {
                    final email = ref.read(_userEmailProvider).valueOrNull;
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
                const SizedBox(height: 2),
                _SettingsRow(
                  icon: Icons.psychology_outlined,
                  label: 'AI Coach',
                  onTap: () => context.push('/coach'),
                ),
              ],
            ),

            const SizedBox(height: 28),

            // --- Support section ---
            const _SectionLabel(label: 'SUPPORT'),
            const SizedBox(height: 10),
            _SettingsCard(
              children: [
                _SettingsRow(
                  icon: Icons.chat_bubble_outline,
                  label: 'Send feedback',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Feedback form coming soon.')),
                    );
                  },
                ),
                const SizedBox(height: 2),
                _SettingsRow(
                  icon: Icons.info_outline,
                  label: 'App version',
                  trailing: Text(
                    '1.0.0',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.contentTertiary,
                        ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // Sign out
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () async {
                  await ref.read(authServiceProvider).logout();
                  if (context.mounted) context.go('/auth/login');
                },
                child: const Text('Sign out'),
              ),
            ),

            const SizedBox(height: 12),

            // Delete account
            Center(
              child: TextButton(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Delete account?'),
                      content: const Text(
                          'This will permanently delete your account and all data. This cannot be undone.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Delete',
                              style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Account deletion coming soon.')),
                    );
                  }
                },
                child: Text(
                  'Delete account',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.red.shade300,
                      ),
                ),
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
// Generic settings row (icon + label + chevron)
// ---------------------------------------------------------------------------

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Widget? trailing;

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
            if (trailing != null)
              trailing!
            else if (onTap != null)
              const Icon(Icons.chevron_right,
                  size: 20, color: AppColors.contentTertiary),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reminder row (label + time chip + toggle)
// ---------------------------------------------------------------------------

class _ReminderRow extends StatelessWidget {
  const _ReminderRow({
    required this.label,
    required this.sublabel,
    required this.time,
    required this.enabled,
    required this.onToggle,
    required this.onTimeTap,
  });

  final String label;
  final String sublabel;
  final TimeOfDay time;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTimeTap;

  String _formatTime(TimeOfDay t) {
    final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final min = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$min $period';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.content,
                      ),
                ),
                Text(
                  sublabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.contentTertiary,
                      ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: enabled ? onTimeTap : null,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: enabled ? AppColors.kiwi50 : AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _formatTime(time),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: enabled
                          ? AppColors.kiwi700
                          : AppColors.contentTertiary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 24,
            child: FittedBox(
              child: Switch.adaptive(
                value: enabled,
                onChanged: onToggle,
                activeTrackColor: AppColors.kiwi400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
