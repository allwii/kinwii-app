class Mission {
  final String id;
  final String userId;
  final String statement;
  final DateTime createdAt;

  Mission({
    required this.id,
    required this.userId,
    required this.statement,
    required this.createdAt,
  });

  factory Mission.fromJson(Map<String, dynamic> json) => Mission(
        id: json['id'],
        userId: json['user_id'],
        statement: json['statement'],
        createdAt: DateTime.parse(json['created_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'statement': statement,
        'created_at': createdAt.toIso8601String(),
      };
}
