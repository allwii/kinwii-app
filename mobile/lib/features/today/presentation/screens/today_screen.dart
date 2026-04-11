// TodayScreen - "What should I focus on right now?"
// Simplified: task list + AI suggestions + daily reflection (evening).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/kinwii_card.dart';
import '../../../../models/quarterly_goal.dart';
import '../../../../models/task.dart';
import '../../../../models/weekly_plan.dart';
import '../../../../features/auth/presentation/screens/login_screen.dart';
import '../../../../main.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final _weeklyPlanProvider =
    FutureProvider.autoDispose<WeeklyPlan?>((ref) async {
  final api = ref.read(apiServiceProvider);
  final cache = ref.read(cacheServiceProvider);

  final cached = cache.get('today_weekly_plan');
  if (cached != null && cache.isFresh('today_weekly_plan')) {
    _fetchAndCacheWeeklyPlan(api, cache);
    return WeeklyPlan.fromJson(cached as Map<String, dynamic>);
  }

  try {
    final plan = await _fetchAndCacheWeeklyPlan(api, cache);
    return plan;
  } catch (_) {
    if (cached != null) {
      return WeeklyPlan.fromJson(cached as Map<String, dynamic>);
    }
    return null;
  }
});

Future<WeeklyPlan?> _fetchAndCacheWeeklyPlan(
    dynamic api, dynamic cache) async {
  final response = await api.get('/week/current');
  if (response.data == null) return null;
  await cache.put('today_weekly_plan', response.data, ttlMinutes: 15);
  return WeeklyPlan.fromJson(response.data as Map<String, dynamic>);
}

final _todayTasksProvider =
    StateNotifierProvider.autoDispose<_TasksNotifier, AsyncValue<List<Task>>>(
  (ref) => _TasksNotifier(ref),
);

class _TasksNotifier extends StateNotifier<AsyncValue<List<Task>>> {
  _TasksNotifier(this._ref) : super(const AsyncValue.loading()) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    final cache = _ref.read(cacheServiceProvider);
    final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final cacheKey = 'today_tasks_$dateStr';

    final cached = cache.get(cacheKey);
    if (cached != null) {
      final list = (cached as List<dynamic>)
          .map((e) => Task.fromJson(e as Map<String, dynamic>))
          .toList();
      state = AsyncValue.data(list);
    } else {
      state = const AsyncValue.loading();
    }

