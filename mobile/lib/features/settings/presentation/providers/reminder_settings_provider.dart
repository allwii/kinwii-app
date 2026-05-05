import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

class ReminderSettings {
  final bool dailyPlanningEnabled;
  final TimeOfDay dailyPlanningTime;
  final bool dailyReflectionEnabled;
  final TimeOfDay dailyReflectionTime;
  final bool weeklyReflectionEnabled;
  final TimeOfDay weeklyReflectionTime;
  final int weeklyReflectionDay; // DateTime.monday (1) – DateTime.sunday (7)

  static const dayLabels = {
    DateTime.monday: 'Monday',
    DateTime.tuesday: 'Tuesday',
    DateTime.wednesday: 'Wednesday',
    DateTime.thursday: 'Thursday',
    DateTime.friday: 'Friday',
    DateTime.saturday: 'Saturday',
    DateTime.sunday: 'Sunday',
  };

  const ReminderSettings({
    this.dailyPlanningEnabled = true,
    this.dailyPlanningTime = const TimeOfDay(hour: 9, minute: 0),
    this.dailyReflectionEnabled = true,
    this.dailyReflectionTime = const TimeOfDay(hour: 17, minute: 30),
    this.weeklyReflectionEnabled = true,
    this.weeklyReflectionTime = const TimeOfDay(hour: 9, minute: 15),
    this.weeklyReflectionDay = DateTime.monday,
  });

  String get weeklyReflectionDayLabel =>
      dayLabels[weeklyReflectionDay] ?? 'Monday';

  ReminderSettings copyWith({
    bool? dailyPlanningEnabled,
    TimeOfDay? dailyPlanningTime,
    bool? dailyReflectionEnabled,
    TimeOfDay? dailyReflectionTime,
    bool? weeklyReflectionEnabled,
    TimeOfDay? weeklyReflectionTime,
    int? weeklyReflectionDay,
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
        weeklyReflectionDay:
            weeklyReflectionDay ?? this.weeklyReflectionDay,
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
      weeklyReflectionDay:
          box.get('wr_day', defaultValue: DateTime.monday) as int,
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
    await box.put('wr_day', settings.weeklyReflectionDay);
  }
}
