// GoalDetailScreen - Full detail view for a single QuarterlyGoal.
// Usage: Registered as /goals/:id route. Receives goalId as a path parameter.
//
// Example GoRouter config:
//   GoRoute(
//     path: '/goals/:id',
//     builder: (context, state) =>
//         GoalDetailScreen(goalId: state.pathParameters['id']!),
//   )

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/kinwii_card.dart';
import '../../../../core/widgets/progress_bar.dart';
import '../../../../models/quarterly_goal.dart';
import '../../../../features/auth/presentation/screens/login_screen.dart';

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final _goalDetailProvider =
    FutureProvider.autoDispose.family<QuarterlyGoal, String>(
  (ref, goalId) async {
    final api = ref.read(apiServiceProvider);
    final response = await api.get('/goals/$goalId');
    return QuarterlyGoal.fromJson(response.data as Map<String, dynamic>);
  },
);

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class GoalDetailScreen extends ConsumerWidget {
  const GoalDetailScreen({super.key, required this.goalId});

  final String goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goalAsync = ref.watch(_goalDetailProvider(goalId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
          color: AppColors.content,
        ),
        title: const Text('Goal detail'),
      ),
      body: goalAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.kiwi400),
        ),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 48,
                  color: AppColors.contentTertiary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Could not load goal.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.contentSecondary,
                      ),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => ref.invalidate(_goalDetailProvider(goalId)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (goal) => _GoalDetailBody(goal: goal),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body
// ---------------------------------------------------------------------------

class _GoalDetailBody extends StatelessWidget {
  const _GoalDetailBody({required this.goal});

  final QuarterlyGoal goal;

  int _weeksRemaining() {
    final now = DateTime.now();
    final diff = goal.endDate.difference(now).inDays;
    return (diff / 7).ceil().clamp(0, 999);
  }

  int _totalWeeks() {
    final diff = goal.endDate.difference(goal.startDate).inDays;
    return ((diff / 7).ceil()).clamp(1, 999);
  }

  String _quarterLabel() {
    final q = ((goal.startDate.month - 1) ~/ 3) + 1;
    return 'Q$q ${goal.startDate.year}';
  }

  List<_MonthBreakdown> _monthBreakdowns() {
    final months = <_MonthBreakdown>[];
    var cursor = DateTime(goal.startDate.year, goal.startDate.month, 1);
    final end = DateTime(goal.endDate.year, goal.endDate.month + 1, 1);
    while (cursor.isBefore(end)) {
      months.add(_MonthBreakdown(month: cursor));
      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }
    return months;
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d, yyyy');
    final weeksLeft = _weeksRemaining();
    final totalWeeks = _totalWeeks();
    final weeksElapsed = (totalWeeks - weeksLeft).clamp(0, totalWeeks);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quarter badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.kiwi100,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _quarterLabel(),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppColors.kiwi700,
                  ),
            ),
          ),
          const SizedBox(height: 12),

          // Title
          Text(
            goal.title,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppColors.content,
                ),
          ),
          const SizedBox(height: 20),

          // Progress card
          KinwiiCard(
            color: AppColors.kiwi50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Progress',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: AppColors.kiwi600,
                          ),
                    ),
                    Text(
                      '${goal.progressPercent}%',
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: AppColors.kiwi600,
                              ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ProgressBar(percent: goal.progressPercent, height: 8),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Week $weeksElapsed of $totalWeeks',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.contentSecondary,
                          ),
                    ),
                    Text(
                      weeksLeft == 0
                          ? 'Goal ended'
                          : '$weeksLeft wk${weeksLeft == 1 ? '' : 's'} remaining',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.contentSecondary,
                          ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Dates card
          KinwiiCard(
            child: Row(
              children: [
                _InfoItem(
                  label: 'Start',
                  value: fmt.format(goal.startDate),
                ),
                const SizedBox(width: 1),
                Container(width: 1, height: 36, color: AppColors.borderSubtle),
                const SizedBox(width: 1),
                _InfoItem(
                  label: 'End',
                  value: fmt.format(goal.endDate),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Why it matters
          if (goal.why != null && goal.why!.isNotEmpty) ...[
            Text(
              'Why it matters',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.content,
                  ),
            ),
            const SizedBox(height: 8),
            KinwiiCard(
              child: Text(
                goal.why!,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.contentSecondary,
                      height: 1.6,
                    ),
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Monthly breakdown
          Text(
            'Monthly breakdown',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.content,
                ),
          ),
          const SizedBox(height: 8),
          ..._monthBreakdowns().map(
            (m) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _MonthBreakdownTile(breakdown: m, goal: goal),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Supporting widgets
// ---------------------------------------------------------------------------

class _InfoItem extends StatelessWidget {
  const _InfoItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.contentTertiary,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.content,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }
}

class _MonthBreakdown {
  const _MonthBreakdown({required this.month});

  final DateTime month;
}

class _MonthBreakdownTile extends StatelessWidget {
  const _MonthBreakdownTile({
    required this.breakdown,
    required this.goal,
  });

  final _MonthBreakdown breakdown;
  final QuarterlyGoal goal;

  String _status() {
    final now = DateTime.now();
    final monthEnd = DateTime(
      breakdown.month.year,
      breakdown.month.month + 1,
      0,
    );
    if (monthEnd.isBefore(now)) return 'Past';
    if (breakdown.month.month == now.month &&
        breakdown.month.year == now.year) {
      return 'Current';
    }
    return 'Upcoming';
  }

  @override
  Widget build(BuildContext context) {
    final monthName = DateFormat('MMMM yyyy').format(breakdown.month);
    final status = _status();
    final isCurrent = status == 'Current';

    return KinwiiCard(
      color: isCurrent ? AppColors.kiwi50 : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              monthName,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.content,
                    fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                  ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isCurrent
                  ? AppColors.kiwi100
                  : AppColors.borderSubtle,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              status,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isCurrent
                        ? AppColors.kiwi700
                        : AppColors.contentTertiary,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
