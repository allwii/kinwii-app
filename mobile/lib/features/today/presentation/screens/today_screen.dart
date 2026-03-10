// TodayScreen - "What should I focus on right now?"
// Usage: Registered as /today route inside AppShell's ShellRoute.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/kinwii_card.dart';
import '../../../../core/widgets/progress_bar.dart';
import '../../../../models/mission.dart';
import '../../../../models/task.dart';
import '../../../../models/weekly_plan.dart';
import '../../../../features/auth/presentation/screens/login_screen.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final _missionProvider = FutureProvider.autoDispose<Mission?>((ref) async {
  final api = ref.read(apiServiceProvider);
  try {
    final response = await api.get('/mission');
    if (response.data == null) return null;
    return Mission.fromJson(response.data as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
});

final _weeklyPlanProvider =
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
    state = const AsyncValue.loading();
    try {
      final api = _ref.read(apiServiceProvider);
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final response =
          await api.get('/tasks', queryParameters: {'date': dateStr});
      final list = (response.data as List<dynamic>)
          .map((e) => Task.fromJson(e as Map<String, dynamic>))
          .toList();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> toggleComplete(String taskId) async {
    final current = state.valueOrNull;
    if (current == null) return;

    // Optimistic update
    final idx = current.indexWhere((t) => t.id == taskId);
    if (idx == -1) return;
    final updated = current[idx].copyWith(completed: !current[idx].completed);
    final optimistic = List<Task>.from(current)..[idx] = updated;
    state = AsyncValue.data(optimistic);

    try {
      final api = _ref.read(apiServiceProvider);
      await api.patch('/tasks/$taskId/complete');
    } catch (_) {
      // Revert on failure
      state = AsyncValue.data(current);
    }
  }

  Future<void> addTask({
    required String weeklyPlanId,
    required String title,
    required EnergyType energyType,
  }) async {
    try {
      final api = _ref.read(apiServiceProvider);
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final response = await api.post('/tasks', data: {
        'weekly_plan_id': weeklyPlanId,
        'title': title,
        'date': dateStr,
        'energy_type': energyType.name,
      });
      final newTask = Task.fromJson(response.data as Map<String, dynamic>);
      final current = state.valueOrNull ?? [];
      state = AsyncValue.data([...current, newTask]);
    } catch (_) {
      // Let caller handle
      rethrow;
    }
  }

  Future<void> refresh() => _load();
}

