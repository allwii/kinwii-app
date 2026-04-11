// SettingsScreen — Configure reminders and account.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../features/auth/presentation/screens/login_screen.dart';
import '../../../../main.dart';

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

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  void _updateAndSchedule(
      WidgetRef ref, ReminderSettings settings) {
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

            // --- Reminders section ---
            Text(
              'REMINDERS',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.contentSecondary,
                    letterSpacing: 1.2,
                  ),
            ),
            const SizedBox(height: 12),
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
            const SizedBox(height: 8),
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
                  _updateAndSchedule(
                      ref, settings.copyWith(dailyReflectionTime: picked));
                }
              },
            ),
            const SizedBox(height: 8),
            _ReminderRow(
              label: 'Weekly reflection',
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
                  _updateAndSchedule(
                      ref, settings.copyWith(weeklyReflectionTime: picked));
                }
              },
            ),

            const SizedBox(height: 32),

            // --- Account section ---
            Text(
              'ACCOUNT',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.contentSecondary,
                    letterSpacing: 1.2,
                  ),
            ),
            const SizedBox(height: 12),
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
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reminder row
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderSubtle),
      ),
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
          Switch.adaptive(
            value: enabled,
            onChanged: onToggle,
            activeColor: AppColors.kiwi400,
          ),
        ],
      ),
    );
  }
}
