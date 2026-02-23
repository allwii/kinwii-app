class WeeklyReflection {
  final String id;
  final String userId;
  final String weeklyPlanId;
  final String? movedNeedle;
  final String? drainedEnergy;
  final String? stopDoing;
  final String? focusNextWeek;
  final String? aiSummary;
  final String? aiFocusRecommendation;
  final DateTime createdAt;

  WeeklyReflection({
    required this.id,
    required this.userId,
    required this.weeklyPlanId,
    this.movedNeedle,
    this.drainedEnergy,
    this.stopDoing,
    this.focusNextWeek,
    this.aiSummary,
    this.aiFocusRecommendation,
    required this.createdAt,
  });

  factory WeeklyReflection.fromJson(Map<String, dynamic> json) =>
      WeeklyReflection(
        id: json['id'],
        userId: json['user_id'],
        weeklyPlanId: json['weekly_plan_id'],
        movedNeedle: json['moved_needle'],
        drainedEnergy: json['drained_energy'],
        stopDoing: json['stop_doing'],
        focusNextWeek: json['focus_next_week'],
        aiSummary: json['ai_summary'],
        aiFocusRecommendation: json['ai_focus_recommendation'],
        createdAt: DateTime.parse(json['created_at']),
      );
}