// Daily focus suggestions provider — no autoDispose so the response is cached
// for the app session. Keyed by (weeklyPlanId, date) so it auto-refreshes on
// a new day without any manual invalidation.
final _dailyFocusProvider = FutureProvider
    .family<Map<String, dynamic>?, (String, String)>((ref, key) async {
  final (weeklyPlanId, date) = key;
  final api = ref.read(apiServiceProvider);
  try {
    final response = await api.post('/ai/suggest-daily-focus', data: {
      'weekly_plan_id': weeklyPlanId,
      'date': date,
    });
    return response.data as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missionAsync = ref.watch(_missionProvider);
    final weeklyPlanAsync = ref.watch(_weeklyPlanProvider);
    final tasksAsync = ref.watch(_todayTasksProvider);
    final today = DateTime.now();

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: weeklyPlanAsync.maybeWhen(
        data: (plan) => FloatingActionButton(
          onPressed: plan == null
              ? null
              : () {
                  final weeklyPlanId = plan.id;
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    builder: (_) => _AddTaskSheet(
                      weeklyPlanId: weeklyPlanId,
                      notifier: ref.read(_todayTasksProvider.notifier),
                      onAdded: () async {
                        await ref
                            .read(_todayTasksProvider.notifier)
                            .refresh();
                      },
                    ),
                  );
                },
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
            ref.invalidate(_missionProvider);
            ref.invalidate(_weeklyPlanProvider);
            await ref.read(_todayTasksProvider.notifier).refresh();
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Mission statement (subtle)
              SliverToBoxAdapter(
                child: missionAsync.maybeWhen(
                  data: (mission) => mission != null
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                          child: Text(
                            mission.statement,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: AppColors.kiwi600,
                                  fontStyle: FontStyle.italic,
                                ),
                          ),
                        )
                      : const SizedBox.shrink(),
                  orElse: () => const SizedBox.shrink(),
                ),
              ),

              // Date header + mission/roles icon
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 16, 4),
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
                        onPressed: () => context.push('/mission'),
                        icon: const Icon(
                          Icons.compass_calibration_outlined,
                          color: AppColors.kiwi500,
                          size: 22,
                        ),
                        tooltip: 'Mission & Roles',
                      ),
                    ],
                  ),
                ),
              ),

              // Weekly intent card
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: weeklyPlanAsync.when(
                    loading: () => const _IntentCardSkeleton(),
                    error: (_, __) => const _IntentCardSkeleton(),
                    data: (plan) => plan == null
                        ? const _IntentCardSkeleton()
                        : _IntentCard(plan: plan),
                  ),
                ),
              ),

              // AI daily focus suggestions
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: weeklyPlanAsync.maybeWhen(
                    data: (plan) => plan != null
                        ? _DailyFocusCard(weeklyPlanId: plan.id)
                        : const SizedBox.shrink(),
                    orElse: () => const SizedBox.shrink(),
                  ),
                ),
              ),

              // Section label
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
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
                      child: CircularProgressIndicator(
                        color: AppColors.kiwi400,
                      ),
                    ),
                  ),
                ),
                error: (_, __) => const SliverToBoxAdapter(
                  child: EmptyState(
                    message: 'Could not load tasks. Pull to refresh.',
                  ),
                ),
                data: (tasks) {
                  final visible = tasks.take(5).toList();
                  if (visible.isEmpty) {
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
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) => _TaskTile(
                        task: visible[index],
                        onToggle: () => ref
                            .read(_todayTasksProvider.notifier)
                            .toggleComplete(visible[index].id),
                      ),
                    ),
                  );
                },
              ),

              // Reflection prompt
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                  child: weeklyPlanAsync.maybeWhen(
                    data: (plan) => plan != null
                        ? _ReflectionPrompt(weeklyPlanId: plan.id)
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
}

// ---------------------------------------------------------------------------
// Intent card
// ---------------------------------------------------------------------------

class _IntentCard extends StatelessWidget {
  const _IntentCard({required this.plan});

  final WeeklyPlan plan;

  @override
  Widget build(BuildContext context) {
    return KinwiiCard(
      color: AppColors.kiwi50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This week',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.kiwi600,
                  letterSpacing: 0.4,
                ),
          ),
          const SizedBox(height: 6),
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
      ),
    );
  }
}

