class QuarterlyGoal {
  final String id;
  final String userId;
  final String title;
  final String? why;
  final DateTime startDate;
  final DateTime endDate;
  final int progressPercent;
  final String? roleId;
  final String? roleName;
  final DateTime createdAt;

  QuarterlyGoal({
    required this.id,
    required this.userId,
    required this.title,
    this.why,
    required this.startDate,
    required this.endDate,
    required this.progressPercent,
    this.roleId,
    this.roleName,
    required this.createdAt,
  });

  factory QuarterlyGoal.fromJson(Map<String, dynamic> json) => QuarterlyGoal(
        id: json['id'],
        userId: json['user_id'],
        title: json['title'],
        why: json['why'],
        startDate: DateTime.parse(json['start_date']),
        endDate: DateTime.parse(json['end_date']),
        progressPercent: json['progress_percent'] ?? 0,
        roleId: json['role_id'],
        roleName: json['role_name'],
        createdAt: DateTime.parse(json['created_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'title': title,
        'why': why,
        'start_date': startDate.toIso8601String().split('T').first,
        'end_date': endDate.toIso8601String().split('T').first,
        'progress_percent': progressPercent,
        'role_id': roleId,
        'role_name': roleName,
        'created_at': createdAt.toIso8601String(),
      };
}
