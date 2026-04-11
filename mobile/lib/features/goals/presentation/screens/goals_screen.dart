// GoalsScreen - "Where am I heading?"
// Usage: Registered as /goals route inside AppShell's ShellRoute.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/kinwii_card.dart';
import '../../../../core/widgets/progress_bar.dart';
import '../../../../models/quarterly_goal.dart';
import '../../../../features/auth/presentation/screens/login_screen.dart';
import '../../../../services/subscription_service.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final _goalsProvider =
    StateNotifierProvider.autoDispose<_GoalsNotifier, AsyncValue<List<QuarterlyGoal>>>(
  (ref) => _GoalsNotifier(ref),
);

class _GoalsNotifier
    extends StateNotifier<AsyncValue<List<QuarterlyGoal>>> {
  _GoalsNotifier(this._ref) : super(const AsyncValue.loading()) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    state = const AsyncValue.loading();
    try {
      final api = _ref.read(apiServiceProvider);
      final response = await api.get('/goals');
      final list = (response.data as List<dynamic>)
          .map((e) => QuarterlyGoal.fromJson(e as Map<String, dynamic>))
          .toList();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> addGoal({
    required String title,
    required String why,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final api = _ref.read(apiServiceProvider);
    final response = await api.post('/goals', data: {
      'title': title,
      'why': why,
      'start_date': DateFormat('yyyy-MM-dd').format(startDate),
      'end_date': DateFormat('yyyy-MM-dd').format(endDate),
    });
    final newGoal =
        QuarterlyGoal.fromJson(response.data as Map<String, dynamic>);
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data([...current, newGoal]);
  }

  Future<void> refresh() => _load();
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goalsAsync = ref.watch(_goalsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.kiwi400,
          onRefresh: () async {
            await ref.read(_goalsProvider.notifier).refresh();
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 16, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Goals',
                          style: Theme.of(context)
                              .textTheme
                              .headlineLarge
                              ?.copyWith(color: AppColors.content),
                        ),
                      ),
                      IconButton(
                        onPressed: () => context.push('/analytics'),
                        icon: const Icon(
                          Icons.insights_outlined,
                          color: AppColors.kiwi500,
                          size: 22,
                        ),
                        tooltip: 'Progress',
                      ),
                      IconButton(
                        onPressed: () => _showCreateGoalSheet(context, ref),
                        icon: const Icon(
                          Icons.add_circle_outline,
                          color: AppColors.kiwi500,
                          size: 28,
                        ),
                        tooltip: 'Add goal',
                      ),
                    ],
                  ),
                ),
              ),

              // Goal list / empty / error
              goalsAsync.when(
                loading: () => const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.kiwi400),
                  ),
                ),
                error: (_, __) => const SliverFillRemaining(
                  child: EmptyState(
                    message: 'Could not load goals. Pull to refresh.',
                  ),
                ),
                data: (goals) {
                  if (goals.isEmpty) {
                    return SliverFillRemaining(
                      child: EmptyState(
                        message: 'Set your first goal and give your quarter direction.',
                        actionLabel: 'Set your first goal',
                        onAction: () => _showCreateGoalSheet(context, ref),
                      ),
                    );
                  }
                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
                    sliver: SliverList.separated(
                      itemCount: goals.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) => _GoalCard(
                        goal: goals[index],
                        onTap: () {
                          context.push('/goals/${goals[index].id}').then((_) {
                            ref.read(_goalsProvider.notifier).refresh();
                          });
                        },
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateGoalSheet(BuildContext context, WidgetRef ref) {
    final sub = ref.read(subscriptionProvider);
    final goals = ref.read(_goalsProvider).valueOrNull ?? [];
    if (!sub.isPro && goals.isNotEmpty) {
      context.push('/pro');
      return;
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
      builder: (_) => _CreateGoalSheet(
        notifier: ref.read(_goalsProvider.notifier),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// Goal card
// ---------------------------------------------------------------------------

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal, required this.onTap});

  final QuarterlyGoal goal;
  final VoidCallback onTap;

  String _quarterLabel(DateTime start, DateTime end) {
    final startQ = ((start.month - 1) ~/ 3) + 1;
    final endQ = ((end.month - 1) ~/ 3) + 1;
    final q = startQ == endQ ? 'Q$startQ' : 'Q$startQ–Q$endQ';
    return '$q ${start.year}';
  }

  int _weeksRemaining(DateTime end) {
    final now = DateTime.now();
    final diff = end.difference(now).inDays;
    return (diff / 7).ceil().clamp(0, 999);
  }

  @override
  Widget build(BuildContext context) {
    final weeksLeft = _weeksRemaining(goal.endDate);
    return KinwiiCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.kiwi100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _quarterLabel(goal.startDate, goal.endDate),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.kiwi700,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              if (goal.roleName != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.energyCreative,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    goal.roleName!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF7C3AED),
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
              const Spacer(),
              Text(
                weeksLeft == 0
                    ? 'Ended'
                    : '$weeksLeft wk${weeksLeft == 1 ? '' : 's'} left',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.contentTertiary,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            goal.title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.content,
                ),
          ),
          if (goal.why != null && goal.why!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              goal.why!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.contentSecondary,
                  ),
            ),
          ],
          const SizedBox(height: 12),
          ProgressBar(percent: goal.progressPercent),
          const SizedBox(height: 6),
          Text(
            '${goal.progressPercent}% complete',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.contentSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Create goal sheet — unified layout matching goal detail view
// ---------------------------------------------------------------------------

class _CreateGoalSheet extends ConsumerStatefulWidget {
  const _CreateGoalSheet({required this.notifier});

  final _GoalsNotifier notifier;

  @override
  ConsumerState<_CreateGoalSheet> createState() => _CreateGoalSheetState();
}

class _CreateGoalSheetState extends ConsumerState<_CreateGoalSheet> {
  final _titleCtrl = TextEditingController();
  final _whyCtrl = TextEditingController();
  DateTime _startDate = _currentQuarterStart();
  DateTime _endDate = _currentQuarterEnd();
  bool _loading = false;
  bool _whyExpanded = false;
  String? _error;

  static DateTime _currentQuarterStart() {
    final now = DateTime.now();
    final q = ((now.month - 1) ~/ 3);
    return DateTime(now.year, q * 3 + 1, 1);
  }

  static DateTime _currentQuarterEnd() {
    final start = _currentQuarterStart();
    final endMonth = start.month + 2;
    final lastDay = DateTime(start.year, endMonth + 1, 0).day;
    return DateTime(start.year, endMonth, lastDay);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _whyCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    if (title.length < 5) {
      setState(() => _error = 'Goal title must be at least 5 characters.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.notifier.addGoal(
        title: title,
        why: _whyCtrl.text.trim(),
        startDate: _startDate,
        endDate: _endDate,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Failed to create goal. Please try again.';
        });
      }
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.kiwi400),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate.isBefore(_startDate)) _endDate = _startDate;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    return SizedBox(
      height: screenHeight * 0.6,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 20, 24, 20 + bottomPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Dates row (compact, at top like task detail's date/time row)
            Row(
              children: [
                const Icon(Icons.calendar_today,
                    size: 14, color: AppColors.contentSecondary),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => _pickDate(isStart: true),
                  child: Text(
                    DateFormat('MMM d').format(_startDate),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.content,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
                Text(' – ',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.contentTertiary,
                        )),
                GestureDetector(
                  onTap: () => _pickDate(isStart: false),
                  child: Text(
                    DateFormat('MMM d, yyyy').format(_endDate),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.content,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Title (borderless, matching task creation)
            TextField(
              controller: _titleCtrl,
              autofocus: true,
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
                hintText: 'What\'s your goal?',
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
              maxLines: null,
            ),

            const SizedBox(height: 16),

            // Why (tappable to expand, matching task description)
            if (!_whyExpanded)
              GestureDetector(
                onTap: () => setState(() => _whyExpanded = true),
                child: Text(
                  _whyCtrl.text.isNotEmpty
                      ? _whyCtrl.text
                      : 'Why does this matter?',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _whyCtrl.text.isNotEmpty
                            ? AppColors.contentSecondary
                            : AppColors.contentTertiary,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

            if (_whyExpanded)
              TextField(
                controller: _whyCtrl,
                autofocus: true,
                maxLines: 3,
                minLines: 2,
                textCapitalization: TextCapitalization.sentences,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.content,
                    ),
                decoration: InputDecoration(
                  hintText: 'e.g. Prove the concept and get first customers',
                  hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.contentTertiary,
                      ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
              ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],

            const SizedBox(height: 32),
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
                    : const Text('Create goal'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