    try {
      final api = _ref.read(apiServiceProvider);
      final response =
          await api.get('/tasks', queryParameters: {'date': dateStr});
      await cache.put(cacheKey, response.data, ttlMinutes: 10);
      final list = (response.data as List<dynamic>)
          .map((e) => Task.fromJson(e as Map<String, dynamic>))
          .toList();
      state = AsyncValue.data(list);
    } catch (e, st) {
      if (cached == null) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<void> toggleComplete(String taskId) async {
    final current = state.valueOrNull;
    if (current == null) return;

    final idx = current.indexWhere((t) => t.id == taskId);
    if (idx == -1) return;
    final updated = current[idx].copyWith(completed: !current[idx].completed);
    final optimistic = List<Task>.from(current)..[idx] = updated;
    state = AsyncValue.data(optimistic);

    try {
      final api = _ref.read(apiServiceProvider);
      await api.patch('/tasks/$taskId/complete');
    } catch (_) {
      state = AsyncValue.data(current);
    }
  }

  Future<void> addTask({
    required String weeklyPlanId,
    required String title,
    required EnergyType energyType,
    String? description,
    String? time,
  }) async {
    try {
      final api = _ref.read(apiServiceProvider);
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final response = await api.post('/tasks', data: {
        'weekly_plan_id': weeklyPlanId,
        'title': title,
        'date': dateStr,
        'energy_type': energyType.name,
        if (description != null && description.isNotEmpty)
          'description': description,
        if (time != null) 'time': time,
      });
      final newTask = Task.fromJson(response.data as Map<String, dynamic>);
      final current = state.valueOrNull ?? [];
      state = AsyncValue.data([...current, newTask]);
    } catch (_) {
      rethrow;
    }
  }

  Future<void> updateTask(String taskId, Map<String, dynamic> fields) async {
    try {
      final api = _ref.read(apiServiceProvider);
      final response = await api.put('/tasks/$taskId', data: fields);
      final updatedTask =
          Task.fromJson(response.data as Map<String, dynamic>);
      final current = state.valueOrNull;
      if (current != null) {
        final idx = current.indexWhere((t) => t.id == taskId);
        if (idx != -1) {
          state = AsyncValue.data(List<Task>.from(current)..[idx] = updatedTask);
        }
      }
    } catch (_) {
      rethrow;
    }
  }

  Future<void> deleteTask(String taskId) async {
    final current = state.valueOrNull;
    if (current == null) return;
    // Optimistic removal
    state = AsyncValue.data(current.where((t) => t.id != taskId).toList());
    try {
      final api = _ref.read(apiServiceProvider);
      await api.delete('/tasks/$taskId');
    } catch (_) {
      state = AsyncValue.data(current); // revert
    }
  }

  Future<void> updateSkipReason(String taskId, String reason) async {
    try {
      final api = _ref.read(apiServiceProvider);
      await api.put('/tasks/$taskId', data: {'skip_reason': reason});
      final current = state.valueOrNull;
      if (current != null) {
        final idx = current.indexWhere((t) => t.id == taskId);
        if (idx != -1) {
          final updated = current[idx].copyWith(skipReason: reason);
          state = AsyncValue.data(List<Task>.from(current)..[idx] = updated);
        }
      }
    } catch (_) {
      // Silent fail
    }
  }

  Future<void> refresh() => _load();
}

// Goals provider — used in add task sheet for goal picker
final _goalsProvider =
    FutureProvider.autoDispose<List<QuarterlyGoal>>((ref) async {
  final api = ref.read(apiServiceProvider);
  try {
    final response = await api.get('/goals');
    return (response.data as List<dynamic>)
        .map((e) => QuarterlyGoal.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return [];
  }
});

// AI daily focus suggestions — stateful so we can remove items after use
final _dailyFocusProvider = StateNotifierProvider.family<
    _DailyFocusNotifier, AsyncValue<List<String>>, (String, String)>(
  (ref, key) => _DailyFocusNotifier(ref, key),
);

class _DailyFocusNotifier extends StateNotifier<AsyncValue<List<String>>> {
  _DailyFocusNotifier(this._ref, this._key)
      : super(const AsyncValue.loading()) {
    _load();
  }

  final Ref _ref;
  final (String, String) _key;

  Future<void> _load() async {
    final (weeklyPlanId, date) = _key;
    final api = _ref.read(apiServiceProvider);
    try {
      final response = await api.post('/ai/suggest-daily-focus', data: {
        'weekly_plan_id': weeklyPlanId,
        'date': date,
      });
      final data = response.data as Map<String, dynamic>;
      final suggestions =
          (data['suggestions'] as List<dynamic>?)?.cast<String>() ?? [];
      state = AsyncValue.data(suggestions);
    } catch (_) {
      state = const AsyncValue.data([]);
    }
  }

  void removeSuggestion(String suggestion) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(current.where((s) => s != suggestion).toList());
  }
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weeklyPlanAsync = ref.watch(_weeklyPlanProvider);
    final tasksAsync = ref.watch(_todayTasksProvider);
    final goals = ref.watch(_goalsProvider).valueOrNull ?? [];
    final today = DateTime.now();
    final isEvening = today.hour >= 17;

    // Build goal name lookup: weeklyPlan.quarterId → goal.title
    final plan = weeklyPlanAsync.valueOrNull;
    final goalMap = <String, String>{};
    for (final g in goals) {
      goalMap[g.id] = g.title;
    }
    String? goalNameForTask(Task task) {
      if (plan != null && plan.quarterId != null) {
        return goalMap[plan.quarterId];
      }
      return null;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.kiwi400,
          onRefresh: () async {
            ref.invalidate(_weeklyPlanProvider);
            await ref.read(_todayTasksProvider.notifier).refresh();
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Date header + coach icon
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 16, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          DateFormat('EEEE, MMM d').format(today),
                          style: Theme.of(context)
                              .textTheme
                              .headlineLarge
                              ?.copyWith(color: AppColors.content),
                        ),
                      ),
                      IconButton(
                        onPressed: () => context.push('/coach'),
                        icon: const Icon(
                          Icons.psychology,
                          color: AppColors.kiwi500,
                          size: 22,
                        ),
                        tooltip: 'Growth Coach',
                      ),
                    ],
                  ),
                ),
              ),

              // Section label + add button
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          "Today's focus",
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: AppColors.content,
                                  ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => _showAddTaskSheet(context, ref),
                        icon: const Icon(
                          Icons.add_circle_outline,
                          color: AppColors.kiwi500,
                          size: 24,
                        ),
                        tooltip: 'Add task',
                      ),
                    ],
                  ),
                ),
              ),

              // Task list
              tasksAsync.when(
                loading: () => const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Center(
                      child:
                          CircularProgressIndicator(color: AppColors.kiwi400),
                    ),
                  ),
                ),
                error: (_, __) => const SliverToBoxAdapter(
                  child: EmptyState(
                    message: 'Could not load tasks. Pull to refresh.',
                  ),
                ),
                data: (tasks) {
                  if (tasks.isEmpty) {
                    return const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 24),
                        child: EmptyState(
                          message: 'No tasks yet — add one to get started.',
                        ),
                      ),
                    );
                  }
                  return SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    sliver: SliverList.separated(
                      itemCount: tasks.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) => _TaskTile(
                        task: tasks[index],
                        goalName: goalNameForTask(tasks[index]),
                        onToggle: () => ref
                            .read(_todayTasksProvider.notifier)
                            .toggleComplete(tasks[index].id),
                        onTap: () => _showTaskDetail(
                            context, ref, tasks[index],
                            goalName: goalNameForTask(tasks[index])),
                      ),
                    ),
                  );
                },
              ),

              // AI suggested focus (below tasks)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: weeklyPlanAsync.maybeWhen(
                    data: (plan) => plan != null
                        ? _AiSuggestionsCard(
                            weeklyPlanId: plan.id,
                            onSuggestionTap: (title) {
                              final dateStr = DateFormat('yyyy-MM-dd')
                                  .format(DateTime.now());
                              ref
                                  .read(_dailyFocusProvider(
                                          (plan.id, dateStr))
                                      .notifier)
                                  .removeSuggestion(title);
                              _showAddTaskSheet(context, ref,
                                  initialTitle: title);
                            },
                          )
                        : const SizedBox.shrink(),
                    orElse: () => const SizedBox.shrink(),
                  ),
                ),
              ),

              // Daily reflection entry card (always visible, muted before 5 PM)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
                  child: tasksAsync.maybeWhen(
                    data: (tasks) => tasks.isNotEmpty
                        ? Opacity(
                            opacity: isEvening ? 1.0 : 0.5,
                            child: _DailyReflectionCard(tasks: tasks),
                          )
                        : const SizedBox.shrink(),
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

  void _showTaskDetail(BuildContext context, WidgetRef ref, Task task,
      {String? goalName}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _TaskDetailSheet(
        task: task,
        notifier: ref.read(_todayTasksProvider.notifier),
        goals: ref.read(_goalsProvider).valueOrNull ?? [],
        currentGoalName: goalName,
      ),
    );
  }

  void _showAddTaskSheet(BuildContext context, WidgetRef ref,
      {String? initialTitle}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AddTaskSheet(
        notifier: ref.read(_todayTasksProvider.notifier),
        initialTitle: initialTitle,
        onTaskAdded: () {
          ref.invalidate(_weeklyPlanProvider);
          ref.read(_todayTasksProvider.notifier).refresh();
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Task tile with description and time
// ---------------------------------------------------------------------------

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.task,
    required this.onToggle,
    this.onTap,
    this.goalName,
  });

  final Task task;
  final VoidCallback onToggle;
  final VoidCallback? onTap;
  final String? goalName;

  @override
  Widget build(BuildContext context) {
    final hasSecondRow = task.time != null || goalName != null;
    return KinwiiCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onToggle,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: task.completed ? AppColors.kiwi400 : Colors.white,
                border: Border.all(
                  color: task.completed
                      ? AppColors.kiwi400
                      : AppColors.borderSubtle,
                  width: 2,
                ),
              ),
              child: task.completed
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Text(
                  task.title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: task.completed
                            ? AppColors.contentTertiary
                            : AppColors.content,
                        decoration: task.completed
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                ),
                // Description
                if (task.description != null &&
                    task.description!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    task.description!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.contentSecondary,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                // Bottom row: time (left) + energy chip (right)
                if (hasSecondRow) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (task.time != null) ...[
                        const Icon(Icons.schedule,
                            size: 12, color: AppColors.contentTertiary),
                        const SizedBox(width: 3),
                        Text(
                          _formatTime(task.time!),
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                color: AppColors.contentTertiary,
                                fontSize: 11,
                              ),
                        ),
                      ],
                      if (goalName != null) ...[
                        const Spacer(),
                        const Icon(Icons.flag_outlined,
                            size: 12, color: AppColors.contentTertiary),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            goalName!,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: AppColors.contentTertiary,
                                  fontSize: 11,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(String timeStr) {
    try {
      final parts = timeStr.split(':');
      final hour = int.parse(parts[0]);
      final min = int.parse(parts[1]);
      final t = TimeOfDay(hour: hour, minute: min);
      final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
      final m = t.minute.toString().padLeft(2, '0');
      final p = t.period == DayPeriod.am ? 'AM' : 'PM';
      return '$h:$m $p';
    } catch (_) {
      return timeStr;
    }
  }
}

// ---------------------------------------------------------------------------
// AI suggestions card (tappable to create tasks)
// ---------------------------------------------------------------------------

class _AiSuggestionsCard extends ConsumerWidget {
  const _AiSuggestionsCard({
    required this.weeklyPlanId,
    required this.onSuggestionTap,
  });

  final String weeklyPlanId;
  final void Function(String title) onSuggestionTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final suggestionsAsync =
        ref.watch(_dailyFocusProvider((weeklyPlanId, dateStr)));

    return suggestionsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (suggestions) {
        if (suggestions.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome,
                    size: 16, color: AppColors.kiwi500),
                const SizedBox(width: 6),
                Text(
                  'AI suggested focus',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppColors.kiwi600,
                        letterSpacing: 0.4,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...suggestions.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: InkWell(
                    onTap: () => onSuggestionTap(s),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.kiwi50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.add_circle_outline,
                              size: 16, color: AppColors.kiwi500),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              s,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.kiwi700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Add task sheet (with description + time)
// ---------------------------------------------------------------------------

class _AddTaskSheet extends ConsumerStatefulWidget {
  const _AddTaskSheet({
    required this.notifier,
    this.initialTitle,
    this.onTaskAdded,
  });

  final _TasksNotifier notifier;
  final String? initialTitle;
  final VoidCallback? onTaskAdded;

  @override
  ConsumerState<_AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends ConsumerState<_AddTaskSheet> {
  late final TextEditingController _titleCtrl;
  final _descCtrl = TextEditingController();
  EnergyType _energy = EnergyType.deep;
  TimeOfDay? _time;
  bool _loading = false;
  bool _showDetails = false;
  String? _selectedGoalId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.initialTitle ?? '');
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  /// Resolve the weekly plan for a goal. If none exists for this week,
  /// auto-create one with intent derived from the goal title.
  Future<String> _resolveWeeklyPlanId(String goalId, String goalTitle) async {
    final api = ref.read(apiServiceProvider);

    // Check if current week plan already exists
    try {
      final response = await api.get('/week/current');
      if (response.data != null) {
        return response.data['id'] as String;
      }
    } catch (_) {
      // 404 — no plan exists, create one
    }

    // Auto-create weekly plan linked to this goal
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final mondayStr = DateFormat('yyyy-MM-dd').format(monday);

    final response = await api.post('/week', data: {
      'week_start_date': mondayStr,
      'intent': 'Focus on: $goalTitle',
      'quarter_id': goalId,
    });
    return response.data['id'] as String;
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    if (_selectedGoalId == null) {
      setState(() => _error = 'Please select a goal.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Find goal title for auto-creating weekly plan
      final goals = ref.read(_goalsProvider).valueOrNull ?? [];
      final goal = goals.firstWhere((g) => g.id == _selectedGoalId);
      final planId = await _resolveWeeklyPlanId(goal.id, goal.title);

      String? timeStr;
      if (_time != null) {
        timeStr =
            '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}:00';
      }
      await widget.notifier.addTask(
        weeklyPlanId: planId,
        title: title,
        energyType: _energy,
        description:
            _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        time: timeStr,
      );
      widget.onTaskAdded?.call();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Failed to add task. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final goalsAsync = ref.watch(_goalsProvider);
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    // Auto-select goal if only one exists
    goalsAsync.whenData((goals) {
      if (_selectedGoalId == null && goals.length == 1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _selectedGoalId == null) {
            setState(() => _selectedGoalId = goals.first.id);
          }
        });
      }
    });

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add task', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),

          // Task title
          TextField(
            controller: _titleCtrl,
            autofocus: widget.initialTitle == null,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Task',
              hintText: 'What do you need to do?',
            ),
          ),
          const SizedBox(height: 12),

          // Goal picker
          goalsAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (goals) {
              if (goals.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Create a goal first to start adding tasks.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.contentTertiary,
                        ),
                  ),
                );
              }
              if (goals.length == 1) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.flag, size: 16, color: AppColors.kiwi500),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          goals.first.title,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.kiwi600,
                                    fontWeight: FontWeight.w500,
                                  ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }
              // Multiple goals — show dropdown
              return DropdownButtonFormField<String>(
                initialValue: _selectedGoalId,
                decoration: const InputDecoration(
                  labelText: 'Goal',
                  isDense: true,
                ),
                items: goals
                    .map((g) => DropdownMenuItem(
                          value: g.id,
                          child: Text(
                            g.title,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedGoalId = v),
              );
            },
          ),
          const SizedBox(height: 4),

          // "Add details" toggle
          if (!_showDetails)
            GestureDetector(
              onTap: () => setState(() => _showDetails = true),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.tune,
                        size: 14, color: AppColors.contentTertiary),
                    const SizedBox(width: 4),
                    Text(
                      'Add details',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.contentTertiary,
                          ),
                    ),
                  ],
                ),
              ),
            ),

          // Expanded details
          if (_showDetails) ...[
            TextField(
              controller: _descCtrl,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
              minLines: 1,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Details or expected outcome',
              ),
            ),
            const SizedBox(height: 12),
            // Time picker
            GestureDetector(
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: _time ?? TimeOfDay.now(),
                );
                if (picked != null) setState(() => _time = picked);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.schedule,
                        size: 18, color: AppColors.contentSecondary),
                    const SizedBox(width: 8),
                    Text(
                      _time != null
                          ? _formatTimeOfDay(_time!)
                          : 'Set time',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: _time != null
                                ? AppColors.content
                                : AppColors.contentTertiary,
                          ),
                    ),
                    if (_time != null) ...[
                      const Spacer(),
                      GestureDetector(
                        onTap: () => setState(() => _time = null),
                        child: const Icon(Icons.close,
                            size: 16, color: AppColors.contentTertiary),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Energy type chips
            Wrap(
              spacing: 8,
              children: EnergyType.values.map((e) {
                final selected = e == _energy;
                return ChoiceChip(
                  label: Text(e.name),
                  selected: selected,
                  selectedColor: AppColors.kiwi100,
                  onSelected: (_) => setState(() => _energy = e),
                );
              }).toList(),
            ),
          ],

          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: const TextStyle(color: Colors.red, fontSize: 13)),
          ],

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Add'),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimeOfDay(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final p = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $p';
  }
}

