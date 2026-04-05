import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/presentation/screens/login_screen.dart';

class NotificationPreferences {
  final bool morningFocus;
  final bool eveningReflect;
  final bool midweekProgress;

  const NotificationPreferences({
    this.morningFocus = true,
    this.eveningReflect = true,
    this.midweekProgress = true,
  });

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      morningFocus: json['morning_focus'] as bool? ?? true,
      eveningReflect: json['evening_reflect'] as bool? ?? true,
      midweekProgress: json['midweek_progress'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'morning_focus': morningFocus,
        'evening_reflect': eveningReflect,
        'midweek_progress': midweekProgress,
      };
}

final notificationPrefsProvider = StateNotifierProvider<
    NotificationPrefsNotifier, NotificationPreferences>(
  (ref) => NotificationPrefsNotifier(ref),
);

class NotificationPrefsNotifier
    extends StateNotifier<NotificationPreferences> {
  NotificationPrefsNotifier(this._ref)
      : super(const NotificationPreferences()) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    try {
      final api = _ref.read(apiServiceProvider);
      final response = await api.get('/notifications/preferences');
      state = NotificationPreferences.fromJson(
          response.data as Map<String, dynamic>);
    } catch (_) {
      // Keep defaults
    }
  }

  Future<void> update(NotificationPreferences prefs) async {
    state = prefs;
    try {
      final api = _ref.read(apiServiceProvider);
      await api.put('/notifications/preferences', data: prefs.toJson());
    } catch (_) {
      // Revert could go here, but for simplicity keep optimistic
    }
  }

  Future<void> registerToken(String fcmToken) async {
    try {
      final api = _ref.read(apiServiceProvider);
      await api.post('/notifications/register-token', data: {
        'fcm_token': fcmToken,
      });
    } catch (_) {
      // Silent fail — will retry next launch
    }
  }
}
