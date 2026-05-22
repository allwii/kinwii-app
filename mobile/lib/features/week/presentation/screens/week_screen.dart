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
import '../../../../services/subscription_service.dart';
import '../../../../models/quarterly_goal.dart';
import '../../../../models/task.dart';
import '../../../../models/weekly_plan.dart';
import '../../../../services/providers.dart';
import '../../../../services/review_service.dart';
import '../../../../features/settings/presentation/screens/settings_screen.dart';

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

/// Fetches tasks for the week containing the given weekly plan.
///
/// Preferred path: query by **date range** so we catch tasks that were moved
/// across a week boundary (e.g., by auto-move on Sunday→Monday) but whose
/// `weekly_plan_id` still points to a different plan.
///
/// Fallback path: if the backend doesn't yet support `start_date`/`end_date`
/// (older deploy), fall back to `?weekly_plan_id=...` so the app still shows
/// tasks. Falling silently to an empty list previously caused "all tasks
/// disappeared" reports immediately after this provider was changed.
final _weekTasksProvider =
    FutureProvider.autoDispose.family<List<Task>, String>(
  (ref, weeklyPlanId) async {
    final api = ref.read(apiServiceProvider);

    List<Task> parse(dynamic data) => (data as List<dynamic>)
        .map((e) => Task.fromJson(e as Map<String, dynamic>))
        .toList();

    // Try the date-range path first.
    try {
      final planResp = await api.get('/week/$weeklyPlanId');
      final weekStartStr = planResp.data['week_start_date'] as String;
      final weekStart = DateTime.parse(weekStartStr);
      final weekEnd = weekStart.add(const Duration(days: 6));
      final resp = await api.get(
        '/tasks',
        queryParameters: {
          'start_date': weekStartStr,
          'end_date': DateFormat('yyyy-MM-dd').format(weekEnd),
        },
      );
      return parse(resp.data);
    } catch (_) {
      // Fall through to the legacy path on any failure (e.g., backend without
      // date-range support returns 400).
    }

    try {
      final resp = await api.get(
        '/tasks',
        queryParameters: {'weekly_plan_id': weeklyPlanId},
      );
      return parse(resp.data);
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

/// Returns the Dart weekday (1=Mon..7=Sun) for the user's first-day-of-week
/// setting string ('Monday', 'Sunday', 'Saturday').
int _firstDayNumber(String setting) {
  switch (setting) {
    case 'Sunday':
      return DateTime.sunday; // 7
    case 'Saturday':
      return DateTime.saturday; // 6
    default:
      return DateTime.monday; // 1
  }
}

/// Returns the start of the week containing [date], where the week begins on
/// the day indicated by [firstDay] (1=Mon..7=Sun).
DateTime _startOfWeek(DateTime date, {int firstDay = DateTime.monday}) {
  int diff = (date.weekday - firstDay) % 7;
  return DateTime(date.year, date.month, date.day - diff);
}

List<DateTime> _weekDays(DateTime start) =>
    List.generate(7, (i) => start.add(Duration(days: i)));

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
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
  }

  void _jumpToWeekOf(DateTime date) {
    final fd = _firstDayNumber(ref.read(firstDayOfWeekProvider));
    final currentStart = _startOfWeek(DateTime.now(), firstDay: fd);
    final targetStart = _startOfWeek(date, firstDay: fd);
    final diff = targetStart.difference(currentStart).inDays ~/ 7;
    setState(() {
      _weekOffset = diff;
      _selectedDay = date;
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

  void _showAddTask(
      BuildContext context, WidgetRef ref, WeeklyPlan? plan) {
    if (plan == null) return;

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _WeekAddTaskSheet(
        planId: plan.id,
        quarterId: plan.quarterId,
        date: _selectedDay,
        onCreated: () => ref.invalidate(_weekTasksProvider(plan.id)),
      ),
    );
  }


  void _showAiSheet(BuildContext context, List<String> suggestions) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
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
    });
  }

  void _goToNextWeek() {
    setState(() {
      _weekOffset++;
      _selectedDay = _selectedDay.add(const Duration(days: 7));
    });
  }

  @override
  Widget build(BuildContext context) {
    final isCurrentWeek = _weekOffset == 0;
    final planAsync = isCurrentWeek
        ? ref.watch(_currentWeekPlanProvider)
        : ref.watch(_previousWeekPlanProvider);
    final aiState = ref.watch(_aiSuggestionsProvider);
    final sub = ref.watch(subscriptionProvider);
    final firstDaySetting = ref.watch(firstDayOfWeekProvider);
    final firstDay = _firstDayNumber(firstDaySetting);
    final weekStart = _startOfWeek(DateTime.now(), firstDay: firstDay)
        .add(Duration(days: 7 * _weekOffset));

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
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
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
                                    'Week of ${DateFormat('MMM d').format(weekStart)}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          color: AppColors.content,
                                          fontWeight: FontWeight.w600,
                                        ),
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
                                    : DateFormat('yyyy').format(weekStart),
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

              // Unified "Your Week" summary — one card that adapts to state:
              //   no plan / no big rocks → "Plan your big rocks" CTA
              //   plan + rocks → intent + rocks summary + edit pencil
              //   past week → read-only intent card
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                  child: planAsync.when(
                    loading: () => const _WeekSummaryCardSkeleton(),
                    error: (_, __) => const _WeekSummaryCardSkeleton(),
                    data: (plan) => _WeekSummaryCard(
                      plan: plan,
                      isCurrentWeek: isCurrentWeek,
                    ),
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
                      if (isCurrentWeek && sub.isPro)
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
                            days: _weekDays(weekStart),
                            tasks: const [],
                            selectedDay: _selectedDay,
                            onDayTap: (day) =>
                                setState(() => _selectedDay = day),
                          )
                        : _WeekDaySelectorLoader(
                            plan: plan,
                            days: _weekDays(weekStart),
                            selectedDay: _selectedDay,
                            onDayTap: (day) =>
                                setState(() => _selectedDay = day),
                          ),
                    orElse: () => _DaySelector(
                      days: _weekDays(weekStart),
                      tasks: const [],
                      selectedDay: _selectedDay,
                      onDayTap: (day) => setState(() => _selectedDay = day),
                    ),
                  ),
                ),
              ),

              // Selected day header + add button
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 14, 16, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          DateFormat('EEEE').format(_selectedDay),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: AppColors.content),
                        ),
                      ),
                      if (planAsync.valueOrNull != null &&
                          !_selectedDay.isBefore(DateTime(
                          DateTime.now().year,
                          DateTime.now().month,
                          DateTime.now().day)))
                        IconButton(
                          onPressed: () => _showAddTask(
                              context, ref, planAsync.valueOrNull),
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

              // Tasks for selected day
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
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

  static const _allDayLabels = {
    DateTime.monday: 'M',
    DateTime.tuesday: 'T',
    DateTime.wednesday: 'W',
    DateTime.thursday: 'T',
    DateTime.friday: 'F',
    DateTime.saturday: 'S',
    DateTime.sunday: 'S',
  };

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
                    _allDayLabels[day.weekday] ?? '',
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
            allTasks.where((t) => _isSameDay(t.date, selectedDay)).toList()
              ..sort((a, b) {
                if (a.startTime == null && b.startTime == null) {
                  return a.createdAt.compareTo(b.createdAt);
                }
                if (a.startTime == null) return 1;
                if (b.startTime == null) return -1;
                return a.startTime!.compareTo(b.startTime!);
              });

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (dayTasks.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text(
                  'No tasks yet.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.contentTertiary,
                      ),
                ),
              ),
            ...dayTasks.map((task) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GestureDetector(
                  onTap: () => _showTaskDetail(context, ref, task, planId),
                  onLongPress: () => _showMoveDayPicker(
                      context, ref, task, planId),
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
                        if (task.isBigRock) ...[
                          const Text('🪨',
                              style: TextStyle(fontSize: 14)),
                          const SizedBox(width: 6),
                        ],
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
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Future<void> _toggleTask(WidgetRef ref, String taskId, String planId) async {
    try {
      final api = ref.read(apiServiceProvider);
      await api.patch('/tasks/$taskId/complete');
      ReviewService.recordCompletion();
      ref.invalidate(_weekTasksProvider(planId));
    } catch (_) {
      // Silent fail
    }
  }

  void _showMoveDayPicker(
      BuildContext context, WidgetRef ref, Task task, String planId) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalContext) => _MoveDayPicker(
        task: task,
        firstDayOfWeek: _firstDayNumber(ref.read(firstDayOfWeekProvider)),
        onSelected: (day) async {
          Navigator.of(modalContext).pop();
          try {
            final api = ref.read(apiServiceProvider);
            await api.put('/tasks/${task.id}', data: {
              'date': DateFormat('yyyy-MM-dd').format(day),
            });
            ref.invalidate(_weekTasksProvider(planId));
          } catch (_) {}
        },
      ),
    );
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