class _IntentCardSkeleton extends StatelessWidget {
  const _IntentCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return KinwiiCard(
      color: AppColors.kiwi50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 12,
            width: 60,
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
// Daily focus suggestions card
// ---------------------------------------------------------------------------

class _DailyFocusCard extends ConsumerStatefulWidget {
  const _DailyFocusCard({required this.weeklyPlanId});

  final String weeklyPlanId;

  @override
  ConsumerState<_DailyFocusCard> createState() => _DailyFocusCardState();
}

class _DailyFocusCardState extends ConsumerState<_DailyFocusCard> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final focusAsync = ref.watch(_dailyFocusProvider((widget.weeklyPlanId, today)));

    return focusAsync.when(
      loading: () => KinwiiCard(
        color: AppColors.kiwi50,
        child: Row(
          children: [
            const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.kiwi400,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Getting focus suggestions…',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.kiwi600,
                  ),
            ),
          ],
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (data) {
        if (data == null) return const SizedBox.shrink();
        final suggestions = (data['suggestions'] as List<dynamic>?)
                ?.cast<String>() ??
            [];
        final nudge = data['nudge'] as String?;
        if (suggestions.isEmpty) return const SizedBox.shrink();

        return KinwiiCard(
          color: AppColors.kiwi50,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.auto_awesome,
                    size: 16,
                    color: AppColors.kiwi500,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Suggested focus',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: AppColors.kiwi600,
                        ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => _dismissed = true),
                    child: const Icon(
                      Icons.close,
                      size: 16,
                      color: AppColors.contentTertiary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...suggestions.map(
                (s) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.kiwi400,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
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
              if (nudge != null) ...[
                const SizedBox(height: 4),
                Text(
                  nudge,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.kiwi600,
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Task tile
// ---------------------------------------------------------------------------

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task, required this.onToggle});

  final Task task;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return KinwiiCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: onToggle,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color:
                    task.completed ? AppColors.kiwi400 : Colors.transparent,
                border: Border.all(
                  color: task.completed
                      ? AppColors.kiwi400
                      : AppColors.borderSubtle,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: task.completed
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              task.title,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: task.completed
                        ? AppColors.contentTertiary
                        : AppColors.content,
                    decoration: task.completed
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                  ),
            ),
          ),
          const SizedBox(width: 8),
          _EnergyPill(energyType: task.energyType),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Energy type pill
// ---------------------------------------------------------------------------

class _EnergyPill extends StatelessWidget {
  const _EnergyPill({required this.energyType});

  final EnergyType energyType;

  static const _labels = {
    EnergyType.deep: 'Deep',
    EnergyType.admin: 'Admin',
    EnergyType.creative: 'Creative',
    EnergyType.personal: 'Personal',
  };

  static const _colors = {
    EnergyType.deep: AppColors.energyDeep,
    EnergyType.admin: AppColors.energyAdmin,
    EnergyType.creative: AppColors.energyCreative,
    EnergyType.personal: AppColors.energyPersonal,
  };

  static const _textColors = {
    EnergyType.deep: AppColors.kiwi700,
    EnergyType.admin: AppColors.contentSecondary,
    EnergyType.creative: Color(0xFF7C3AED),
    EnergyType.personal: Color(0xFFBE123C),
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _colors[energyType],
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _labels[energyType] ?? '',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _textColors[energyType],
              fontWeight: FontWeight.w500,
            ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add task bottom sheet
// ---------------------------------------------------------------------------

class _AddTaskSheet extends StatefulWidget {
  const _AddTaskSheet({
    required this.weeklyPlanId,
    required this.notifier,
    required this.onAdded,
  });

  final String weeklyPlanId;
  final _TasksNotifier notifier;
  final Future<void> Function()? onAdded;

  @override
  State<_AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends State<_AddTaskSheet> {
  final _titleController = TextEditingController();
  EnergyType _selectedEnergy = EnergyType.deep;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Please enter a task title');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await widget.notifier.addTask(
        weeklyPlanId: widget.weeklyPlanId,
        title: title,
        energyType: _selectedEnergy,
      );
      await widget.onAdded?.call();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to add task. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'New task',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _titleController,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'What needs to get done?',
              hintText: 'e.g. Draft proposal outline',
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          Text(
            'Energy type',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.contentSecondary,
                ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: EnergyType.values.map((type) {
              final isSelected = _selectedEnergy == type;
              return GestureDetector(
                onTap: () => setState(() => _selectedEnergy = type),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.kiwi400
                        : AppColors.borderSubtle,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    type.name[0].toUpperCase() + type.name.substring(1),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: isSelected
                              ? Colors.white
                              : AppColors.contentSecondary,
                        ),
                  ),
                ),
              );
            }).toList(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _submit,
              child: _isLoading
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
    );
  }
}

// ---------------------------------------------------------------------------
// Reflection prompt
// ---------------------------------------------------------------------------

class _ReflectionPrompt extends ConsumerWidget {
  const _ReflectionPrompt({required this.weeklyPlanId});

  final String weeklyPlanId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reflectionAsync = ref.watch(_reflectionExistsProvider(weeklyPlanId));
    return reflectionAsync.maybeWhen(
      data: (exists) => exists
          ? const SizedBox.shrink()
          : KinwiiCard(
              color: AppColors.kiwi50,
              onTap: () => context.go('/reflect'),
              child: Row(
                children: [
                  const Icon(
                    Icons.auto_awesome_outlined,
                    color: AppColors.kiwi500,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'How did this week go? Take a moment to reflect.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.kiwi700,
                          ),
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: AppColors.kiwi500,
                  ),
                ],
              ),
            ),
      orElse: () => const SizedBox.shrink(),
    );
  }
}

final _reflectionExistsProvider =
    FutureProvider.autoDispose.family<bool, String>((ref, weeklyPlanId) async {
  final api = ref.read(apiServiceProvider);
  try {
    final response = await api.get('/reflection/$weeklyPlanId');
    return response.data != null;
  } catch (_) {
    return false;
  }
});