// ---------------------------------------------------------------------------
// Task detail sheet — redesigned per Todoist-style layout
// ---------------------------------------------------------------------------

class _TaskDetailSheet extends StatefulWidget {
  const _TaskDetailSheet({
    required this.task,
    required this.notifier,
    required this.goals,
    this.currentGoalName,
  });

  final Task task;
  final _TasksNotifier notifier;
  final List<QuarterlyGoal> goals;
  final String? currentGoalName;

  @override
  State<_TaskDetailSheet> createState() => _TaskDetailSheetState();
}

class _TaskDetailSheetState extends State<_TaskDetailSheet> {
  late TextEditingController _titleCtrl;
  late TextEditingController _descCtrl;
  late DateTime _date;
  late String? _selectedGoalName;
  TimeOfDay? _time;
  bool _saving = false;
  bool _dirty = false;
  bool _descFullView = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.task.title);
    _descCtrl = TextEditingController(text: widget.task.description ?? '');
    _selectedGoalName = widget.currentGoalName;
    _date = widget.task.date;
    if (widget.task.time != null) {
      try {
        final parts = widget.task.time!.split(':');
        _time = TimeOfDay(
            hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  bool get _isOverdue {
    if (_time == null) return false;
    final now = DateTime.now();
    final taskDateTime = DateTime(
        _date.year, _date.month, _date.day, _time!.hour, _time!.minute);
    return taskDateTime.isBefore(now) && !widget.task.completed;
  }

  String get _dateTimeLabel {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final taskDay = DateTime(_date.year, _date.month, _date.day);
    final diff = taskDay.difference(today).inDays;

    String dayPart;
    if (diff == 0) {
      dayPart = 'Today';
    } else if (diff == 1) {
      dayPart = 'Tomorrow';
    } else if (diff == -1) {
      dayPart = 'Yesterday';
    } else {
      dayPart = DateFormat('EEE, MMM d').format(_date);
    }

    if (_time != null) {
      return '$dayPart, ${_formatTimeOfDay(_time!)}';
    }
    return dayPart;
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    setState(() => _saving = true);

    String? timeStr;
    if (_time != null) {
      timeStr =
          '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}:00';
    }

    try {
      await widget.notifier.updateTask(widget.task.id, {
        'title': title,
        'description':
            _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        'date': DateFormat('yyyy-MM-dd').format(_date),
        if (timeStr != null) 'time': timeStr,
      });
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    await widget.notifier.deleteTask(widget.task.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickDateTime() async {
    // Pick date first
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.kiwi400),
        ),
        child: child!,
      ),
    );
    if (pickedDate == null || !mounted) return;

    // Then pick time
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: _time ?? TimeOfDay.now(),
    );

    setState(() {
      _date = pickedDate;
      if (pickedTime != null) _time = pickedTime;
      _dirty = true;
    });
  }

  String _formatTimeOfDay(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final p = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $p';
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    // Full-view: expand to full screen when editing description
    if (_descFullView) {
      return SizedBox(
        height: screenHeight * 0.92,
        child: _buildFullView(context, bottomPadding),
      );
    }

    // Compact view: 60% height
    return SizedBox(
      height: screenHeight * 0.6,
      child: _buildCompactView(context, bottomPadding),
    );
  }

  Widget _buildFullView(BuildContext context, double bottomPadding) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 16 + bottomPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Same top section as compact view
          _buildTopSection(context),

          const SizedBox(height: 16),

          // Title (read-only in full view)
          Text(
            _titleCtrl.text,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.content,
                  fontWeight: FontWeight.w600,
                ),
          ),

          const SizedBox(height: 12),

          // Description: editable, fills remaining space
          Expanded(
            child: TextField(
              controller: _descCtrl,
              autofocus: true,
              expands: true,
              maxLines: null,
              textAlignVertical: TextAlignVertical.top,
              textCapitalization: TextCapitalization.sentences,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.content,
                    height: 1.6,
                  ),
              decoration: InputDecoration(
                hintText: 'Add details, outcomes, or notes...',
                hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.contentTertiary,
                    ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (_) => _markDirty(),
            ),
          ),

          // Done button
          SafeArea(
            child: Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: () {
                    if (_dirty) _save();
                    setState(() => _descFullView = false);
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.all(8),
                    minimumSize: Size.zero,
                  ),
                  child: const Icon(
                    Icons.check,
                    color: AppColors.kiwi500,
                    size: 24,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Top section shared between compact and full views:
  /// Row 1 = energy chip + menu, Row 2 = checkmark + date/time
  Widget _buildTopSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Row 1: Goal chip + more menu
        Row(
          children: [
            GestureDetector(
              onTap: _showGoalPicker,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.kiwi50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.flag,
                        size: 14, color: AppColors.kiwi500),
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: Text(
                        _selectedGoalName ?? 'Select goal',
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: _selectedGoalName != null
                                      ? AppColors.kiwi600
                                      : AppColors.contentTertiary,
                                  fontWeight: FontWeight.w500,
                                ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.unfold_more,
                        size: 14, color: AppColors.contentTertiary),
                  ],
                ),
              ),
            ),
            const Spacer(),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz,
                  color: AppColors.contentSecondary),
              onSelected: (v) {
                if (v == 'delete') _delete();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline,
                          size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Row 2: Checkmark + date/time
        Row(
          children: [
            GestureDetector(
              onTap: () {
                widget.notifier.toggleComplete(widget.task.id);
                Navigator.of(context).pop();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: widget.task.completed
                      ? AppColors.kiwi400
                      : Colors.white,
                  border: Border.all(
                    color: widget.task.completed
                        ? AppColors.kiwi400
                        : AppColors.borderSubtle,
                    width: 2,
                  ),
                ),
                child: widget.task.completed
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _pickDateTime,
              child: Text(
                _dateTimeLabel,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: _isOverdue ? Colors.red : AppColors.content,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCompactView(BuildContext context, double bottomPadding) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 20, 24, 20 + bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTopSection(context),

          const SizedBox(height: 16),

          // Title (editable, no background)
          TextField(
            controller: _titleCtrl,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.content,
                  fontWeight: FontWeight.w600,
                ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              hintText: 'Task title',
              contentPadding: EdgeInsets.zero,
              isDense: true,
            ),
            maxLines: null,
            onChanged: (_) => _markDirty(),
          ),

          const SizedBox(height: 8),

          // Description (tappable to expand to full view)
          GestureDetector(
            onTap: () => setState(() => _descFullView = true),
            child: Text(
              _descCtrl.text.isNotEmpty
                  ? _descCtrl.text
                  : 'Add details, outcomes, or notes...',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _descCtrl.text.isNotEmpty
                        ? AppColors.contentSecondary
                        : AppColors.contentTertiary,
                  ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          const SizedBox(height: 20),

          // Save button (only when dirty)
          if (_dirty)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save'),
              ),
            ),
        ],
      ),
    );
  }

  void _showGoalPicker() {
    if (widget.goals.isEmpty) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Goal', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...widget.goals.map((g) => ListTile(
                  leading: const Icon(Icons.flag,
                      size: 16, color: AppColors.kiwi500),
                  title: Text(
                    g.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: g.title == _selectedGoalName
                      ? const Icon(Icons.check, color: AppColors.kiwi500)
                      : null,
                  onTap: () {
                    setState(() {
                      _selectedGoalName = g.title;
                      _dirty = true;
                    });
                    Navigator.of(context).pop();
                  },
                )),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Daily reflection entry card → opens wizard
