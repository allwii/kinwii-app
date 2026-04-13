// AnalyticsScreen — Progress analytics: completion trends, energy breakdown,
// weekly rhythm, and goal progress.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../features/auth/presentation/screens/login_screen.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class _WeekCompletion {
  final DateTime weekStart;
  final int totalTasks;
  final int completedTasks;
  final double completionRate;

  _WeekCompletion({
    required this.weekStart,
    required this.totalTasks,
    required this.completedTasks,
    required this.completionRate,
  });

  factory _WeekCompletion.fromJson(Map<String, dynamic> j) => _WeekCompletion(
        weekStart: DateTime.parse(j['week_start'] as String),
        totalTasks: j['total_tasks'] as int,
        completedTasks: j['completed_tasks'] as int,
        completionRate: (j['completion_rate'] as num).toDouble(),
      );
}

class _EnergyBreakdown {
  final String energyType;
  final int count;

  _EnergyBreakdown({required this.energyType, required this.count});

  factory _EnergyBreakdown.fromJson(Map<String, dynamic> j) =>
      _EnergyBreakdown(
        energyType: j['energy_type'] as String,
        count: j['count'] as int,
      );
}

class _RhythmWeek {
  final DateTime weekStart;
  final bool hadIntent;
  final bool hadTaskDone;
  final bool hadReflection;
  final bool isRhythmWeek;

  _RhythmWeek({
    required this.weekStart,
    required this.hadIntent,
    required this.hadTaskDone,
    required this.hadReflection,
    required this.isRhythmWeek,
  });

  factory _RhythmWeek.fromJson(Map<String, dynamic> j) => _RhythmWeek(
        weekStart: DateTime.parse(j['week_start'] as String),
        hadIntent: j['had_intent'] as bool,
        hadTaskDone: j['had_task_done'] as bool,
        hadReflection: j['had_reflection'] as bool,
        isRhythmWeek: j['is_rhythm_week'] as bool,
      );
}

class _GoalProgress {
  final String goalId;
  final String title;
  final int progressPercent;
  final int weeksRemaining;

  _GoalProgress({
    required this.goalId,
    required this.title,
    required this.progressPercent,
    required this.weeksRemaining,
  });

  factory _GoalProgress.fromJson(Map<String, dynamic> j) => _GoalProgress(
        goalId: j['goal_id'] as String,
        title: j['title'] as String,
        progressPercent: j['progress_percent'] as int,
        weeksRemaining: j['weeks_remaining'] as int,
      );
}

class _AnalyticsData {
  final List<_WeekCompletion> weeklyCompletions;
  final List<_EnergyBreakdown> energyBreakdown;
  final List<_RhythmWeek> rhythmWeeks;
  final List<_GoalProgress> goalProgress;

  _AnalyticsData({
    required this.weeklyCompletions,
    required this.energyBreakdown,
    required this.rhythmWeeks,
    required this.goalProgress,
  });

