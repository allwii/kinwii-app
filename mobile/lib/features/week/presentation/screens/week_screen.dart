// WeekScreen - "Is this week aligned?"
// Usage: Registered as /week route inside AppShell's ShellRoute.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/kinwii_card.dart';
import '../../../../core/widgets/progress_bar.dart';
import '../../../../models/task.dart';
import '../../../../models/weekly_plan.dart';
import '../../../../features/auth/presentation/screens/login_screen.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final _currentWeekPlanProvider =
    FutureProvider.autoDispose<WeeklyPlan?>((ref) async {
  final api = ref.read(apiServiceProvider);
  try {
    final response = await api.get('/week/current');
    if (response.data == null) return null;
    return WeeklyPlan.fromJson(response.data as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
});

final _weekTasksProvider =
    FutureProvider.autoDispose.family<List<Task>, String>(
  (ref, weeklyPlanId) async {
    final api = ref.read(apiServiceProvider);
    try {
      final response = await api.get(
        '/tasks',
        queryParameters: {'weekly_plan_id': weeklyPlanId},
      );
      return (response.data as List<dynamic>)
          .map((e) => Task.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  },
);

final _aiSuggestionsProvider =
    StateNotifierProvider.autoDispose<_AiSuggestionsNotifier, _AiState>(
  (ref) => _AiSuggestionsNotifier(ref),
);

class _AiState {
  const _AiState({
    this.isLoading = false,
    this.suggestions = const [],
    this.error,
  });

  final bool isLoading;
  final List<String> suggestions;
  final String? error;
}

class _AiSuggestionsNotifier extends StateNotifier<_AiState> {
  _AiSuggestionsNotifier(this._ref) : super(const _AiState());

  final Ref _ref;

  Future<void> align(String weeklyPlanId) async {
    state = const _AiState(isLoading: true);
    try {
      final api = _ref.read(apiServiceProvider);
      final response = await api.post(
        '/ai/align-week',
        data: {'weekly_plan_id': weeklyPlanId},
      );
      final raw = response.data['suggestions'] as List<dynamic>;
      state = _AiState(suggestions: raw.cast<String>());
    } catch (_) {
      state = const _AiState(error: 'Could not get suggestions. Try again.');
    }
  }

  void reset() => state = const _AiState();
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

DateTime _startOfWeek(DateTime date) {
  // Monday-based week
  final weekday = date.weekday; // 1=Mon ... 7=Sun
  return DateTime(date.year, date.month, date.day - (weekday - 1));
}

List<DateTime> _weekDays(DateTime monday) =>
    List.generate(7, (i) => monday.add(Duration(days: i)));

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class WeekScreen extends ConsumerStatefulWidget {
  const WeekScreen({super.key});

  @override
  ConsumerState<WeekScreen> createState() => _WeekScreenState();
}

class _WeekScreenState extends ConsumerState<WeekScreen> {
  bool _editingIntent = false;
  final _intentController = TextEditingController();

  @override
  void dispose() {
    _intentController.dispose();
    super.dispose();
  }

  Future<void> _saveIntent(WeeklyPlan plan) async {
    final newIntent = _intentController.text.trim();
    if (newIntent.isEmpty || newIntent == plan.intent) {
      setState(() => _editingIntent = false);
      return;
    }
    try {
      final api = ref.read(apiServiceProvider);
      await api.put('/week/${plan.id}', data: {'intent': newIntent});
      ref.invalidate(_currentWeekPlanProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save intent.')),
        );
      }
    }
    if (mounted) setState(() => _editingIntent = false);
  }

  void _showAiSheet(BuildContext context, List<String> suggestions) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (_) => _AiAlignSheet(suggestions: suggestions),
    );
  }

  @override
  Widget build(BuildContext context) {
    final planAsync = ref.watch(_currentWeekPlanProvider);
    final aiState = ref.watch(_aiSuggestionsProvider);
    final monday = _startOfWeek(DateTime.now());
    final sunday = monday.add(const Duration(days: 6));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.kiwi400,
          onRefresh: () async => ref.invalidate(_currentWeekPlanProvider),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Week of ${DateFormat('MMM d').format(monday)} – ${DateFormat('MMM d').format(sunday)}',
                        style:
                            Theme.of(context).textTheme.headlineLarge?.copyWith(
                                  color: AppColors.content,
                                ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('yyyy').format(monday),
                        style:
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: AppColors.contentSecondary,
                                ),
                      ),
                    ],
                  ),
                ),
              ),

              // Intent card
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: planAsync.when(
                    loading: () => const _IntentSkeleton(),
                    error: (_, __) => const _IntentSkeleton(),
                    data: (plan) => plan == null
                        ? const _IntentSkeleton()
                        : _IntentCard(
                            plan: plan,
                            isEditing: _editingIntent,
                            intentController: _intentController,
                            onEditTap: () {
                              _intentController.text = plan.intent;
                              setState(() => _editingIntent = true);
                            },
                            onSave: () => _saveIntent(plan),
                            onCancel: () =>
                                setState(() => _editingIntent = false),
                          ),
                  ),
                ),
              ),

              // 7-day grid label
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                  child: Text(
                    'This week',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.content,
                        ),
                  ),
                ),
              ),

              // 7-day grid
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: planAsync.maybeWhen(
                    data: (plan) => plan == null
                        ? const _DayGrid(days: [], tasks: [])
                        : _WeekGridLoader(
                            plan: plan,
                            days: _weekDays(monday),
                          ),
                    orElse: () => _DayGrid(
                      days: _weekDays(monday),
                      tasks: const [],
                    ),
                  ),
                ),
              ),

              // AI align button
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                  child: planAsync.maybeWhen(
                    data: (plan) => plan == null
                        ? const SizedBox.shrink()
                        : SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: aiState.isLoading
                                  ? null
                                  : () async {
                                      final notifier = ref.read(
                                        _aiSuggestionsProvider.notifier,
                                      );
                                      // Capture before async gap
                                      final messenger =
                                          ScaffoldMessenger.of(context);
                                      final capturedContext = context;
                                      await notifier.align(plan.id);
                                      final updated =
                                          ref.read(_aiSuggestionsProvider);
                                      if (!mounted) return;
                                      if (updated.suggestions.isNotEmpty) {
                                        _showAiSheet(
                                          capturedContext,
                                          updated.suggestions,
                                        );
                                        ref
                                            .read(
                                              _aiSuggestionsProvider.notifier,
                                            )
                                            .reset();
                                      } else if (updated.error != null) {
                                        messenger.showSnackBar(
                                          SnackBar(
                                            content: Text(updated.error!),
                                          ),
                                        );
                                      }
                                    },
                              icon: aiState.isLoading
                                  ? const SizedBox(
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.auto_awesome_outlined,
                                      size: 18,
                                    ),
                              label: Text(
                                aiState.isLoading
                                    ? 'Aligning…'
                                    : 'AI Align this week',
                              ),
                            ),
                          ),
                    orElse: () => const SizedBox.shrink(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Intent card with inline edit
// ---------------------------------------------------------------------------

class _IntentCard extends StatelessWidget {
  const _IntentCard({
    required this.plan,
    required this.isEditing,
    required this.intentController,
    required this.onEditTap,
    required this.onSave,
    required this.onCancel,
  });

  final WeeklyPlan plan;
  final bool isEditing;
  final TextEditingController intentController;
  final VoidCallback onEditTap;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return KinwiiCard(
      color: AppColors.kiwi50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Weekly intent',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppColors.kiwi600,
                      letterSpacing: 0.4,
                    ),
              ),
              const Spacer(),
              if (!isEditing)
                GestureDetector(
                  onTap: onEditTap,
                  child: const Icon(
                    Icons.edit_outlined,
                    size: 16,
                    color: AppColors.kiwi500,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (isEditing) ...[
            TextField(
              controller: intentController,
              autofocus: true,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'What do you want to achieve this week?',
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onCancel,
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: onSave,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                  child: const Text('Save'),
                ),
              ],
            ),
          ] else ...[
            Text(
              plan.intent,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.content,
                    fontWeight: FontWeight.w500,
                  ),
            ),
            const SizedBox(height: 12),
            ProgressBar(percent: plan.progressPercent),
            const SizedBox(height: 6),
            Text(
              '${plan.progressPercent}% complete',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.contentSecondary,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _IntentSkeleton extends StatelessWidget {
  const _IntentSkeleton();

  @override
  Widget build(BuildContext context) {
    return KinwiiCard(
      color: AppColors.kiwi50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 12,
            width: 80,
            decoration: BoxDecoration(
              color: AppColors.borderSubtle,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 16,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.borderSubtle,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 12),
          const ProgressBar(percent: 0),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Week grid loader (fetches tasks then renders grid)
// ---------------------------------------------------------------------------

class _WeekGridLoader extends ConsumerWidget {
  const _WeekGridLoader({required this.plan, required this.days});

  final WeeklyPlan plan;
  final List<DateTime> days;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(_weekTasksProvider(plan.id));
    return tasksAsync.when(
      loading: () => _DayGrid(days: days, tasks: const []),
      error: (_, __) => _DayGrid(days: days, tasks: const []),
      data: (tasks) => _DayGrid(days: days, tasks: tasks),
    );
  }
}

// ---------------------------------------------------------------------------
// 7-day grid
// ---------------------------------------------------------------------------

class _DayGrid extends StatelessWidget {
  const _DayGrid({required this.days, required this.tasks});

  final List<DateTime> days;
  final List<Task> tasks;

  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return Row(
      children: List.generate(days.length, (i) {
        final day = days[i];
        final isToday = day.year == today.year &&
            day.month == today.month &&
            day.day == today.day;
        final dayTasks = tasks.where((t) {
          return t.date.year == day.year &&
              t.date.month == day.month &&
              t.date.day == day.day;
        }).toList();
        final completed = dayTasks.where((t) => t.completed).length;
        final total = dayTasks.length;

        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: isToday ? AppColors.kiwi50 : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: isToday
                  ? Border.all(color: AppColors.kiwi300, width: 1.5)
                  : Border.all(color: AppColors.borderSubtle),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _dayLabels[i],
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isToday
                            ? AppColors.kiwi600
                            : AppColors.contentTertiary,
                        fontWeight: isToday
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${day.day}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isToday
                            ? AppColors.kiwi700
                            : AppColors.contentSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 6),
                // Task dots
                if (total > 0)
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 2,
                    runSpacing: 2,
                    children: List.generate(total.clamp(0, 4), (j) {
                      final isDone = j < completed;
                      return Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDone
                              ? AppColors.kiwi400
                              : AppColors.borderSubtle,
                        ),
                      );
                    }),
                  )
                else
                  Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.transparent,
                    ),
                  ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// AI align bottom sheet
// ---------------------------------------------------------------------------

class _AiAlignSheet extends StatelessWidget {
  const _AiAlignSheet({required this.suggestions});

  final List<String> suggestions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome,
                color: AppColors.kiwi500,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'AI suggestions',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Here are up to 3 ways to better align this week.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.contentSecondary,
                ),
          ),
          const SizedBox(height: 16),
          ...suggestions.take(3).map(
                (s) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: KinwiiCard(
                    color: AppColors.kiwi50,
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 3),
                          child: Icon(
                            Icons.lightbulb_outline,
                            size: 16,
                            color: AppColors.kiwi500,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            s,
                            style:
                                Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: AppColors.content,
                                    ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Dismiss'),
            ),
          ),
        ],
      ),
    );
  }
}
