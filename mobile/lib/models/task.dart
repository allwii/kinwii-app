enum EnergyType { deep, admin, creative, personal }

/// A "big rock" (Covey, 7 Habits) is a high-priority weekly task tied to a
/// specific goal. We identify them via a heuristic — no dedicated DB column.
extension TaskBigRock on Task {
  bool get isBigRock =>
      quarterId != null && energyType == EnergyType.deep;
}

class Task {
  final String id;
  final String userId;
  final String weeklyPlanId;
  final String? quarterId;
  final String title;
  final DateTime date;
  final bool completed;
  final EnergyType energyType;
  final String? description;
  final String? startTime;
  final String? endTime;
  final String? skipReason;
  final DateTime createdAt;

  Task({
    required this.id,
    required this.userId,
    required this.weeklyPlanId,
    this.quarterId,
    required this.title,
    required this.date,
    required this.completed,
    required this.energyType,
    this.description,
    this.startTime,
    this.endTime,
    this.skipReason,
    required this.createdAt,
  });

  Task copyWith({
    bool? completed,
    String? description,
    String? startTime,
    String? endTime,
    String? skipReason,
    String? quarterId,
  }) =>
      Task(
        id: id,
        userId: userId,
        weeklyPlanId: weeklyPlanId,
        quarterId: quarterId ?? this.quarterId,
        title: title,
        date: date,
        completed: completed ?? this.completed,
        energyType: energyType,
        description: description ?? this.description,
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
        skipReason: skipReason ?? this.skipReason,
        createdAt: createdAt,
      );

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        id: json['id'],
        userId: json['user_id'],
        weeklyPlanId: json['weekly_plan_id'],
        quarterId: json['quarter_id'] as String?,
        title: json['title'],
        date: DateTime.parse(json['date']),
        completed: json['completed'] ?? false,
        energyType: EnergyType.values.firstWhere(
          (e) => e.name == json['energy_type'],
          orElse: () => EnergyType.deep,
        ),
        description: json['description'] as String?,
        startTime: json['start_time'] as String?,
        endTime: json['end_time'] as String?,
        skipReason: json['skip_reason'] as String?,
        createdAt: DateTime.parse(json['created_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'weekly_plan_id': weeklyPlanId,
        if (quarterId != null) 'quarter_id': quarterId,
        'title': title,
        'date': date.toIso8601String().split('T').first,
        'completed': completed,
        'energy_type': energyType.name,
        if (description != null) 'description': description,
        if (startTime != null) 'start_time': startTime,
        if (endTime != null) 'end_time': endTime,
        if (skipReason != null) 'skip_reason': skipReason,
        'created_at': createdAt.toIso8601String(),
      };
}