// ---------------------------------------------------------------------------
// Create week bottom sheet
// ---------------------------------------------------------------------------

// Add task sheet for week view (matches Today's add task experience)
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Add task sheet for week view
// ---------------------------------------------------------------------------

class _WeekAddTaskSheet extends ConsumerStatefulWidget {
  const _WeekAddTaskSheet({
    required this.planId,
    required this.quarterId,
    required this.date,
    required this.onCreated,
  });

  final String planId;
  final String? quarterId;
  final DateTime date;
  final VoidCallback onCreated;

  @override
  ConsumerState<_WeekAddTaskSheet> createState() => _WeekAddTaskSheetState();
}

class _WeekAddTaskSheetState extends ConsumerState<_WeekAddTaskSheet> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _loading = false;
  String? _goalName;

  @override
  void initState() {
    super.initState();
    // Resolve goal name from quarterId
    if (widget.quarterId != null) {
      ref.listenManual(_weekGoalsProvider, (_, next) {
        next.whenData((goals) {
          final match = goals.where((g) => g.id == widget.quarterId);
          if (match.isNotEmpty && mounted) {
            setState(() => _goalName = match.first.title);
          }
        });
      });
    }
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
      final api = ref.read(apiServiceProvider);
      String? startStr;
      String? endStr;
      if (_startTime != null) {
        startStr =
            '${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}:00';
      }
      if (_endTime != null) {
        endStr =
            '${_endTime!.hour.toString().padLeft(2, '0')}:${_endTime!.minute.toString().padLeft(2, '0')}:00';
      }
      await api.post('/tasks', data: {
        'weekly_plan_id': widget.planId,
        'title': title,
        'date': DateFormat('yyyy-MM-dd').format(widget.date),
        'energy_type': 'deep',
        if (_descCtrl.text.trim().isNotEmpty)
          'description': _descCtrl.text.trim(),
        if (startStr != null) 'start_time': startStr,
        if (endStr != null) 'end_time': endStr,
      });
      widget.onCreated();
      ReviewService.recordMinorAction();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatTimeOfDay(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final p = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $p';
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    final sheetHeight = bottomInset > 0
        ? screenHeight * 0.85
        : screenHeight * 0.6;
    final dayLabel = DateFormat('EEEE, MMM d').format(widget.date);

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: sheetHeight,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: bottomInset > 0
                ? 0
                : MediaQuery.of(context).padding.bottom,
          ),
        child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Goal chip
                if (_goalName != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
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
                              _goalName!,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: AppColors.kiwi600,
                                    fontWeight: FontWeight.w500,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Date label
                Row(
                  children: [
                    const Icon(Icons.calendar_today,
                        size: 14, color: AppColors.contentSecondary),
                    const SizedBox(width: 6),
                    Text(
                      dayLabel,
                      style:
                          Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppColors.content,
                                fontWeight: FontWeight.w500,
                              ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: _startTime ?? TimeOfDay.now(),
                          helpText: 'Start time',
                        );
                        if (picked != null) {
                          setState(() => _startTime = picked);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: AppColors.surfaceAlt,
                        ),
                        child: Text(
                          _startTime != null
                              ? _formatTimeOfDay(_startTime!)
                              : 'Start',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                color: _startTime != null
                                    ? AppColors.content
                                    : AppColors.contentTertiary,
                              ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text('–',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.contentTertiary)),
                    ),
                    GestureDetector(
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: _endTime ??
                              _startTime?.replacing(
                                      hour:
                                          (_startTime!.hour + 1) % 24) ??
                              TimeOfDay.now(),
                          helpText: 'End time',
                        );
                        if (picked != null) {
                          setState(() => _endTime = picked);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: AppColors.surfaceAlt,
                        ),
                        child: Text(
                          _endTime != null
                              ? _formatTimeOfDay(_endTime!)
                              : 'End',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                color: _endTime != null
                                    ? AppColors.content
                                    : AppColors.contentTertiary,
                              ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Title
                TextField(
                  controller: _titleCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.content,
                        fontWeight: FontWeight.w600,
                      ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    hintText: 'What do you need to focus on?',
                    hintStyle:
                        Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: AppColors.contentTertiary,
                              fontWeight: FontWeight.w400,
                            ),
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                  ),
                  maxLines: null,
                ),

                const SizedBox(height: 12),

                // Description
                TextField(
                  controller: _descCtrl,
                  maxLines: null,
                  minLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.content,
                        height: 1.5,
                      ),
                  decoration: InputDecoration(
                    hintText:
                        'What\u2019s the deliverable? e.g. "Draft v1 of proposal"',
                    hintStyle:
                        Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.contentTertiary,
                            ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
          ),
          // Toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              border: Border(
                top: BorderSide(color: AppColors.borderSubtle, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => FocusScope.of(context).unfocus(),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.keyboard_hide_outlined,
                        size: 22, color: AppColors.contentSecondary),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _loading ? null : _submit,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppColors.kiwi400,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _loading
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check,
                            size: 20, color: Colors.white),
                  ),
                ),
              ],
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

