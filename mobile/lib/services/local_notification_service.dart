import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class LocalNotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();

  static const _channelId = 'kinwii_reminders';
  static const _channelName = 'Kinwii Reminders';
  static const _channelDesc =
      'Daily planning, reflection, and weekly review reminders';

  static const _dailyPlanningBaseId = 100;
  static const _dailyReflectionBaseId = 200;
  static const _weeklyReflectionId = 300;

  Future<void> init() async {
    tz.initializeTimeZones();

    // Set local timezone using the native platform API
    try {
      final tzInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzInfo.identifier));
    } catch (_) {
      // Fall back to UTC if timezone detection fails
    }

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );
  }

  /// Schedule all default notifications. Call on app start to ensure
  /// reminders are active even if the user never visits Settings.
  Future<void> scheduleDefaults() async {
    // One-time migration: reschedule all notifications with correct timezone.
    final box = await Hive.openBox('kinwii_flags');
    final tzFixed = box.get('tz_fix_v1', defaultValue: false) as bool;

    final pending = await _plugin.pendingNotificationRequests();
    if (pending.isNotEmpty && !tzFixed) {
      // Cancel old (possibly wrong-timezone) notifications and reschedule.
      await cancelAll();
      await box.put('tz_fix_v1', true);
    } else if (pending.isNotEmpty) {
      return; // Already scheduled with correct timezone
    } else {
      await box.put('tz_fix_v1', true);
    }

    // Read user-saved times from Hive, falling back to defaults.
    final settings = await Hive.openBox('kinwii_settings');
    final dpEnabled = settings.get('dp_enabled', defaultValue: true) as bool;
    final drEnabled = settings.get('dr_enabled', defaultValue: true) as bool;
    final wrEnabled = settings.get('wr_enabled', defaultValue: true) as bool;

    if (dpEnabled) {
      await scheduleDailyPlanningReminder(TimeOfDay(
        hour: settings.get('dp_hour', defaultValue: 9) as int,
        minute: settings.get('dp_min', defaultValue: 0) as int,
      ));
    }
    if (drEnabled) {
      await scheduleDailyReflectionReminder(TimeOfDay(
        hour: settings.get('dr_hour', defaultValue: 17) as int,
        minute: settings.get('dr_min', defaultValue: 30) as int,
      ));
    }
    if (wrEnabled) {
      await scheduleWeeklyReflectionReminder(TimeOfDay(
        hour: settings.get('wr_hour', defaultValue: 9) as int,
        minute: settings.get('wr_min', defaultValue: 15) as int,
      ));
    }
  }

  Future<void> requestPermissions() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  NotificationDetails get _details => const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      );

  Future<void> _scheduleWeekday({
    required int baseId,
    required TimeOfDay time,
    required String title,
    required String body,
  }) async {
    for (var day = DateTime.monday; day <= DateTime.friday; day++) {
      await _plugin.zonedSchedule(
        id: baseId + (day - 1),
        title: title,
        body: body,
        scheduledDate: _nextInstanceOfDayTime(day, time),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  Future<void> _scheduleMonday({
    required int id,
    required TimeOfDay time,
    required String title,
    required String body,
  }) async {
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: _nextInstanceOfDayTime(DateTime.monday, time),
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  tz.TZDateTime _nextInstanceOfDayTime(int weekday, TimeOfDay time) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, time.hour, time.minute);
    while (scheduled.weekday != weekday) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 7));
    }
    return scheduled;
  }

  // --- Public API ---

  Future<void> scheduleDailyPlanningReminder(TimeOfDay time) async {
    await _cancelRange(_dailyPlanningBaseId, 5);
    await _scheduleWeekday(
      baseId: _dailyPlanningBaseId,
      time: time,
      title: 'Plan your day',
      body: 'Take a moment to set your focus for today.',
    );
  }

  Future<void> scheduleDailyReflectionReminder(TimeOfDay time) async {
    await _cancelRange(_dailyReflectionBaseId, 5);
    await _scheduleWeekday(
      baseId: _dailyReflectionBaseId,
      time: time,
      title: 'Time to reflect',
      body: 'How did today go? Review your tasks.',
    );
  }

  Future<void> scheduleWeeklyReflectionReminder(TimeOfDay time) async {
    await _plugin.cancel(id: _weeklyReflectionId);
    await _scheduleMonday(
      id: _weeklyReflectionId,
      time: time,
      title: 'Weekly review',
      body: 'Reflect on your week and plan ahead.',
    );
  }

  Future<void> cancelDailyPlanning() =>
      _cancelRange(_dailyPlanningBaseId, 5);

  Future<void> cancelDailyReflection() =>
      _cancelRange(_dailyReflectionBaseId, 5);

  Future<void> cancelWeeklyReflection() =>
      _plugin.cancel(id: _weeklyReflectionId);

  Future<void> cancelAll() => _plugin.cancelAll();

  Future<void> _cancelRange(int baseId, int count) async {
    for (var i = 0; i < count; i++) {
      await _plugin.cancel(id: baseId + i);
    }
  }
}
