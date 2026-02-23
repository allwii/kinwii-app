class WeeklyPlan {
  final String id;
  final String userId;
  final String? quarterId;
  final DateTime weekStartDate;
  final String intent;
  final int progressPercent;
  final DateTime createdAt;

  WeeklyPlan({
    required this.id,
    required this.userId,
    this.quarterId,
    required this.weekStartDate,
    required this.intent,
    required this.progressPercent,
    required this.createdAt,
  });

  factory WeeklyPlan.fromJson(Map<String, dynamic> json) => WeeklyPlan(
        id: json['id'],
        userId: json['user_id'],
        quarterId: json['quarter_id'],
        weekStartDate: DateTime.parse(json['week_start_date']),
        intent: json['intent'],
        progressPercent: json['progress_percent'] ?? 0,
        createdAt: DateTime.parse(json['created_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'quarter_id': quarterId,
        'week_start_date': weekStartDate.toIso8601String().split('T').first,
        'intent': intent,
        'progress_percent': progressPercent,
        'created_at': createdAt.toIso8601String(),
      };
}