  factory _AnalyticsData.fromJson(Map<String, dynamic> j) => _AnalyticsData(
        weeklyCompletions: (j['weekly_completions'] as List)
            .map((e) =>
                _WeekCompletion.fromJson(e as Map<String, dynamic>))
            .toList(),
        energyBreakdown: (j['energy_breakdown'] as List)
            .map((e) =>
                _EnergyBreakdown.fromJson(e as Map<String, dynamic>))
            .toList(),
        rhythmWeeks: (j['rhythm_weeks'] as List)
            .map((e) => _RhythmWeek.fromJson(e as Map<String, dynamic>))
            .toList(),
        goalProgress: (j['goal_progress'] as List)
            .map((e) =>
                _GoalProgress.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final _analyticsProvider =
    FutureProvider.autoDispose<_AnalyticsData>((ref) async {
  final api = ref.read(apiServiceProvider);
  final response = await api.get('/analytics/progress', queryParameters: {
    'weeks': 8,
  });
  return _AnalyticsData.fromJson(response.data as Map<String, dynamic>);
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(_analyticsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.content),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Progress',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColors.content,
              ),
        ),
        centerTitle: true,
      ),
      body: dataAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.kiwi400),
        ),
        error: (_, __) => const Center(
          child: Text('Could not load analytics.'),
        ),
        data: (data) => RefreshIndicator(
          color: AppColors.kiwi400,
          onRefresh: () async => ref.invalidate(_analyticsProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
            children: [
              _RhythmSection(data.rhythmWeeks),
              const SizedBox(height: 24),
              _CompletionTrendSection(data.weeklyCompletions),
              const SizedBox(height: 24),
              _EnergySection(data.energyBreakdown),
              const SizedBox(height: 24),
              _GoalProgressSection(data.goalProgress),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Weekly Rhythm section (forgiving consistency)
// ---------------------------------------------------------------------------

class _RhythmSection extends StatelessWidget {
  const _RhythmSection(this.weeks);

  final List<_RhythmWeek> weeks;

  @override
  Widget build(BuildContext context) {
    final rhythmCount = weeks.where((w) => w.isRhythmWeek).length;
    final total = weeks.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Weekly rhythm',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.content,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          '$rhythmCount of $total weeks in rhythm',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.contentSecondary,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          'A rhythm week = intent set + task done + reflected',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.contentTertiary,
              ),
        ),
        const SizedBox(height: 12),
        Row(
          children: weeks.map((w) {
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  children: [
                    Container(
                      height: 32,
                      decoration: BoxDecoration(
                        color: w.isRhythmWeek
                            ? AppColors.kiwi400
                            : w.hadIntent || w.hadTaskDone
                                ? AppColors.kiwi100
                                : AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: w.isRhythmWeek
                          ? const Center(
                              child: Icon(Icons.check,
                                  size: 16, color: Colors.white),
                            )
                          : null,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('M/d').format(w.weekStart),
                      style:
                          Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: AppColors.contentTertiary,
                                fontSize: 9,
                              ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Completion trend section
// ---------------------------------------------------------------------------

class _CompletionTrendSection extends StatelessWidget {
  const _CompletionTrendSection(this.weeks);

  final List<_WeekCompletion> weeks;

  @override
  Widget build(BuildContext context) {
    final maxTasks =
        weeks.fold<int>(0, (m, w) => w.totalTasks > m ? w.totalTasks : m);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Task completion',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.content,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Completed vs total tasks per week',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.contentTertiary,
              ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 100,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: weeks.map((w) {
              final totalHeight =
                  maxTasks > 0 ? (w.totalTasks / maxTasks) * 80 : 0.0;
              final doneHeight =
                  maxTasks > 0 ? (w.completedTasks / maxTasks) * 80 : 0.0;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      SizedBox(
                        height: 80,
                        child: Stack(
                          alignment: Alignment.bottomCenter,
                          children: [
                            Container(
                              height: totalHeight,
                              decoration: BoxDecoration(
                                color: AppColors.surfaceAlt,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            Container(
                              height: doneHeight,
                              decoration: BoxDecoration(
                                color: AppColors.kiwi400,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('M/d').format(w.weekStart),
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(
                              color: AppColors.contentTertiary,
                              fontSize: 9,
                            ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: AppColors.kiwi400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 4),
            Text('Done',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.contentTertiary)),
            const SizedBox(width: 12),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 4),
            Text('Total',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.contentTertiary)),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Energy breakdown section
// ---------------------------------------------------------------------------

class _EnergySection extends StatelessWidget {
  const _EnergySection(this.breakdown);

  final List<_EnergyBreakdown> breakdown;

  static const _colors = {
    'deep': AppColors.energyDeep,
    'admin': AppColors.energyAdmin,
    'creative': AppColors.energyCreative,
    'personal': AppColors.energyPersonal,
  };

  static const _labels = {
    'deep': 'Deep work',
    'admin': 'Admin',
    'creative': 'Creative',
    'personal': 'Personal',
  };

  @override
  Widget build(BuildContext context) {
    final total = breakdown.fold<int>(0, (s, e) => s + e.count);
    if (total == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Energy breakdown',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.content,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Complete some tasks to see your energy mix.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.contentTertiary,
                ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Energy breakdown',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.content,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Completed tasks by energy type',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.contentTertiary,
              ),
        ),
        const SizedBox(height: 12),
        // Stacked bar
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 20,
            child: Row(
              children: breakdown.map((e) {
                final fraction = e.count / total;
                return Expanded(
                  flex: (fraction * 100).round().clamp(1, 100),
                  child: Container(
                    color: _colors[e.energyType] ?? AppColors.surfaceAlt,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: breakdown.map((e) {
            final pct = ((e.count / total) * 100).round();
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _colors[e.energyType] ?? AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(color: AppColors.borderSubtle),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${_labels[e.energyType] ?? e.energyType} $pct%',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.contentSecondary,
                      ),
                ),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Goal progress section
// ---------------------------------------------------------------------------

class _GoalProgressSection extends StatelessWidget {
  const _GoalProgressSection(this.goals);

  final List<_GoalProgress> goals;

  @override
  Widget build(BuildContext context) {
    if (goals.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Goal progress',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.content,
              ),
        ),
        const SizedBox(height: 12),
        ...goals.map((g) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          g.title,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppColors.content),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${g.weeksRemaining} wk${g.weeksRemaining == 1 ? '' : 's'} left',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.contentTertiary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: g.progressPercent / 100,
                      minHeight: 8,
                      backgroundColor: AppColors.surfaceAlt,
                      color: AppColors.kiwi400,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${g.progressPercent}%',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.contentSecondary,
                        ),
                  ),
                ],
              ),
            )),
      ],
    );
  }
}