// ---------------------------------------------------------------------------
// Move-day picker: swipeable PageView of weeks. Shows the current week first
// and lets the user swipe right for future weeks, or left for past weeks.
// ---------------------------------------------------------------------------

class _MoveDayPicker extends StatefulWidget {
  const _MoveDayPicker({
    required this.task,
    required this.firstDayOfWeek,
    required this.onSelected,
  });

  final Task task;
  final int firstDayOfWeek;
  final ValueChanged<DateTime> onSelected;

  @override
  State<_MoveDayPicker> createState() => _MoveDayPickerState();
}

class _MoveDayPickerState extends State<_MoveDayPicker> {
  // Page 0 = current week. Allow 8 weeks back and 26 weeks (~6 months) forward
  // so the user can move a task anywhere within a planning horizon.
  static const _weeksBack = 8;
  static const _weeksForward = 26;
  static const _totalPages = _weeksBack + _weeksForward + 1;

  late final PageController _pageController;
  late final DateTime _todayWeekStart;
  int _currentPage = _weeksBack;

  @override
  void initState() {
    super.initState();
    _todayWeekStart =
        _startOfWeek(DateTime.now(), firstDay: widget.firstDayOfWeek);
    // Start on the page containing the task's current date.
    final taskWeekStart =
        _startOfWeek(widget.task.date, firstDay: widget.firstDayOfWeek);
    final diffDays = taskWeekStart.difference(_todayWeekStart).inDays;
    final weeksFromToday = (diffDays / 7).round();
    final initialPage =
        (_weeksBack + weeksFromToday).clamp(0, _totalPages - 1);
    _currentPage = initialPage;
    _pageController = PageController(initialPage: initialPage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  DateTime _weekStartForPage(int page) =>
      _todayWeekStart.add(Duration(days: (page - _weeksBack) * 7));

  String _weekLabel(DateTime weekStart) {
    final weeksFromToday =
        weekStart.difference(_todayWeekStart).inDays ~/ 7;
    if (weeksFromToday == 0) return 'This week';
    if (weeksFromToday == 1) return 'Next week';
    if (weeksFromToday == -1) return 'Last week';
    final weekEnd = weekStart.add(const Duration(days: 6));
    final sameMonth = weekStart.month == weekEnd.month;
    if (sameMonth) {
      return '${DateFormat('MMM').format(weekStart)} ${weekStart.day}–${weekEnd.day}';
    }
    return '${DateFormat('MMM d').format(weekStart)} – ${DateFormat('MMM d').format(weekEnd)}';
  }

  @override
  Widget build(BuildContext context) {
    final visibleWeekStart = _weekStartForPage(_currentPage);
    final canSwipeLeft = _currentPage > 0;
    final canSwipeRight = _currentPage < _totalPages - 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Move to...',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.content,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.task.title,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.contentSecondary,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 16),
          // Week label + arrows
          Row(
            children: [
              IconButton(
                onPressed: canSwipeLeft
                    ? () => _pageController.previousPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        )
                    : null,
                icon: const Icon(Icons.chevron_left, size: 20),
                color: AppColors.contentSecondary,
                disabledColor: AppColors.contentTertiary.withValues(alpha: 0.3),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    _weekLabel(visibleWeekStart),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.contentSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ),
              IconButton(
                onPressed: canSwipeRight
                    ? () => _pageController.nextPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        )
                    : null,
                icon: const Icon(Icons.chevron_right, size: 20),
                color: AppColors.contentSecondary,
                disabledColor: AppColors.contentTertiary.withValues(alpha: 0.3),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 64,
            child: PageView.builder(
              controller: _pageController,
              itemCount: _totalPages,
              onPageChanged: (page) => setState(() => _currentPage = page),
              itemBuilder: (context, page) {
                final weekStart = _weekStartForPage(page);
                final days = List.generate(
                    7, (i) => weekStart.add(Duration(days: i)));
                return _WeekRow(
                  days: days,
                  taskDate: widget.task.date,
                  onSelected: widget.onSelected,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekRow extends StatelessWidget {
  const _WeekRow({
    required this.days,
    required this.taskDate,
    required this.onSelected,
  });

  final List<DateTime> days;
  final DateTime taskDate;
  final ValueChanged<DateTime> onSelected;

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return Row(
      children: days.map((day) {
        final isCurrentDay = _sameDay(day, taskDate);
        final isToday = _sameDay(day, today);
        // Use the day's actual weekday (Mon=1..Sun=7) for the label, so the
        // letter under each date is always correct regardless of how the
        // week starts (Mon vs Sun).
        const dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
        final dayIndex = day.weekday - 1;
        return Expanded(
          child: GestureDetector(
            onTap: isCurrentDay ? null : () => onSelected(day),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isCurrentDay
                    ? AppColors.kiwi400
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: isToday && !isCurrentDay
                    ? Border.all(color: AppColors.kiwi300, width: 1.5)
                    : null,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    dayLabels[dayIndex],
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: isCurrentDay
                              ? Colors.white
                              : AppColors.contentTertiary,
                          fontSize: 10,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${day.day}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isCurrentDay
                              ? Colors.white
                              : AppColors.content,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// _WeekSummaryCard — unified "Your Week" surface
//
// Replaces the old intent card + planning banner + empty state. Has two
// visual states:
//
//   1. Empty state (no plan or no big rocks): "🪨 Plan your big rocks" CTA
//      that opens the wizard at Step 1.
//   2. Filled state (plan exists + ≥1 big rock): shows the intent, up to 3
//      big rocks as chips, and a progress bar. An edit pencil deep-links
//      to the wizard's intent step for typo fixes.
//
// Past weeks (when `!isCurrentWeek`) render the existing read-only card.
// ---------------------------------------------------------------------------

class _WeekSummaryCard extends ConsumerWidget {
  const _WeekSummaryCard({required this.plan, required this.isCurrentWeek});

  final WeeklyPlan? plan;
  final bool isCurrentWeek;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Past weeks → keep the existing read-only treatment.
    if (!isCurrentWeek && plan != null) {
      return _IntentCardReadOnly(plan: plan!);
    }

    // Current week with no plan at all → empty state. Tapping kicks off the
    // wizard, which creates the plan transparently via _ensureWeeklyPlan.
    if (plan == null) {
      return _PlanWeekCta(
        onTap: () => context.push('/week/plan'),
      );
    }

    final tasksAsync = ref.watch(_weekTasksProvider(plan!.id));
    return tasksAsync.maybeWhen(
      data: (tasks) {
        final bigRocks = tasks.where((t) => t.isBigRock).toList();
        if (bigRocks.isEmpty) {
          return _PlanWeekCta(
            onTap: () => context.push('/week/plan'),
          );
        }
        return _WeekSummaryFilled(
          plan: plan!,
          bigRocks: bigRocks,
        );
      },
      orElse: () => _WeekSummaryFilled(
        plan: plan!,
        bigRocks: const [],
      ),
    );
  }
}

class _PlanWeekCta extends StatelessWidget {
  const _PlanWeekCta({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.kiwi50,
              AppColors.kiwi100.withValues(alpha: 0.6),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.kiwi200),
        ),
        child: Row(
          children: [
            const Text('🪨', style: TextStyle(fontSize: 28)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Plan your big rocks',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppColors.content,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'The one most important thing for each goal this week.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.contentSecondary,
                          height: 1.3,
                        ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 22, color: AppColors.kiwi500),
          ],
        ),
      ),
    );
  }
}

class _WeekSummaryFilled extends StatelessWidget {
  const _WeekSummaryFilled({
    required this.plan,
    required this.bigRocks,
  });

  final WeeklyPlan plan;
  final List<Task> bigRocks;

  @override
  Widget build(BuildContext context) {
    final intentText = plan.intent.trim();
    // Hide the onboarding placeholder so we don't display literal scaffolding
    // text to the user. They'll see "Set a weekly intent" hint instead.
    final showIntent = intentText.isNotEmpty &&
        intentText != 'Plan your big rocks for the week';

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 12, 16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label row with the edit pencil deep-linking to wizard Step 3.
          Row(
            children: [
              Text(
                'THIS WEEK',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.kiwi700,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => context.push('/week/plan?step=2'),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.edit_outlined,
                    size: 18,
                    color: AppColors.kiwi600.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Intent text (or hint when blank). Tapping opens the wizard too.
          GestureDetector(
            onTap: () => context.push('/week/plan?step=2'),
            child: Text(
              showIntent ? intentText : 'Set a weekly intent →',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: showIntent
                        ? AppColors.content
                        : AppColors.contentTertiary,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
            ),
          ),
          if (bigRocks.isNotEmpty) ...[
            const SizedBox(height: 12),
            _BigRockChips(rocks: bigRocks),
          ],
          const SizedBox(height: 14),
          ProgressBar(percent: plan.progressPercent),
        ],
      ),
    );
  }
}

class _BigRockChips extends StatelessWidget {
  const _BigRockChips({required this.rocks});
  final List<Task> rocks;

  @override
  Widget build(BuildContext context) {
    // Show up to 3 chips; collapse the rest into "+N".
    const maxVisible = 3;
    final visible = rocks.take(maxVisible).toList();
    final overflow = rocks.length - visible.length;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final t in visible) _RockChip(label: t.title),
        if (overflow > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.kiwi100.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '+$overflow more',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.kiwi700,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
      ],
    );
  }
}

class _RockChip extends StatelessWidget {
  const _RockChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: AppColors.kiwi200.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🪨', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.content,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekSummaryCardSkeleton extends StatelessWidget {
  const _WeekSummaryCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.kiwi50,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 10,
            width: 70,
            decoration: BoxDecoration(
              color: AppColors.borderSubtle,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            height: 16,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.borderSubtle,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 14),
          const ProgressBar(percent: 0),
        ],
      ),
    );
  }
}
