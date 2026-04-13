import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../main.dart';
import '../providers/reminder_settings_provider.dart';
import '../widgets/reminder_row.dart';

class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

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
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          'Notifications',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.content,
              ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        children: [
          Container(
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
              children: [
                ReminderRow(
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
                ReminderRow(
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
                ReminderRow(
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
          ),
        ],
      ),
    );
  }
}
