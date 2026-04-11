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
      bottomNavigationBar: tasksAsync.maybeWhen(
        data: (tasks) => tasks.isNotEmpty
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                    child: Opacity(
                      opacity: isEvening ? 1.0 : 0.75,
                      child: _DailyReflectionCard(tasks: tasks),
                    ),
                  ),
                ],
              )
            : null,
        orElse: () => null,
      ),
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

              // Bottom spacing
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
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
      useRootNavigator: true,
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
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
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
// Add task sheet — unified layout matching task detail view
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
  TimeOfDay? _time;
  bool _loading = false;
  bool _descFullView = false;
  String? _selectedGoalId;
  String? _selectedGoalName;
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

  Future<String> _resolveWeeklyPlanId(String goalId, String goalTitle) async {
    final api = ref.read(apiServiceProvider);
    try {
      final response = await api.get('/week/current');
      if (response.data != null) return response.data['id'] as String;
    } catch (_) {}

    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final response = await api.post('/week', data: {
      'week_start_date': DateFormat('yyyy-MM-dd').format(monday),
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
      final planId =
          await _resolveWeeklyPlanId(_selectedGoalId!, _selectedGoalName!);
      String? timeStr;
      if (_time != null) {
        timeStr =
            '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}:00';
      }
      await widget.notifier.addTask(
        weeklyPlanId: planId,
        title: title,
        energyType: EnergyType.deep,
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

  void _showGoalPicker(List<QuarterlyGoal> goals) {
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
            ...goals.map((g) => ListTile(
                  leading: const Icon(Icons.flag,
                      size: 16, color: AppColors.kiwi500),
                  title: Text(g.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: g.id == _selectedGoalId
                      ? const Icon(Icons.check, color: AppColors.kiwi500)
                      : null,
                  onTap: () {
                    setState(() {
                      _selectedGoalId = g.id;
                      _selectedGoalName = g.title;
                    });
                    Navigator.of(context).pop();
                  },
                )),
          ],
        ),
      ),
    );
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? TimeOfDay.now(),
    );
    if (picked != null) setState(() => _time = picked);
  }

  String _formatTimeOfDay(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final p = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $p';
  }

  @override
  Widget build(BuildContext context) {
    final goalsAsync = ref.watch(_goalsProvider);
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    // Auto-select goal if only one exists
    goalsAsync.whenData((goals) {
      if (_selectedGoalId == null && goals.length == 1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _selectedGoalId == null) {
            setState(() {
              _selectedGoalId = goals.first.id;
              _selectedGoalName = goals.first.title;
            });
          }
        });
      }
    });

    final goals = goalsAsync.valueOrNull ?? [];

    // Full-view for description editing
    if (_descFullView) {
      return SizedBox(
        height: screenHeight * 0.92,
        child: _buildDescFullView(context, bottomPadding),
      );
    }

    // Compact view
    return SizedBox(
      height: screenHeight * 0.6,
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 20, 24, 20 + bottomPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Goal chip
            Row(
              children: [
                GestureDetector(
                  onTap: goals.length > 1
                      ? () => _showGoalPicker(goals)
                      : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
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
                          constraints:
                              const BoxConstraints(maxWidth: 220),
                          child: Text(
                            _selectedGoalName ?? 'Select goal',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: _selectedGoalName != null
                                      ? AppColors.kiwi600
                                      : AppColors.contentTertiary,
                                  fontWeight: FontWeight.w500,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (goals.length > 1) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.unfold_more,
                              size: 14,
                              color: AppColors.contentTertiary),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Row 2: Today + time
            Row(
              children: [
                const Icon(Icons.today,
                    size: 18, color: AppColors.contentSecondary),
                const SizedBox(width: 6),
                Text(
                  'Today',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.content,
                        fontWeight: FontWeight.w500,
                      ),
                ),
                if (_time != null) ...[
                  Text(
                    ', ${_formatTimeOfDay(_time!)}',
                    style:
                        Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.content,
                              fontWeight: FontWeight.w500,
                            ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => setState(() => _time = null),
                    child: const Icon(Icons.close,
                        size: 14, color: AppColors.contentTertiary),
                  ),
                ],
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: _pickTime,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: AppColors.surfaceAlt,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.schedule,
                            size: 14,
                            color: AppColors.contentTertiary),
                        const SizedBox(width: 4),
                        Text(
                          _time != null ? 'Change' : 'Set time',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                color: AppColors.contentTertiary,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Title (borderless, matches detail view)
            TextField(
              controller: _titleCtrl,
              autofocus: widget.initialTitle == null,
              textCapitalization: TextCapitalization.sentences,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.content,
                    fontWeight: FontWeight.w600,
                  ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                hintText: 'What task do you need to focus on?',
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
              maxLines: null,
            ),

            const SizedBox(height: 16),

            // Description (tappable, with visual height)
            GestureDetector(
              onTap: () => setState(() => _descFullView = true),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 60),
                child: Text(
                  _descCtrl.text.isNotEmpty
                      ? _descCtrl.text
                      : 'Add details, deliverables, or notes...',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _descCtrl.text.isNotEmpty
                            ? AppColors.contentSecondary
                            : AppColors.contentTertiary,
                      ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],

            const Spacer(),

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
                    : const Text('Add task'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDescFullView(BuildContext context, double bottomPadding) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 16 + bottomPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _titleCtrl.text.isNotEmpty
                      ? _titleCtrl.text
                      : 'New task',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.content,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _descFullView = false),
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
          const SizedBox(height: 8),
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
                hintText: 'add details, deliverables, or notes...',
                hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.contentTertiary,
                    ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
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
                hintText: 'add details, deliverables, or notes...',
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
                  : 'add details, deliverables, or notes...',
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

class _DailyReflectionCard extends StatefulWidget {
  const _DailyReflectionCard({required this.tasks});

  final List<Task> tasks;

  @override
  State<_DailyReflectionCard> createState() => _DailyReflectionCardState();
}

class _DailyReflectionCardState extends State<_DailyReflectionCard> {
  bool _completed = false;

  Future<void> _openWizard() async {
    await showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _DailyReflectionWizard(tasks: widget.tasks),
    );
    // Wizard was dismissed — mark as complete
    if (mounted) setState(() => _completed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_completed) {
      return KinwiiCard(
        onTap: _openWizard,
        child: Row(
          children: [
            const Icon(Icons.check_circle,
                size: 20, color: AppColors.kiwi500),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Daily reflection complete',
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

    final done = widget.tasks.where((t) => t.completed).length;
    final total = widget.tasks.length;

    return KinwiiCard(
      onTap: _openWizard,
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
                  'Daily reflection',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.content,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                Text(
                  '$done of $total tasks completed',
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
  final _tomorrowCtrl = TextEditingController();
  int _currentStep = 0;

  // Mutable copy of tasks so we can toggle completion inside the wizard
  late List<Task> _tasks;

  // Track which incomplete tasks to carry forward
  late Set<String> _carryIds;

  List<Task> get _incomplete => _tasks.where((t) => !t.completed).toList();

  @override
  void initState() {
    super.initState();
    _tasks = List<Task>.from(widget.tasks);
    _carryIds = _incomplete.map((t) => t.id).toSet();
  }

  void _toggleTask(String taskId) {
    setState(() {
      final idx = _tasks.indexWhere((t) => t.id == taskId);
      if (idx != -1) {
        _tasks[idx] = _tasks[idx].copyWith(completed: !_tasks[idx].completed);
        // Update carry set: remove from carry if now completed
        if (_tasks[idx].completed) {
          _carryIds.remove(taskId);
        } else {
          _carryIds.add(taskId);
        }
      }
    });
    // Also toggle on backend
    ref.read(_todayTasksProvider.notifier).toggleComplete(taskId);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _tomorrowCtrl.dispose();
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
    final notifier = ref.read(_todayTasksProvider.notifier);

    // Drop tasks not carried forward
    for (final t in _incomplete) {
      if (!_carryIds.contains(t.id)) {
        await notifier.updateSkipReason(t.id, 'Dropped in daily review');
      }
    }

    // Create tomorrow's focus as a task (if user entered one)
    final tomorrowText = _tomorrowCtrl.text.trim();
    if (tomorrowText.isNotEmpty) {
      try {
        final api = ref.read(apiServiceProvider);
        final tomorrow = DateTime.now().add(const Duration(days: 1));
        final tomorrowStr = DateFormat('yyyy-MM-dd').format(tomorrow);

        // Get current weekly plan for the task link
        try {
          final planResp = await api.get('/week/current');
          if (planResp.data != null) {
            final planId = planResp.data['id'] as String;
            await api.post('/tasks', data: {
              'weekly_plan_id': planId,
              'title': tomorrowText,
              'date': tomorrowStr,
              'energy_type': 'deep',
            });
          }
        } catch (_) {
          // No weekly plan — skip task creation silently
        }
      } catch (_) {
        // Silent fail — don't block dismiss
      }
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    const totalSteps = 3;

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

          // Step indicator + time estimate
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
            child: Column(
              children: [
                _StepBar(currentStep: _currentStep, totalSteps: totalSteps),
                const SizedBox(height: 6),
                Text(
                  '~1 minute',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.contentTertiary,
                      ),
                ),
              ],
            ),
          ),

          // Pages
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                // Step 1: Wins (with tappable checkmarks)
                _DailyWinsStep(
                  tasks: _tasks,
                  onToggle: _toggleTask,
                  onNext: () => _goToStep(1),
                ),

                // Step 2: Carry over
                _DailyCarryStep(
                  incomplete: _incomplete,
                  carryIds: _carryIds,
                  onToggleCarry: (id) => setState(() {
                    if (_carryIds.contains(id)) {
                      _carryIds.remove(id);
                    } else {
                      _carryIds.add(id);
                    }
                  }),
                  onBack: () => _goToStep(0),
                  onNext: () => _goToStep(2),
                ),

                // Step 3: Tomorrow's focus
                _DailyTomorrowStep(
                  controller: _tomorrowCtrl,
                  onBack: () => _goToStep(1),
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

// Step indicator bar (shared by daily + weekly wizards)
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

// Daily Step 1: Celebrate wins
class _DailyWinsStep extends StatelessWidget {
  const _DailyWinsStep({
    required this.tasks,
    required this.onToggle,
    required this.onNext,
  });

  final List<Task> tasks;
  final void Function(String taskId) onToggle;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final done = tasks.where((t) => t.completed).length;
    final total = tasks.length;
    final pct = total > 0 ? (done / total * 100).round() : 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Today\'s wins',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColors.content,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            '$done of $total done ($pct%)',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.kiwi600,
                  fontWeight: FontWeight.w500,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap to mark tasks done.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.contentTertiary,
                ),
          ),
          const SizedBox(height: 16),

          ...tasks.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: () => onToggle(t.id),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          color: t.completed
                              ? AppColors.kiwi400
                              : Colors.white,
                          border: Border.all(
                            color: t.completed
                                ? AppColors.kiwi400
                                : AppColors.borderSubtle,
                            width: 2,
                          ),
                        ),
                        child: t.completed
                            ? const Icon(Icons.check,
                                size: 14, color: Colors.white)
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          t.title,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: t.completed
                                    ? AppColors.contentTertiary
                                    : AppColors.content,
                                decoration: t.completed
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              )),

          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onNext,
              child: const Text('Continue'),
            ),
          ),
        ],
      ),
    );
  }
}

// Daily Step 2: Carry over or drop incomplete tasks
class _DailyCarryStep extends StatelessWidget {
  const _DailyCarryStep({
    required this.incomplete,
    required this.carryIds,
    required this.onToggleCarry,
    required this.onBack,
    required this.onNext,
  });

  final List<Task> incomplete;
  final Set<String> carryIds;
  final void Function(String id) onToggleCarry;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    if (incomplete.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'All done!',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.content,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Every task completed. Nice work.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.contentSecondary,
                  ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onNext,
                child: const Text('Continue'),
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What\'s carrying over?',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColors.content,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap to keep or drop each task.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.contentSecondary,
                ),
          ),
          const SizedBox(height: 16),

          ...incomplete.map((t) {
            final carry = carryIds.contains(t.id);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () => onToggleCarry(t.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: carry ? Colors.white : AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: carry
                          ? AppColors.kiwi300
                          : AppColors.borderSubtle,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        carry
                            ? Icons.arrow_forward_rounded
                            : Icons.close_rounded,
                        size: 18,
                        color: carry
                            ? AppColors.kiwi500
                            : AppColors.contentTertiary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          t.title,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: carry
                                    ? AppColors.content
                                    : AppColors.contentTertiary,
                                decoration: carry
                                    ? null
                                    : TextDecoration.lineThrough,
                              ),
                        ),
                      ),
                      Text(
                        carry ? 'Tomorrow' : 'Drop',
                        style:
                            Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: carry
                                      ? AppColors.kiwi600
                                      : AppColors.contentTertiary,
                                ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),

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
                  onPressed: onNext,
                  child: const Text('Continue'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Daily Step 3: Tomorrow's focus
class _DailyTomorrowStep extends StatelessWidget {
  const _DailyTomorrowStep({
    required this.controller,
    required this.onBack,
    required this.onFinish,
  });

  final TextEditingController controller;
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
            'Tomorrow\'s focus',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColors.content,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'What\'s the one thing that matters most tomorrow?',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.contentSecondary,
                ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            maxLines: 2,
            minLines: 1,
            decoration: const InputDecoration(
              hintText: 'e.g. Finish the proposal draft',
            ),
          ),
          const SizedBox(height: 28),
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
