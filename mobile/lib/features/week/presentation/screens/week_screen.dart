// WeekScreen - "Is this week aligned?"
// Usage: Registered as /week route inside AppShell's ShellRoute.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/kinwii_card.dart';
import '../../../../core/widgets/progress_bar.dart';
import '../../../../core/widgets/task_detail_sheet.dart';
import '../../../../models/quarterly_goal.dart';
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

final _weekGoalsProvider =
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
  int _weekOffset = 0;
  bool _editingIntent = false;
  bool _suggestingIntent = false;
  final _intentController = TextEditingController();
  final _intentFocusNode = FocusNode();
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    _intentFocusNode.addListener(() {
      if (!_intentFocusNode.hasFocus && _editingIntent) {
        setState(() => _editingIntent = false);
      }
    });
  }

  @override
  void dispose() {
    _intentController.dispose();
    _intentFocusNode.dispose();
    super.dispose();
  }

  void _jumpToWeekOf(DateTime date) {
    final currentMonday = _startOfWeek(DateTime.now());
    final targetMonday = _startOfWeek(date);
    final diff = targetMonday.difference(currentMonday).inDays ~/ 7;
    setState(() {
      _weekOffset = diff;
      _selectedDay = date;
      _editingIntent = false;
    });
  }

  Future<void> _showWeekPicker() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.kiwi400),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      _jumpToWeekOf(picked);
    }
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
      _selectedDay = _selectedDay.subtract(const Duration(days: 7));
      _editingIntent = false;
    });
  }

  void _goToNextWeek() {
    setState(() {
      _weekOffset++;
      _selectedDay = _selectedDay.add(const Duration(days: 7));
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
              // Header — tappable to open week picker
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        color: AppColors.content,
                        onPressed: _goToPreviousWeek,
                        tooltip: 'Previous week',
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: _showWeekPicker,
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Week of ${DateFormat('MMM d').format(monday)} – ${DateFormat('MMM d').format(sunday)}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(color: AppColors.content),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.calendar_today,
                                      size: 14, color: AppColors.contentTertiary),
                                ],
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
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        color: AppColors.content,
                        onPressed: _goToNextWeek,
                        tooltip: 'Next week',
                      ),
                    ],
                  ),
                ),
              ),

              // Intent card
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
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
                                focusNode: _intentFocusNode,
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

              // "This week" label + AI align (inline)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
                  child: Row(
                    children: [
                      Text(
                        isCurrentWeek ? 'This week' : 'Days',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: AppColors.content,
                            ),
                      ),
                      const Spacer(),
                      if (isCurrentWeek)
                        planAsync.maybeWhen(
                          data: (plan) => plan != null
                              ? GestureDetector(
                                  onTap: aiState.isLoading
                                      ? null
                                      : () async {
                                          final notifier = ref.read(
                                              _aiSuggestionsProvider.notifier);
                                          final messenger =
                                              ScaffoldMessenger.of(context);
                                          final capturedContext = context;
                                          await notifier.align(plan.id);
                                          final updated =
                                              ref.read(_aiSuggestionsProvider);
                                          if (!mounted) return;
                                          if (updated.suggestions.isNotEmpty) {
                                            _showAiSheet(capturedContext,
                                                updated.suggestions);
                                            ref
                                                .read(_aiSuggestionsProvider
                                                    .notifier)
                                                .reset();
                                          } else if (updated.error != null) {
                                            messenger.showSnackBar(SnackBar(
                                                content:
                                                    Text(updated.error!)));
                                          }
                                        },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: AppColors.kiwi50,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (aiState.isLoading)
                                          const SizedBox(
                                            height: 14,
                                            width: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 1.5,
                                              color: AppColors.kiwi500,
                                            ),
                                          )
                                        else
                                          const Icon(
                                              Icons.auto_awesome_outlined,
                                              size: 14,
                                              color: AppColors.kiwi500),
                                        const SizedBox(width: 4),
                                        Text(
                                          aiState.isLoading
                                              ? 'Aligning…'
                                              : 'AI Align',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: AppColors.kiwi600,
                                                fontWeight: FontWeight.w500,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                          orElse: () => const SizedBox.shrink(),
                        ),
                    ],
                  ),
                ),
              ),

              // 7-day selector (compact)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: planAsync.maybeWhen(
                    data: (plan) => plan == null
                        ? _DaySelector(
                            days: _weekDays(monday),
                            tasks: const [],
                            selectedDay: _selectedDay,
                            onDayTap: (day) =>
                                setState(() => _selectedDay = day),
                          )
                        : _WeekDaySelectorLoader(
                            plan: plan,
                            days: _weekDays(monday),
                            selectedDay: _selectedDay,
                            onDayTap: (day) =>
                                setState(() => _selectedDay = day),
                          ),
                    orElse: () => _DaySelector(
                      days: _weekDays(monday),
                      tasks: const [],
                      selectedDay: _selectedDay,
                      onDayTap: (day) => setState(() => _selectedDay = day),
                    ),
                  ),
                ),
              ),

              // Tasks for selected day
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: planAsync.maybeWhen(
                    data: (plan) => plan != null
                        ? _SelectedDayTasks(
                            planId: plan.id,
                            quarterId: plan.quarterId,
                            selectedDay: _selectedDay,
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
    required this.focusNode,
    required this.onEditTap,
    required this.onSave,
    required this.onCancel,
    required this.onSuggestIntent,
  });

  final WeeklyPlan plan;
  final bool isEditing;
  final bool isSuggestingIntent;
  final TextEditingController intentController;
  final FocusNode focusNode;
  final VoidCallback onEditTap;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final VoidCallback onSuggestIntent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.kiwi50,
            AppColors.kiwi50.withValues(alpha: 0.5),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text('🎯', style: TextStyle(fontSize: 24)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Weekly intent',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: AppColors.kiwi700,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const Spacer(),
                    if (isEditing)
                      GestureDetector(
                        onTap: onSave,
                        child: const Icon(
                          Icons.check,
                          size: 20,
                          color: AppColors.kiwi500,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                if (isEditing) ...[
                  TextField(
                    controller: intentController,
                    focusNode: focusNode,
                    autofocus: true,
                    maxLines: 3,
                    minLines: 1,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => onSave(),
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: AppColors.content,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                    decoration: InputDecoration(
                      hintText: 'What do you want to achieve this week?',
                      hintStyle:
                          Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: AppColors.contentTertiary,
                                fontWeight: FontWeight.w400,
                              ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                  ),
                  if (plan.quarterId != null) ...[
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: isSuggestingIntent ? null : onSuggestIntent,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.kiwi200),
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
                              const Icon(Icons.auto_awesome,
                                  size: 14, color: AppColors.kiwi500),
                            const SizedBox(width: 5),
                            Text(
                              isSuggestingIntent
                                  ? 'Suggesting…'
                                  : 'Suggest intent',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: AppColors.kiwi600,
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ] else ...[
                  GestureDetector(
                    onTap: onEditTap,
                    child: Text(
                      plan.intent,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: AppColors.kiwi600,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                          ),
                    ),
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
          ),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.kiwi50,
            AppColors.kiwi50.withValues(alpha: 0.5),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text('🎯', style: TextStyle(fontSize: 24)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Weekly intent',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColors.kiwi700,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  plan.intent,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.kiwi600,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
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
          ),
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

// ---------------------------------------------------------------------------
// Compact day selector (replaces old _DayGrid)
// ---------------------------------------------------------------------------

class _WeekDaySelectorLoader extends ConsumerWidget {
  const _WeekDaySelectorLoader({
    required this.plan,
    required this.days,
    required this.selectedDay,
    required this.onDayTap,
  });

  final WeeklyPlan plan;
  final List<DateTime> days;
  final DateTime selectedDay;
  final void Function(DateTime) onDayTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(_weekTasksProvider(plan.id));
    return tasksAsync.when(
      loading: () => _DaySelector(
          days: days, tasks: const [], selectedDay: selectedDay, onDayTap: onDayTap),
      error: (_, __) => _DaySelector(
          days: days, tasks: const [], selectedDay: selectedDay, onDayTap: onDayTap),
      data: (tasks) => _DaySelector(
          days: days, tasks: tasks, selectedDay: selectedDay, onDayTap: onDayTap),
    );
  }
}

class _DaySelector extends StatelessWidget {
  const _DaySelector({
    required this.days,
    required this.tasks,
    required this.selectedDay,
    required this.onDayTap,
  });

  final List<DateTime> days;
  final List<Task> tasks;
  final DateTime selectedDay;
  final void Function(DateTime) onDayTap;

  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);

    return Row(
      children: List.generate(days.length, (i) {
        final day = days[i];
        final isSelected = _isSameDay(day, selectedDay);
        final isToday = _isSameDay(day, todayDate);
        final dayTasks = tasks.where((t) => _isSameDay(t.date, day)).toList();
        final hasTasks = dayTasks.isNotEmpty;
        final allDone = hasTasks && dayTasks.every((t) => t.completed);

        return Expanded(
          child: GestureDetector(
            onTap: () => onDayTap(day),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.kiwi400 : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: isToday && !isSelected
                    ? Border.all(color: AppColors.kiwi400, width: 1.5)
                    : null,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _dayLabels[i],
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: isSelected
                              ? Colors.white
                              : AppColors.contentTertiary,
                          fontSize: 10,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${day.day}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isSelected
                              ? Colors.white
                              : isToday
                                  ? AppColors.kiwi600
                                  : AppColors.content,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 3),
                  // Dot indicator: green if all done, gray if has tasks
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: !hasTasks
                          ? Colors.transparent
                          : isSelected
                              ? Colors.white
                              : allDone
                                  ? AppColors.kiwi400
                                  : AppColors.borderSubtle,
                    ),
                  ),
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
// Inline task list for selected day
// ---------------------------------------------------------------------------

class _SelectedDayTasks extends ConsumerWidget {
  const _SelectedDayTasks({
    required this.planId,
    required this.quarterId,
    required this.selectedDay,
  });

  final String planId;
  final String? quarterId;
  final DateTime selectedDay;

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(_weekTasksProvider(planId));
    // Watch so goals load eagerly and are available by the time the user
    // taps a task; the sheet falls back to awaiting the future if not ready.
    ref.watch(_weekGoalsProvider);

    return tasksAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (allTasks) {
        final dayTasks =
            allTasks.where((t) => _isSameDay(t.date, selectedDay)).toList();

        if (dayTasks.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'No tasks for this day.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.contentTertiary,
                  ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: dayTasks.map((task) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: () => _showTaskDetail(context, ref, task, planId),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => _toggleTask(ref, task.id, planId),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(5),
                          color: task.completed
                              ? AppColors.kiwi400
                              : Colors.white,
                          border: Border.all(
                            color: task.completed
                                ? AppColors.kiwi400
                                : AppColors.borderSubtle,
                            width: 1.5,
                          ),
                        ),
                        child: task.completed
                            ? const Icon(Icons.check,
                                size: 12, color: Colors.white)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        task.title,
                        style:
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
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
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Future<void> _toggleTask(WidgetRef ref, String taskId, String planId) async {
    try {
      final api = ref.read(apiServiceProvider);
      await api.patch('/tasks/$taskId/complete');
      ref.invalidate(_weekTasksProvider(planId));
    } catch (_) {
      // Silent fail
    }
  }

  Future<void> _showTaskDetail(
      BuildContext context, WidgetRef ref, Task task, String planId) async {
    final api = ref.read(apiServiceProvider);
    // Goals provider is autoDispose; ensure it's loaded before opening.
    List<QuarterlyGoal> goals;
    try {
      goals = await ref.read(_weekGoalsProvider.future);
    } catch (_) {
      goals = [];
    }
    if (!context.mounted) return;

    // Resolve the current goal name from the plan's quarter_id.
    String? currentGoalName;
    if (quarterId != null) {
      final match = goals.where((g) => g.id == quarterId).toList();
      if (match.isNotEmpty) currentGoalName = match.first.title;
    }

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => TaskDetailSheet(
        task: task,
        goals: goals,
        currentGoalName: currentGoalName,
        onUpdate: (taskId, fields) async {
          await api.put('/tasks/$taskId', data: fields);
          ref.invalidate(_weekTasksProvider(planId));
        },
        onDelete: (taskId) async {
          await api.delete('/tasks/$taskId');
          ref.invalidate(_weekTasksProvider(planId));
        },
        onToggleComplete: (taskId) async {
          await api.patch('/tasks/$taskId/complete');
          ref.invalidate(_weekTasksProvider(planId));
        },
      ),
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
