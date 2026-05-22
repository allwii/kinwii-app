// WeeklyPlanWizardScreen — 3-step "Big Rocks" weekly planning wizard.
//
// Step 1: Intro + active-goal preview
// Step 2: Per-goal big rock + day chip
// Step 3: Review summary + editable weekly intent + commit
//
// Reuses the chrome pattern from weekly_review_screen.dart.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../models/quarterly_goal.dart';
import '../../../../services/providers.dart';
import '../../../../services/subscription_service.dart';
import '../../../settings/presentation/screens/settings_screen.dart'
    show firstDayOfWeekProvider;

class WeeklyPlanWizardScreen extends ConsumerStatefulWidget {
  const WeeklyPlanWizardScreen({
    super.key,
    this.firstTime = false,
    this.initialStep = 0,
  });

  /// When true, the wizard auto-fills AI suggestions on Step 2 entry and
  /// navigates to /today on completion. Otherwise navigates to /week.
  final bool firstTime;

  /// Starting step (0–2). The Week screen pencil deep-links to Step 3 (index 2)
  /// for quick intent edits while still loading big rocks for context.
  final int initialStep;

  @override
  ConsumerState<WeeklyPlanWizardScreen> createState() =>
      _WeeklyPlanWizardScreenState();
}

class _WeeklyPlanWizardScreenState
    extends ConsumerState<WeeklyPlanWizardScreen> {
  final _pageController = PageController();
  int _currentStep = 0;

  bool _isLoading = true;
  String? _loadError;

  // Loaded data
  List<QuarterlyGoal> _activeGoals = [];
  String? _weeklyPlanId;
  DateTime _weekStart = DateTime.now();
  final _intentCtrl = TextEditingController();

  // Per-goal user input: goalId -> {title, date, suggesting?}
  final Map<String, TextEditingController> _rockCtrls = {};
  final Map<String, DateTime> _rockDays = {};
  final Set<String> _suggesting = {};
  // goalId -> existing task id (for "edit" instead of "duplicate" on commit)
  final Map<String, String> _rockTaskIds = {};

  bool _autofilled = false;
  bool _isCommitting = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _intentCtrl.dispose();
    for (final c in _rockCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  int _firstDayNumber(String setting) {
    switch (setting) {
      case 'Sunday':
        return DateTime.sunday;
      case 'Saturday':
        return DateTime.saturday;
      default:
        return DateTime.monday;
    }
  }

  DateTime _startOfWeek(DateTime date, {int firstDay = DateTime.monday}) {
    int diff = (date.weekday - firstDay) % 7;
    return DateTime(date.year, date.month, date.day - diff);
  }

  Future<void> _loadData() async {
    try {
      final api = ref.read(apiServiceProvider);
      final fd = _firstDayNumber(ref.read(firstDayOfWeekProvider));
      _weekStart = _startOfWeek(DateTime.now(), firstDay: fd);

      // Load active goals
      final goalsResp = await api.get('/goals');
      final goals = (goalsResp.data as List)
          .map((g) => QuarterlyGoal.fromJson(g as Map<String, dynamic>))
          .toList();
      final today = DateTime.now();
      final active = goals
          .where((g) =>
              g.endDate.isAfter(today.subtract(const Duration(days: 1))))
          .toList();

      // Resolve / create the current weekly plan
      String? planId;
      try {
        final wkResp = await api.get('/week/current');
        if (wkResp.data != null) {
          planId = wkResp.data['id'] as String?;
          // Preload existing intent so reopening the wizard edits, not
          // resets, what the user already wrote.
          final existingIntent = wkResp.data['intent'] as String?;
          if (existingIntent != null &&
              existingIntent.trim().isNotEmpty &&
              // Treat the onboarding placeholder as "no intent yet" so the
              // wizard's auto-derivation from big rocks still kicks in.
              existingIntent.trim() != 'Plan your big rocks for the week') {
            _intentCtrl.text = existingIntent;
          }
        }
      } catch (_) {
        // 404 is fine; we'll create one below if needed.
      }

      // Initialize controllers per goal. Pre-fill rock day to the first
      // weekday of the visible week (today or next Monday if weekend done).
      final defaultDay = today.isBefore(_weekStart.add(const Duration(days: 7)))
          ? today
          : _weekStart;
      for (final g in active) {
        _rockCtrls[g.id] = TextEditingController();
        _rockDays[g.id] = defaultDay;
      }

      // Preload any existing big rocks for this week so users can edit
      // instead of duplicating.
      if (planId != null) {
        try {
          final tasksResp = await api
              .get('/tasks', queryParameters: {'weekly_plan_id': planId});
          final tasks = tasksResp.data as List;
          for (final raw in tasks) {
            final t = raw as Map<String, dynamic>;
            final qid = t['quarter_id'] as String?;
            final energy = t['energy_type'] as String?;
            if (qid == null || energy != 'deep') continue;
            if (!_rockCtrls.containsKey(qid)) continue;
            // Use the first matching big rock for the goal as the editable one.
            if (_rockCtrls[qid]!.text.isEmpty) {
              _rockCtrls[qid]!.text = t['title'] as String? ?? '';
              final dateStr = t['date'] as String?;
              if (dateStr != null) {
                _rockDays[qid] = DateTime.parse(dateStr);
              }
              final tid = t['id'] as String?;
              if (tid != null) _rockTaskIds[qid] = tid;
            }
          }
        } catch (_) {
          // Non-fatal — proceed with blank fields
        }
      }

      if (!mounted) return;
      setState(() {
        _activeGoals = active;
        _weeklyPlanId = planId;
        _isLoading = false;
      });

      // Honor an initialStep deep-link (e.g., pencil → Step 3 for intent edit).
      // Wait one frame so the PageController is attached before we jump.
      if (widget.initialStep > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _goToStep(widget.initialStep.clamp(0, 2));
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Could not load your goals. Pull to retry.';
      });
    }
  }

  void _goToStep(int step) {
    if (step < 0 || step > 2) return;
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    setState(() => _currentStep = step);

    // On entering Step 2 for first-time users, auto-fill AI suggestions for
    // empty rock fields. Runs once.
    if (step == 1 &&
        widget.firstTime &&
        !_autofilled &&
        _activeGoals.isNotEmpty) {
      _autofilled = true;
      _autofillSuggestions();
    }

    // Pre-fill the intent on Step 3 entry if user hasn't edited it.
    if (step == 2 && _intentCtrl.text.trim().isEmpty) {
      final filled = _rockCtrls.entries
          .where((e) => e.value.text.trim().isNotEmpty)
          .map((e) => e.value.text.trim())
          .toList();
      if (filled.isNotEmpty) {
        _intentCtrl.text = 'This week: ${filled.join(', ')}';
      }
    }
  }

  Future<void> _autofillSuggestions() async {
    final futures = <Future<void>>[];
    for (final g in _activeGoals) {
      if (_rockCtrls[g.id]!.text.trim().isNotEmpty) continue;
      futures.add(_suggestForGoal(g.id, silent: true));
    }
    await Future.wait(futures);
  }

  Future<void> _suggestForGoal(String goalId, {bool silent = false}) async {
    if (_suggesting.contains(goalId)) return;
    setState(() => _suggesting.add(goalId));
    try {
      final api = ref.read(apiServiceProvider);
      final resp = await api.post('/ai/suggest-intent', data: {
        'goal_id': goalId,
      });
      final suggestion = resp.data['suggested_intent'] as String?;
      if (mounted && suggestion != null && suggestion.trim().isNotEmpty) {
        _rockCtrls[goalId]!.text = suggestion.trim();
      }
    } catch (_) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't suggest right now."),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _suggesting.remove(goalId));
    }
  }

  Future<void> _skip() async {
    // Set a Hive flag so the Week banner still appears (signals: not planned).
    final box = await Hive.openBox('kinwii_flags');
    await box.put(
        'week_plan_skipped_${DateFormat('yyyy-MM-dd').format(_weekStart)}',
        true);
    if (mounted) context.go('/today');
  }

  Future<String?> _ensureWeeklyPlan() async {
    if (_weeklyPlanId != null) return _weeklyPlanId;
    try {
      final api = ref.read(apiServiceProvider);
      final quarterId =
          _activeGoals.isNotEmpty ? _activeGoals.first.id : null;
      final resp = await api.post('/week', data: {
        if (quarterId != null) 'quarter_id': quarterId,
        'week_start_date': DateFormat('yyyy-MM-dd').format(_weekStart),
        'intent': 'Plan your big rocks for the week',
      });
      final planId = resp.data['id'] as String;
      _weeklyPlanId = planId;
      return planId;
    } catch (_) {
      return null;
    }
  }

  Future<void> _commit() async {
    setState(() => _isCommitting = true);
    try {
      final planId = await _ensureWeeklyPlan();
      if (planId == null) throw Exception('No plan');

      final api = ref.read(apiServiceProvider);

      // Upsert one big rock per filled goal: PUT if we loaded an existing
      // task for this goal, POST otherwise. Prevents duplicates on reopen.
      for (final goal in _activeGoals) {
        final title = _rockCtrls[goal.id]!.text.trim();
        if (title.isEmpty) continue;
        final day = _rockDays[goal.id] ?? _weekStart;
        final existingId = _rockTaskIds[goal.id];
        try {
          if (existingId != null) {
            await api.put('/tasks/$existingId', data: {
              'title': title,
              'date': DateFormat('yyyy-MM-dd').format(day),
              'energy_type': 'deep',
              'quarter_id': goal.id,
            });
          } else {
            await api.post('/tasks', data: {
              'weekly_plan_id': planId,
              'title': title,
              'date': DateFormat('yyyy-MM-dd').format(day),
              'energy_type': 'deep',
              'quarter_id': goal.id,
            });
          }
        } catch (_) {
          // Skip individual failures
        }
      }

      // Update the weekly intent
      final intent = _intentCtrl.text.trim();
      if (intent.isNotEmpty) {
        try {
          await api.put('/week/$planId', data: {'intent': intent});
        } catch (_) {}
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🪨 Your week is set.'),
          duration: Duration(seconds: 2),
        ),
      );
      context.go(widget.firstTime ? '/today' : '/week');
    } catch (_) {
      if (!mounted) return;
      setState(() => _isCommitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong. Please try again.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  bool get _hasAtLeastOneRock => _rockCtrls.values
      .any((c) => c.text.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            _currentStep > 0 ? Icons.arrow_back_ios_new : Icons.close,
            color: AppColors.content,
            size: _currentStep > 0 ? 18 : 24,
          ),
          onPressed: _currentStep > 0
              ? () => _goToStep(_currentStep - 1)
              : () => context.pop(),
        ),
        title: Text(
          widget.firstTime ? 'Plan your first week' : 'Plan your week',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(color: AppColors.content),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: _StepIndicator(current: _currentStep, total: 3),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.kiwi400))
          : _loadError != null
              ? Center(child: Text(_loadError!))
              : _activeGoals.isEmpty
                  ? _NoGoalsState(onCreate: () => context.push('/goals'))
                  : PageView(
                      controller: _pageController,
                      physics: const NeverScrollableScrollPhysics(),
                      onPageChanged: (i) =>
                          setState(() => _currentStep = i),
                      children: [
                        _IntroStep(
                          goals: _activeGoals,
                          firstTime: widget.firstTime,
                          onContinue: () => _goToStep(1),
                          onSkip: widget.firstTime ? _skip : null,
                        ),
                        _BigRocksStep(
                          goals: _activeGoals,
                          rockCtrls: _rockCtrls,
                          rockDays: _rockDays,
                          weekStart: _weekStart,
                          firstDayOfWeek: _firstDayNumber(
                              ref.watch(firstDayOfWeekProvider)),
                          suggesting: _suggesting,
                          isPro: ref.watch(subscriptionProvider).isPro,
                          onSuggest: (goalId) => _suggestForGoal(goalId),
                          onPickDay: (goalId, day) =>
                              setState(() => _rockDays[goalId] = day),
                          onContinue: _hasAtLeastOneRock
                              ? () => _goToStep(2)
                              : null,
                          onChanged: () => setState(() {}),
                        ),
                        _ReviewStep(
                          goals: _activeGoals,
                          rockCtrls: _rockCtrls,
                          rockDays: _rockDays,
                          intentCtrl: _intentCtrl,
                          isCommitting: _isCommitting,
                          onCommit: _commit,
                          // Editing mode when existing big rocks were preloaded
                          // — the commit button reads "Save changes" instead
                          // of "Create my week".
                          isEditing: _rockTaskIds.isNotEmpty,
                        ),
                      ],
                    ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step indicator (4px segmented bar)
// ---------------------------------------------------------------------------

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.current, required this.total});
  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(total, (i) {
        return Expanded(
          child: Container(
            height: 4,
            margin: EdgeInsets.only(right: i < total - 1 ? 2 : 0),
            decoration: BoxDecoration(
              color: i <= current ? AppColors.kiwi400 : AppColors.borderSubtle,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// No-goals empty state
// ---------------------------------------------------------------------------

class _NoGoalsState extends StatelessWidget {
  const _NoGoalsState({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎯', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(
              'Set a goal first',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.content,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Big rocks anchor to goals. Add one and come back.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.contentSecondary,
                  ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: onCreate,
              child: const Text('Create a goal'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 1: Intro
// ---------------------------------------------------------------------------

class _IntroStep extends StatelessWidget {
  const _IntroStep({
    required this.goals,
    required this.firstTime,
    required this.onContinue,
    this.onSkip,
  });

  final List<QuarterlyGoal> goals;
  final bool firstTime;
  final VoidCallback onContinue;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🪨', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            Text(
              firstTime ? 'Set your big rocks' : 'Plan your big rocks',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.content,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              "Pick the single most important thing for each goal this week. "
              'Put your big rocks in first — everything else fits around them.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.contentSecondary,
                    height: 1.5,
                  ),
            ),
            const SizedBox(height: 24),
            Text(
              'YOUR GOALS',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.contentTertiary,
                    letterSpacing: 1.2,
                  ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: goals.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _GoalSummaryCard(goal: goals[i]),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onContinue,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Continue'),
              ),
            ),
            if (onSkip != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: onSkip,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.contentSecondary,
                  ),
                  child: const Text("Skip — I'll plan later"),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GoalSummaryCard extends StatelessWidget {
  const _GoalSummaryCard({required this.goal});
  final QuarterlyGoal goal;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        children: [
          Text(_goalEmoji(goal.title),
              style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              goal.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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

// ---------------------------------------------------------------------------
// Step 2: Per-goal big rock
// ---------------------------------------------------------------------------

class _BigRocksStep extends StatelessWidget {
  const _BigRocksStep({
    required this.goals,
    required this.rockCtrls,
    required this.rockDays,
    required this.weekStart,
    required this.firstDayOfWeek,
    required this.suggesting,
    required this.isPro,
    required this.onSuggest,
    required this.onPickDay,
    required this.onContinue,
    required this.onChanged,
  });

  final List<QuarterlyGoal> goals;
  final Map<String, TextEditingController> rockCtrls;
  final Map<String, DateTime> rockDays;
  final DateTime weekStart;
  final int firstDayOfWeek;
  final Set<String> suggesting;
  final bool isPro;
  final void Function(String goalId) onSuggest;
  final void Function(String goalId, DateTime day) onPickDay;
  final VoidCallback? onContinue;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final orderedDays =
        List.generate(7, (i) => weekStart.add(Duration(days: i)));
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'For each goal, what matters most this week?',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.content,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'One sentence is enough. Then pick the day you\'ll do it.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.contentSecondary,
                  ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                itemCount: goals.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (_, i) {
                  final goal = goals[i];
                  return _BigRockCard(
                    goal: goal,
                    controller: rockCtrls[goal.id]!,
                    selectedDay: rockDays[goal.id] ?? weekStart,
                    days: orderedDays,
                    isSuggesting: suggesting.contains(goal.id),
                    isPro: isPro,
                    onSuggest: () => onSuggest(goal.id),
                    onPickDay: (d) => onPickDay(goal.id, d),
                    onChanged: onChanged,
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onContinue,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BigRockCard extends StatelessWidget {
  const _BigRockCard({
    required this.goal,
    required this.controller,
    required this.selectedDay,
    required this.days,
    required this.isSuggesting,
    required this.isPro,
    required this.onSuggest,
    required this.onPickDay,
    required this.onChanged,
  });

  final QuarterlyGoal goal;
  final TextEditingController controller;
  final DateTime selectedDay;
  final List<DateTime> days;
  final bool isSuggesting;
  final bool isPro;
  final VoidCallback onSuggest;
  final ValueChanged<DateTime> onPickDay;
  final VoidCallback onChanged;

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(_goalEmoji(goal.title),
                  style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  goal.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.content,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              if (isPro)
                GestureDetector(
                  onTap: isSuggesting ? null : onSuggest,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: isSuggesting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.kiwi500),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.auto_awesome,
                                  size: 14, color: AppColors.kiwi500),
                              const SizedBox(width: 4),
                              Text(
                                'Suggest',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: AppColors.kiwi600,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            onChanged: (_) => onChanged(),
            // Auto-expand to fit the content. Most AI suggestions are 1–3
            // sentences; capping at 2 lines hid most of the text behind a tap.
            maxLines: null,
            minLines: 2,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.content,
                  height: 1.4,
                ),
            decoration: InputDecoration(
              hintText: 'The most important thing this week is…',
              hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.contentTertiary,
                  ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.borderSubtle),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.borderSubtle),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                    color: AppColors.kiwi400, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 12),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: days.map((day) {
              final selected = _sameDay(day, selectedDay);
              const dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
              final dayIndex = day.weekday - 1;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onPickDay(day),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.kiwi400
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: selected
                          ? null
                          : Border.all(color: AppColors.borderSubtle),
                    ),
                    child: Column(
                      children: [
                        Text(
                          dayLabels[dayIndex],
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                color: selected
                                    ? Colors.white
                                    : AppColors.contentTertiary,
                                fontSize: 10,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${day.day}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: selected
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
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 3: Review + intent + commit
// ---------------------------------------------------------------------------

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({
    required this.goals,
    required this.rockCtrls,
    required this.rockDays,
    required this.intentCtrl,
    required this.isCommitting,
    required this.onCommit,
    required this.isEditing,
  });

  final List<QuarterlyGoal> goals;
  final Map<String, TextEditingController> rockCtrls;
  final Map<String, DateTime> rockDays;
  final TextEditingController intentCtrl;
  final bool isCommitting;
  final bool isEditing;
  final VoidCallback onCommit;

  @override
  Widget build(BuildContext context) {
    final filled = goals
        .where((g) => (rockCtrls[g.id]?.text.trim().isNotEmpty ?? false))
        .toList();

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your week, at a glance',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.content,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            ...filled.map((g) {
              final day = rockDays[g.id] ?? DateTime.now();
              final dayLabel = DateFormat('EEE, MMM d').format(day);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('🪨', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            rockCtrls[g.id]!.text.trim(),
                            style:
                                Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: AppColors.content,
                                      fontWeight: FontWeight.w600,
                                    ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_goalEmoji(g.title)} ${g.title} · $dayLabel',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: AppColors.contentSecondary,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 24),
            Text(
              'WEEKLY INTENT',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.contentTertiary,
                    letterSpacing: 1.2,
                  ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: intentCtrl,
              maxLines: 3,
              minLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'In one line, what is this week about?',
                hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.contentTertiary,
                    ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.borderSubtle),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.borderSubtle),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                      color: AppColors.kiwi400, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isCommitting ? null : onCommit,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: isCommitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(isEditing ? 'Save changes' : 'Create my week'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Smart goal emoji (copied from goals_screen._goalEmoji for consistency)
// ---------------------------------------------------------------------------

String _goalEmoji(String title) {
  final t = title.toLowerCase();
  if (t.contains('exercise') ||
      t.contains('run') ||
      t.contains('gym') ||
      t.contains('health') ||
      t.contains('fitness') ||
      t.contains('lose') ||
      t.contains('weight')) return '🏃';
  if (t.contains('save') ||
      t.contains('invest') ||
      t.contains('debt') ||
      t.contains('money') ||
      t.contains('financ') ||
      t.contains('\$')) return '💰';
  if (t.contains('promot') ||
      t.contains('career') ||
      t.contains('job') ||
      t.contains('launch') ||
      t.contains('ship') ||
      t.contains('work')) return '🚀';
  if (t.contains('read') ||
      t.contains('book') ||
      t.contains('learn') ||
      t.contains('course') ||
      t.contains('study')) return '📚';
  if (t.contains('meditat') ||
      t.contains('sleep') ||
      t.contains('mindful') ||
      t.contains('stress') ||
      t.contains('wellbeing')) return '🧘';
  if (t.contains('write') ||
      t.contains('creat') ||
      t.contains('art') ||
      t.contains('music') ||
      t.contains('design')) return '🎨';
  if (t.contains('family') ||
      t.contains('friend') ||
      t.contains('relat') ||
      t.contains('date') ||
      t.contains('call')) return '❤️';
  if (t.contains('language') ||
      t.contains('certif') ||
      t.contains('skill')) return '🎓';
  return '🎯';
}
