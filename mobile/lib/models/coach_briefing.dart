class CoachBriefing {
  final String id;
  final DateTime date;
  final String headline;

  /// Present only for Pro users; `null` for free-tier responses.
  final String? body;

  /// Empty for free-tier responses.
  final List<String> followups;

  final bool isPro;
  final DateTime createdAt;

  const CoachBriefing({
    required this.id,
    required this.date,
    required this.headline,
    required this.body,
    required this.followups,
    required this.isPro,
    required this.createdAt,
  });

  factory CoachBriefing.fromJson(Map<String, dynamic> json) => CoachBriefing(
        id: json['id'] as String,
        date: DateTime.parse(json['date'] as String),
        headline: json['headline'] as String,
        body: json['body'] as String?,
        followups: ((json['followups'] as List<dynamic>?) ?? const [])
            .map((e) => e as String)
            .toList(),
        isPro: json['is_pro'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
