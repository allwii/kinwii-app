class DailyIntent {
  final String id;
  final String userId;
  final String? weeklyPlanId;
  final DateTime date;
  final String intent;
  final bool? honored;
  final String? note;
  final DateTime createdAt;

  DailyIntent({
    required this.id,
    required this.userId,
    this.weeklyPlanId,
    required this.date,
    required this.intent,
    this.honored,
    this.note,
    required this.createdAt,
  });

  factory DailyIntent.fromJson(Map<String, dynamic> json) => DailyIntent(
        id: json['id'],
        userId: json['user_id'],
        weeklyPlanId: json['weekly_plan_id'],
        date: DateTime.parse(json['date']),
        intent: json['intent'],
        honored: json['honored'],
        note: json['note'],
        createdAt: DateTime.parse(json['created_at']),
      );

  DailyIntent copyWith({
    bool? honored,
    String? note,
    String? intent,
  }) =>
      DailyIntent(
        id: id,
        userId: userId,
        weeklyPlanId: weeklyPlanId,
        date: date,
        intent: intent ?? this.intent,
        honored: honored ?? this.honored,
        note: note ?? this.note,
        createdAt: createdAt,
      );
}
