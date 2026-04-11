// TodayScreen - "What should I focus on right now?"
// Simplified: task list + AI suggestions + daily reflection (evening).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/kinwii_card.dart';
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
    final today = DateTime.now();
    final isEvening = today.hour >= 17;

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: weeklyPlanAsync.maybeWhen(
        data: (plan) => plan == null
            ? null
            : FloatingActionButton(
                onPressed: () => _showAddTaskSheet(context, ref, plan.id),
                backgroundColor: AppColors.kiwi400,
                foregroundColor: Colors.white,
                child: const Icon(Icons.add),
              ),
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

              // Section label
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                  child: Text(
                    "Today's focus",
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.content,
                        ),
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
                        onToggle: () => ref
                            .read(_todayTasksProvider.notifier)
                            .toggleComplete(tasks[index].id),
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
                              _showAddTaskSheet(context, ref, plan.id,
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

  void _showAddTaskSheet(BuildContext context, WidgetRef ref, String planId,
      {String? initialTitle}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AddTaskSheet(
        weeklyPlanId: planId,
        notifier: ref.read(_todayTasksProvider.notifier),
        initialTitle: initialTitle,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Task tile with description and time
// ---------------------------------------------------------------------------

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task, required this.onToggle});

  final Task task;
  final VoidCallback onToggle;

  static const _energyColors = {
    EnergyType.deep: AppColors.energyDeep,
    EnergyType.admin: AppColors.energyAdmin,
    EnergyType.creative: AppColors.energyCreative,
    EnergyType.personal: AppColors.energyPersonal,
  };

  @override
  Widget build(BuildContext context) {
    return KinwiiCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onToggle,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 24,
              height: 24,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: task.completed ? AppColors.kiwi400 : Colors.white,
                border: Border.all(
                  color:
                      task.completed ? AppColors.kiwi400 : AppColors.borderSubtle,
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
              ],
            ),
          ),
          if (task.time != null) ...[
            const SizedBox(width: 8),
            Text(
              _formatTime(task.time!),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.contentTertiary,
                  ),
            ),
          ],
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _energyColors[task.energyType] ?? AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              task.energyType.name,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.contentSecondary,
                    fontSize: 10,
                  ),
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

class _AddTaskSheet extends StatefulWidget {
  const _AddTaskSheet({
    required this.weeklyPlanId,
    required this.notifier,
    this.initialTitle,
  });

  final String weeklyPlanId;
  final _TasksNotifier notifier;
  final String? initialTitle;

  @override
  State<_AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends State<_AddTaskSheet> {
  late final TextEditingController _titleCtrl;
  final _descCtrl = TextEditingController();
  EnergyType _energy = EnergyType.deep;
  TimeOfDay? _time;
  bool _loading = false;

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

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    setState(() => _loading = true);
    try {
      String? timeStr;
      if (_time != null) {
        timeStr =
            '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}:00';
      }
      await widget.notifier.addTask(
        weeklyPlanId: widget.weeklyPlanId,
        title: title,
        energyType: _energy,
        description:
            _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        time: timeStr,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add task',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
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
          TextField(
            controller: _descCtrl,
            textCapitalization: TextCapitalization.sentences,
            maxLines: 2,
            minLines: 1,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
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
                        : 'Set time (optional)',
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
          const SizedBox(height: 14),
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
          const SizedBox(height: 20),
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
