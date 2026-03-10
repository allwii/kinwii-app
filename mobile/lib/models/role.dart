class Role {
  final String id;
  final String userId;
  final String name;
  final String? description;
  final DateTime createdAt;

  Role({
    required this.id,
    required this.userId,
    required this.name,
    this.description,
    required this.createdAt,
  });

  factory Role.fromJson(Map<String, dynamic> json) => Role(
        id: json['id'],
        userId: json['user_id'],
        name: json['name'],
        description: json['description'],
        createdAt: DateTime.parse(json['created_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'name': name,
        'description': description,
        'created_at': createdAt.toIso8601String(),
      };
}
