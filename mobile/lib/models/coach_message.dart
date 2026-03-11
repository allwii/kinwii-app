class CoachMessage {
  final String id;
  final String userId;
  final String role; // "user" or "assistant"
  final String content;
  final DateTime createdAt;

  CoachMessage({
    required this.id,
    required this.userId,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  factory CoachMessage.fromJson(Map<String, dynamic> json) => CoachMessage(
        id: json['id'],
        userId: json['user_id'],
        role: json['role'],
        content: json['content'],
        createdAt: DateTime.parse(json['created_at']),
      );
}