// ---------------------------------------------------------------------------

class _DailyReflectionCard extends StatelessWidget {
  const _DailyReflectionCard({required this.tasks});

  final List<Task> tasks;

  @override
  Widget build(BuildContext context) {
    final completed = tasks.where((t) => t.completed).length;
    final total = tasks.length;

    return KinwiiCard(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (_) => _DailyReflectionWizard(tasks: tasks),
        );
      },
      color: AppColors.kiwi50,
      child: Row(
        children: [
          const Icon(Icons.rate_review_outlined,
              size: 20, color: AppColors.kiwi600),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Daily reflection',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.content,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                Text(
                  '$completed of $total tasks completed',
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
  }
}

// ---------------------------------------------------------------------------
// Daily reflection wizard (2-step: review tasks → add reasons for incomplete)
// ---------------------------------------------------------------------------

class _DailyReflectionWizard extends ConsumerStatefulWidget {
  const _DailyReflectionWizard({required this.tasks});

  final List<Task> tasks;

  @override
  ConsumerState<_DailyReflectionWizard> createState() =>
      _DailyReflectionWizardState();
}

class _DailyReflectionWizardState
    extends ConsumerState<_DailyReflectionWizard> {
  final _pageController = PageController();
  int _currentStep = 0;
  final Map<String, TextEditingController> _reasonControllers = {};

  List<Task> get _completed =>
      widget.tasks.where((t) => t.completed).toList();
  List<Task> get _incomplete =>
      widget.tasks.where((t) => !t.completed).toList();

  @override
  void initState() {
    super.initState();
    for (final t in _incomplete) {
      _reasonControllers[t.id] =
          TextEditingController(text: t.skipReason ?? '');
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final c in _reasonControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _goToStep(int step) {
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    setState(() => _currentStep = step);
  }

  Future<void> _finish() async {
    // Save all skip reasons
    final notifier = ref.read(_todayTasksProvider.notifier);
    for (final t in _incomplete) {
      final reason = _reasonControllers[t.id]?.text.trim() ?? '';
      if (reason.isNotEmpty && reason != (t.skipReason ?? '')) {
        await notifier.updateSkipReason(t.id, reason);
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final totalSteps = _incomplete.isEmpty ? 1 : 2;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          // Handle bar
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderSubtle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Step indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _StepBar(
                currentStep: _currentStep, totalSteps: totalSteps),
          ),

          // Pages
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                // Step 1: Review completed tasks
                _ReviewStep(
                  completed: _completed,
                  incomplete: _incomplete,
                  totalTasks: widget.tasks.length,
                  onNext: _incomplete.isNotEmpty
                      ? () => _goToStep(1)
                      : _finish,
                  isLastStep: _incomplete.isEmpty,
                ),

                // Step 2: Add reasons for incomplete (only if there are incomplete tasks)
                if (_incomplete.isNotEmpty)
                  _ReasonsStep(
                    incomplete: _incomplete,
                    controllers: _reasonControllers,
                    onBack: () => _goToStep(0),
                    onFinish: _finish,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Step indicator bar
class _StepBar extends StatelessWidget {
  const _StepBar({required this.currentStep, required this.totalSteps});

  final int currentStep;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(totalSteps, (i) {
        return Expanded(
          child: Container(
            height: 4,
            margin: EdgeInsets.only(right: i < totalSteps - 1 ? 4 : 0),
            decoration: BoxDecoration(
              color:
                  i <= currentStep ? AppColors.kiwi400 : AppColors.borderSubtle,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }
}

// Step 1: Review tasks
class _ReviewStep extends StatelessWidget {
  const _ReviewStep({
    required this.completed,
    required this.incomplete,
    required this.totalTasks,
    required this.onNext,
    required this.isLastStep,
  });

  final List<Task> completed;
  final List<Task> incomplete;
  final int totalTasks;
  final VoidCallback onNext;
  final bool isLastStep;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How did today go?',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColors.content,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            '${completed.length} of $totalTasks tasks completed',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.contentSecondary,
                ),
          ),
          const SizedBox(height: 20),

          if (completed.isNotEmpty) ...[
            Text(
              'Completed',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppColors.kiwi600,
                  ),
            ),
            const SizedBox(height: 8),
            ...completed.map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle,
                          size: 20, color: AppColors.kiwi500),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          t.title,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppColors.contentSecondary,
                                    decoration: TextDecoration.lineThrough,
                                  ),
                        ),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 16),
          ],

          if (incomplete.isNotEmpty) ...[
            Text(
              'Incomplete',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppColors.contentTertiary,
                  ),
            ),
            const SizedBox(height: 8),
            ...incomplete.map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.radio_button_unchecked,
                          size: 20, color: AppColors.contentTertiary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          t.title,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppColors.content,
                                  ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],

          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onNext,
              child:
                  Text(isLastStep ? 'Done' : 'Continue'),
            ),
          ),
        ],
      ),
    );
  }
}

// Step 2: Add reasons for incomplete tasks
class _ReasonsStep extends StatelessWidget {
  const _ReasonsStep({
    required this.incomplete,
    required this.controllers,
    required this.onBack,
    required this.onFinish,
  });

  final List<Task> incomplete;
  final Map<String, TextEditingController> controllers;
  final VoidCallback onBack;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What happened?',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColors.content,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Optional — note why these tasks were incomplete.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.contentSecondary,
                ),
          ),
          const SizedBox(height: 20),

          ...incomplete.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.radio_button_unchecked,
                            size: 18, color: AppColors.contentTertiary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            t.title,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: AppColors.content),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.only(left: 26),
                      child: TextField(
                        controller: controllers[t.id],
                        style: Theme.of(context).textTheme.bodySmall,
                        decoration: InputDecoration(
                          hintText: 'Why? (optional)',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                                color: AppColors.borderSubtle),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )),

          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                flex: 1,
                child: OutlinedButton(
                  onPressed: onBack,
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: onFinish,
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
