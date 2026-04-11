enum EnergyType { deep, admin, creative, personal }

class Task {
  final String id;
  final String userId;
  final String weeklyPlanId;
  final String title;
  final DateTime date;
  final bool completed;
  final EnergyType energyType;
  final String? description;
  final String? time;
  final String? skipReason;
  final DateTime createdAt;

  Task({
    required this.id,
    required this.userId,
    required this.weeklyPlanId,
    required this.title,
    required this.date,
    required this.completed,
    required this.energyType,
    this.description,
    this.time,
    this.skipReason,
    required this.createdAt,
  });

  Task copyWith({
    bool? completed,
    String? description,
    String? time,
    String? skipReason,
  }) =>
      Task(
        id: id,
        userId: userId,
        weeklyPlanId: weeklyPlanId,
        title: title,
        date: date,
        completed: completed ?? this.completed,
        energyType: energyType,
        description: description ?? this.description,
        time: time ?? this.time,
        skipReason: skipReason ?? this.skipReason,
        createdAt: createdAt,
      );

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        id: json['id'],
        userId: json['user_id'],
        weeklyPlanId: json['weekly_plan_id'],
        title: json['title'],
        date: DateTime.parse(json['date']),
        completed: json['completed'] ?? false,
        energyType: EnergyType.values.firstWhere(
          (e) => e.name == json['energy_type'],
          orElse: () => EnergyType.deep,
        ),
        description: json['description'] as String?,
        time: json['time'] as String?,
        skipReason: json['skip_reason'] as String?,
        createdAt: DateTime.parse(json['created_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'weekly_plan_id': weeklyPlanId,
        'title': title,
        'date': date.toIso8601String().split('T').first,
        'completed': completed,
        'energy_type': energyType.name,
        if (description != null) 'description': description,
        if (time != null) 'time': time,
        if (skipReason != null) 'skip_reason': skipReason,
        'created_at': createdAt.toIso8601String(),
      };
}
