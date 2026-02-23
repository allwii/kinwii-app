enum EnergyType { deep, admin, creative, personal }

class Task {
  final String id;
  final String userId;
  final String weeklyPlanId;
  final String title;
  final DateTime date;
  final bool completed;
  final EnergyType energyType;
  final DateTime createdAt;

  Task({
    required this.id,
    required this.userId,
    required this.weeklyPlanId,
    required this.title,
    required this.date,
    required this.completed,
    required this.energyType,
    required this.createdAt,
  });

  Task copyWith({bool? completed}) => Task(
        id: id,
        userId: userId,
        weeklyPlanId: weeklyPlanId,
        title: title,
        date: date,
        completed: completed ?? this.completed,
        energyType: energyType,
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
        'created_at': createdAt.toIso8601String(),
      };
}
