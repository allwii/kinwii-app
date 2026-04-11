// WeekScreen - "Is this week aligned?"
// Usage: Registered as /week route inside AppShell's ShellRoute.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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

final _previousWeekPlanProvider =
    FutureProvider.autoDispose<WeeklyPlan?>((ref) async {
  final api = ref.read(apiServiceProvider);
  try {
    final response = await api.get('/week/previous');
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

final _weekReflectionExistsProvider =
    FutureProvider.autoDispose.family<bool, String>((ref, planId) async {
  final api = ref.read(apiServiceProvider);
  try {
    await api.get('/reflection/$planId');
    return true;
  } catch (_) {
    return false;
  }
});

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
  int _weekOffset = 0; // 0 = current week, -1 = previous week
  bool _editingIntent = false;
  bool _suggestingIntent = false;
  final _intentController = TextEditingController();

  @override
  void dispose() {
    _intentController.dispose();
    super.dispose();
  }

  Future<void> _suggestIntent(WeeklyPlan plan) async {
    if (plan.quarterId == null) return;
    setState(() => _suggestingIntent = true);
    try {
      final api = ref.read(apiServiceProvider);
      String? previousPlanId;
      try {
        final prevResponse = await api.get('/week/previous');
        previousPlanId = prevResponse.data['id'] as String?;
      } catch (_) {}
      final response = await api.post('/ai/suggest-intent', data: {
        'goal_id': plan.quarterId,
        if (previousPlanId != null) 'previous_plan_id': previousPlanId,
      });
      final suggested = response.data['suggested_intent'] as String?;
      if (suggested != null && mounted) {
        _intentController.text = suggested;
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get suggestion.')),
        );
      }
    }
    if (mounted) setState(() => _suggestingIntent = false);
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

  void _showCreateWeekSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (_) => _CreateWeekSheet(
        onCreated: () {
          ref.invalidate(_currentWeekPlanProvider);
        },
      ),
    );
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

  void _goToPreviousWeek() {
    setState(() {
      _weekOffset--;
      _editingIntent = false;
    });
  }

  void _goToNextWeek() {
    setState(() {
      _weekOffset++;
      _editingIntent = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isCurrentWeek = _weekOffset == 0;
    final planAsync = isCurrentWeek
        ? ref.watch(_currentWeekPlanProvider)
        : ref.watch(_previousWeekPlanProvider);
    final aiState = ref.watch(_aiSuggestionsProvider);
    final monday = _startOfWeek(DateTime.now()).add(Duration(days: 7 * _weekOffset));
    final sunday = monday.add(const Duration(days: 6));

    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: planAsync.maybeWhen(
        data: (plan) {
          if (plan == null) return null;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                child: _WeeklyReflectionEntry(planId: plan.id),
              ),
            ],
          );
        },
        orElse: () => null,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.kiwi400,
          onRefresh: () async {
            if (isCurrentWeek) {
              ref.invalidate(_currentWeekPlanProvider);
            } else {
              ref.invalidate(_previousWeekPlanProvider);
            }
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Header with week navigation
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        color: _weekOffset > -1
                            ? AppColors.content
                            : AppColors.borderSubtle,
                        onPressed: _weekOffset > -1 ? _goToPreviousWeek : null,
                        tooltip: 'Previous week',
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              'Week of ${DateFormat('MMM d').format(monday)} – ${DateFormat('MMM d').format(sunday)}',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(color: AppColors.content),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isCurrentWeek
                                  ? 'Current week'
                                  : DateFormat('yyyy').format(monday),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: isCurrentWeek
                                        ? AppColors.kiwi600
                                        : AppColors.contentSecondary,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        color: _weekOffset < 0
                            ? AppColors.content
                            : AppColors.borderSubtle,
                        onPressed: _weekOffset < 0 ? _goToNextWeek : null,
                        tooltip: 'Next week',
                      ),
                    ],
                  ),
                ),
              ),

              // Intent card (read-only for past weeks)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: planAsync.when(
                    loading: () => const _IntentSkeleton(),
                    error: (_, __) => const _IntentSkeleton(),
                    data: (plan) => plan == null
                        ? _IntentEmpty(
                            onSetUp: () => _showCreateWeekSheet(context),
                          )
                        : isCurrentWeek
                            ? _IntentCard(
                                plan: plan,
                                isEditing: _editingIntent,
                                isSuggestingIntent: _suggestingIntent,
                                intentController: _intentController,
                                onEditTap: () {
                                  _intentController.text = plan.intent;
                                  setState(() => _editingIntent = true);
                                },
                                onSave: () => _saveIntent(plan),
                                onCancel: () =>
                                    setState(() => _editingIntent = false),
                                onSuggestIntent: () => _suggestIntent(plan),
                              )
                            : _IntentCardReadOnly(plan: plan),
                  ),
                ),
              ),

              // Day grid label
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                  child: Text(
                    isCurrentWeek ? 'This week' : 'Days',
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
                        ? _DayGrid(days: _weekDays(monday), tasks: const [])
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

              // AI align button (current week only)
              if (isCurrentWeek)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
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

              // Bottom spacing
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
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
    required this.isSuggestingIntent,
    required this.intentController,
    required this.onEditTap,
    required this.onSave,
    required this.onCancel,
    required this.onSuggestIntent,
  });

  final WeeklyPlan plan;
  final bool isEditing;
  final bool isSuggestingIntent;
  final TextEditingController intentController;
  final VoidCallback onEditTap;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final VoidCallback onSuggestIntent;

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
            if (plan.quarterId != null) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: isSuggestingIntent ? null : onSuggestIntent,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.kiwi300),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isSuggestingIntent)
                        const SizedBox(
                          height: 12,
                          width: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: AppColors.kiwi500,
                          ),
                        )
                      else
                        const Icon(
                          Icons.auto_awesome,
                          size: 14,
                          color: AppColors.kiwi500,
                        ),
                      const SizedBox(width: 5),
                      Text(
                        isSuggestingIntent
                            ? 'Suggesting…'
                            : 'Suggest intent',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.kiwi600,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
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
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (plan.progressPercent > 0) ...[
              const SizedBox(height: 10),
              ProgressBar(percent: plan.progressPercent),
              const SizedBox(height: 4),
              Text(
                '${plan.progressPercent}% complete',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.contentSecondary,
                    ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

// Read-only intent card for past weeks
class _IntentCardReadOnly extends StatelessWidget {
  const _IntentCardReadOnly({required this.plan});

  final WeeklyPlan plan;

  @override
  Widget build(BuildContext context) {
    return KinwiiCard(
      color: AppColors.kiwi50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Weekly intent',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.kiwi600,
                  letterSpacing: 0.4,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            plan.intent,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.content,
                  fontWeight: FontWeight.w500,
                ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (plan.progressPercent > 0) ...[
            const SizedBox(height: 10),
            ProgressBar(percent: plan.progressPercent),
            const SizedBox(height: 4),
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

  void _showDaySheet(
    BuildContext context,
    DateTime day,
    List<Task> dayTasks,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (_) => _DayTasksSheet(day: day, tasks: dayTasks),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(_weekTasksProvider(plan.id));
    return tasksAsync.when(
      loading: () => _DayGrid(days: days, tasks: const []),
      error: (_, __) => _DayGrid(days: days, tasks: const []),
      data: (tasks) => _DayGrid(
        days: days,
        tasks: tasks,
        onDayTap: (day, dayTasks) => _showDaySheet(context, day, dayTasks),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 7-day grid
// ---------------------------------------------------------------------------

enum _DayStatus { allDone, partial, hasTasks, empty, today, future }

class _DayGrid extends StatelessWidget {
  const _DayGrid({
    required this.days,
    required this.tasks,
    this.onDayTap,
  });

  final List<DateTime> days;
  final List<Task> tasks;
  final void Function(DateTime day, List<Task> dayTasks)? onDayTap;

  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  _DayStatus _statusFor(DateTime day, List<Task> dayTasks, DateTime todayDate) {
    final isPast = day.isBefore(todayDate);
    final isToday = day.year == todayDate.year &&
        day.month == todayDate.month &&
        day.day == todayDate.day;
    if (isToday) return _DayStatus.today;
    if (!isPast) return _DayStatus.future;
    if (dayTasks.isEmpty) return _DayStatus.empty;
    if (dayTasks.every((t) => t.completed)) return _DayStatus.allDone;
    if (dayTasks.any((t) => t.completed)) return _DayStatus.partial;
    return _DayStatus.hasTasks;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);

    return Row(
      children: List.generate(days.length, (i) {
        final day = days[i];
        final dayTasks = tasks.where((t) {
          return t.date.year == day.year &&
              t.date.month == day.month &&
              t.date.day == day.day;
        }).toList();
        final completed = dayTasks.where((t) => t.completed).length;
        final total = dayTasks.length;
        final status = _statusFor(day, dayTasks, todayDate);

        // Colors per status
        final bgColor = switch (status) {
          _DayStatus.allDone  => const Color(0xFFECFCF0),
          _DayStatus.partial  => const Color(0xFFFFF8ED),
          _DayStatus.today    => AppColors.kiwi50,
          _DayStatus.hasTasks => Colors.white,
          _DayStatus.empty    => Colors.white,
          _DayStatus.future   => Colors.white,
        };
        final borderColor = switch (status) {
          _DayStatus.allDone  => AppColors.kiwi300,
          _DayStatus.partial  => const Color(0xFFFBBF24),
          _DayStatus.today    => AppColors.kiwi400,
          _DayStatus.hasTasks => AppColors.borderSubtle,
          _DayStatus.empty    => AppColors.borderSubtle,
          _DayStatus.future   => AppColors.borderSubtle,
        };
        final borderWidth = switch (status) {
          _DayStatus.today    => 2.0,
          _DayStatus.allDone  => 1.5,
          _DayStatus.partial  => 1.5,
          _DayStatus.hasTasks => 1.0,
          _DayStatus.empty    => 1.0,
          _DayStatus.future   => 1.0,
        };
        final labelColor = switch (status) {
          _DayStatus.allDone  => AppColors.kiwi600,
          _DayStatus.partial  => const Color(0xFFD97706),
          _DayStatus.today    => AppColors.kiwi600,
          _DayStatus.hasTasks => AppColors.contentTertiary,
          _DayStatus.empty    => AppColors.contentTertiary,
          _DayStatus.future   => AppColors.contentTertiary,
        };
        final dateColor = switch (status) {
          _DayStatus.allDone  => AppColors.kiwi700,
          _DayStatus.partial  => const Color(0xFF92400E),
          _DayStatus.today    => AppColors.kiwi700,
          _DayStatus.hasTasks => AppColors.contentSecondary,
          _DayStatus.empty    => AppColors.contentTertiary,
          _DayStatus.future   => AppColors.contentTertiary,
        };

        Widget indicator;
        switch (status) {
          case _DayStatus.allDone:
            indicator = const Icon(
              Icons.check_circle_rounded,
              size: 14,
              color: AppColors.kiwi400,
            );
          case _DayStatus.partial:
            indicator = Text(
              '$completed/$total',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: const Color(0xFFD97706),
                    fontWeight: FontWeight.w600,
                    fontSize: 9,
                  ),
            );
          case _DayStatus.hasTasks:
            indicator = Wrap(
              alignment: WrapAlignment.center,
              spacing: 2,
              children: List.generate(total.clamp(0, 4), (_) => Container(
                width: 4,
                height: 4,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.borderSubtle,
                ),
              )),
            );
          case _DayStatus.today:
            if (total > 0) {
              indicator = Wrap(
                alignment: WrapAlignment.center,
                spacing: 2,
                children: List.generate(total.clamp(0, 4), (j) => Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: j < completed
                        ? AppColors.kiwi400
                        : AppColors.borderSubtle,
                  ),
                )),
              );
            } else {
              indicator = const SizedBox(height: 14);
            }
          case _DayStatus.empty:
          case _DayStatus.future:
            indicator = const SizedBox(height: 14);
        }

        return Expanded(
          child: GestureDetector(
            onTap: onDayTap != null ? () => onDayTap!(day, dayTasks) : null,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: borderWidth),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _dayLabels[i],
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: labelColor,
                          fontWeight: status == _DayStatus.today || status == _DayStatus.allDone
                              ? FontWeight.w700
                              : FontWeight.w400,
                          fontSize: 11,
                        ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${day.day}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: dateColor,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 5),
                  SizedBox(height: 14, child: Center(child: indicator)),
                ],
              ),
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

// ---------------------------------------------------------------------------
// Empty state for when no weekly plan exists
// ---------------------------------------------------------------------------

class _IntentEmpty extends StatelessWidget {
  const _IntentEmpty({required this.onSetUp});

  final VoidCallback onSetUp;

  @override
  Widget build(BuildContext context) {
    return KinwiiCard(
      color: AppColors.kiwi50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Weekly intent',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.kiwi600,
                  letterSpacing: 0.4,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            "You haven't set up this week yet.",
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.contentSecondary,
                ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onSetUp,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Set up this week'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Create week bottom sheet
// ---------------------------------------------------------------------------

class _CreateWeekSheet extends ConsumerStatefulWidget {
  const _CreateWeekSheet({required this.onCreated});

  final VoidCallback onCreated;

  @override
  ConsumerState<_CreateWeekSheet> createState() => _CreateWeekSheetState();
}

class _CreateWeekSheetState extends ConsumerState<_CreateWeekSheet> {
  final _intentController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _intentController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final intent = _intentController.text.trim();
    if (intent.isEmpty) return;

    setState(() => _isSaving = true);
    try {
      final api = ref.read(apiServiceProvider);
      final now = DateTime.now();
      final weekday = now.weekday;
      final monday = DateTime(now.year, now.month, now.day - (weekday - 1));

      await api.post('/week', data: {
        'week_start_date': DateFormat('yyyy-MM-dd').format(monday),
        'intent': intent,
      });

      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onCreated();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not create week. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Set up this week',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(color: AppColors.content),
          ),
          const SizedBox(height: 8),
          Text(
            'What do you want to achieve this week?',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.contentSecondary),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _intentController,
            autofocus: true,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'e.g. Ship the onboarding flow',
              hintStyle: TextStyle(color: AppColors.contentTertiary),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Start this week'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Day tasks bottom sheet
// ---------------------------------------------------------------------------

class _DayTasksSheet extends StatelessWidget {
  const _DayTasksSheet({required this.day, required this.tasks});

  final DateTime day;
  final List<Task> tasks;

  @override
  Widget build(BuildContext context) {
    final dayLabel = DateFormat('EEEE, MMM d').format(day);
    final completed = tasks.where((t) => t.completed).length;

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.35,
      maxChildSize: 0.85,
      expand: false,
      builder: (_, scrollController) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.borderSubtle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              dayLabel,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.content,
                  ),
            ),
            if (tasks.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '$completed / ${tasks.length} completed',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.contentSecondary,
                    ),
              ),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: tasks.isEmpty
                  ? Center(
                      child: Text(
                        'No tasks for this day.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.contentTertiary,
                            ),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      itemCount: tasks.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final task = tasks[i];
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.borderSubtle),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                task.completed
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                size: 20,
                                color: task.completed
                                    ? AppColors.kiwi400
                                    : AppColors.borderSubtle,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  task.title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: task.completed
                                            ? AppColors.contentTertiary
                                            : AppColors.content,
                                        decoration: task.completed
                                            ? TextDecoration.lineThrough
                                            : null,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Weekly reflection entry point (shown at bottom of Week screen)
// ---------------------------------------------------------------------------

class _WeeklyReflectionEntry extends ConsumerWidget {
  const _WeeklyReflectionEntry({required this.planId});

  final String planId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reflectionAsync = ref.watch(_weekReflectionExistsProvider(planId));

    return reflectionAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (exists) {
        if (exists) {
          return KinwiiCard(
            onTap: () => context.push('/reflect/review/$planId'),
            child: Row(
              children: [
                const Icon(Icons.check_circle,
                    size: 20, color: AppColors.kiwi500),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Weekly reflection complete',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.content,
                        ),
                  ),
                ),
                const Icon(Icons.chevron_right,
                    size: 20, color: AppColors.contentTertiary),
              ],
            ),
          );
        }
        return KinwiiCard(
          onTap: () => context.push('/reflect/review/$planId'),
          color: AppColors.kiwi50,
          child: Row(
            children: [
              const Icon(Icons.auto_awesome_outlined,
                  size: 20, color: AppColors.kiwi600),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Start weekly review',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.content,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    Text(
                      'Reflect on your week and plan ahead.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.contentSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  size: 20, color: AppColors.kiwi500),
            ],
          ),
        );
      },
    );
  }
}
