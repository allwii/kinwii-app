// WeeklyReviewScreen — 3-step guided weekly review flow.
// Steps: Celebrate → Reflect → AI Insights + Plan Next Week
// Designed to complete in ~10 minutes.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/kinwii_card.dart';
import '../../../../models/task.dart';
import '../../../../models/weekly_plan.dart';
import '../../../../features/auth/presentation/screens/login_screen.dart';

class WeeklyReviewScreen extends ConsumerStatefulWidget {
  const WeeklyReviewScreen({super.key, required this.weeklyPlanId});

  final String weeklyPlanId;

  @override
  ConsumerState<WeeklyReviewScreen> createState() =>
      _WeeklyReviewScreenState();
}

class _WeeklyReviewScreenState extends ConsumerState<WeeklyReviewScreen> {
  final _pageController = PageController();
  int _currentStep = 0;

  // Data
  WeeklyPlan? _plan;
  List<Task> _completedTasks = [];
  List<Task> _incompleteTasks = [];
  bool _isLoading = true;
  String? _loadError;

  // Carry-forward selections
  final Set<String> _carryForwardIds = {};

  // Reflection (2 questions instead of 4)
  final _whatWorkedCtrl = TextEditingController();
  final _whatToChangeCtrl = TextEditingController();
  bool _isSubmitting = false;

  // AI insights + next week (combined step 3)
  String? _aiSummary;
  String? _aiFocusRec;
  String? _aiPattern;
  bool _isLoadingAi = false;
  final _nextIntentCtrl = TextEditingController();
  bool _isCreatingNextWeek = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _whatWorkedCtrl.dispose();
    _whatToChangeCtrl.dispose();
    _nextIntentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final api = ref.read(apiServiceProvider);
      final planResp = await api.get('/week/${widget.weeklyPlanId}');
      final plan =
          WeeklyPlan.fromJson(planResp.data as Map<String, dynamic>);

      final tasksResp = await api.get('/tasks',
          queryParameters: {'weekly_plan_id': widget.weeklyPlanId});
      final tasks = (tasksResp.data as List)
          .map((t) => Task.fromJson(t as Map<String, dynamic>))
          .toList();

      if (!mounted) return;
      setState(() {
        _plan = plan;
        _completedTasks = tasks.where((t) => t.completed).toList();
        _incompleteTasks = tasks.where((t) => !t.completed).toList();
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Could not load weekly data.';
      });
    }
  }

  void _goToStep(int step) {
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    setState(() => _currentStep = step);
  }

  Future<void> _submitAndLoadAi() async {
    final worked = _whatWorkedCtrl.text.trim();
    if (worked.isEmpty) return;

    setState(() => _isSubmitting = true);
    try {
      final api = ref.read(apiServiceProvider);

      // Submit reflection (map 2 fields to existing 4-field model)
      final reflResp = await api.post('/reflection', data: {
        'weekly_plan_id': widget.weeklyPlanId,
        'moved_needle': worked,
        'focus_next_week': _whatToChangeCtrl.text.trim(),
      });

      final reflId = reflResp.data['id'] as String;
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _isLoadingAi = true;
      });

      // Move to step 3 immediately
      _goToStep(2);

      // Load AI insights + suggested intent in parallel
      final aiFuture = api.post('/ai/summarize-reflection', data: {
        'reflection_id': reflId,
      });

      Future<void>? intentFuture;
      if (_plan?.quarterId != null) {
        intentFuture = api.post('/ai/suggest-intent', data: {
          'goal_id': _plan!.quarterId,
          'previous_plan_id': widget.weeklyPlanId,
        }).then((resp) {
          if (!mounted) return;
          final intent = resp.data['suggested_intent'] as String? ?? '';
          setState(() {
            _nextIntentCtrl.text = intent;
          });
        }).catchError((_) {});
      }

      final aiResp = await aiFuture;
      await intentFuture;

      if (!mounted) return;
      setState(() {
        _isLoadingAi = false;
        _aiSummary = aiResp.data['summary'] as String?;
        _aiFocusRec = aiResp.data['focus_recommendation'] as String?;
        _aiPattern = aiResp.data['pattern_insight'] as String?;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _isLoadingAi = false;
      });
    }
  }

  Future<void> _createNextWeek() async {
    final intent = _nextIntentCtrl.text.trim();
    if (intent.isEmpty) return;

    setState(() => _isCreatingNextWeek = true);
    try {
      final api = ref.read(apiServiceProvider);
      final nextMonday =
          _plan!.weekStartDate.add(const Duration(days: 7));
      final nextMondayStr = DateFormat('yyyy-MM-dd').format(nextMonday);

      // Create next week plan
      final newPlanResp = await api.post('/week', data: {
        'quarter_id': _plan!.quarterId,
        'week_start_date': nextMondayStr,
        'intent': intent,
      });

      final newPlanId = newPlanResp.data['id'] as String;

      // Carry forward selected tasks
      if (_carryForwardIds.isNotEmpty) {
        await api.post('/tasks/carry-forward', data: {
          'task_ids': _carryForwardIds.toList(),
          'target_weekly_plan_id': newPlanId,
          'target_date': nextMondayStr,
        });
      }

      // Create a starter task from AI focus recommendation (if available)
      if (_aiFocusRec != null && _aiFocusRec!.isNotEmpty) {
        try {
          await api.post('/tasks', data: {
            'weekly_plan_id': newPlanId,
            'title': _aiFocusRec,
            'date': nextMondayStr,
            'energy_type': 'deep',
          });
        } catch (_) {
          // Non-critical — don't block navigation
        }
      }

      if (!mounted) return;
      context.go('/today');
    } catch (_) {
      if (!mounted) return;
      setState(() => _isCreatingNextWeek = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.content),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Weekly review',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(color: AppColors.content),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '~10 min',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.contentTertiary,
                    ),
              ),
            ),
          ),
        ],
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
              : PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) => setState(() => _currentStep = i),
                  children: [
                    // Step 1: Celebrate
                    _CelebrateStep(
                      plan: _plan!,
                      completedTasks: _completedTasks,
                      incompleteTasks: _incompleteTasks,
                      carryForwardIds: _carryForwardIds,
                      onToggleCarry: (id) => setState(() {
                        if (_carryForwardIds.contains(id)) {
                          _carryForwardIds.remove(id);
                        } else {
                          _carryForwardIds.add(id);
                        }
                      }),
                      onNext: () => _goToStep(1),
                    ),

                    // Step 2: Reflect (2 questions)
                    _ReflectStep(
                      whatWorkedCtrl: _whatWorkedCtrl,
                      whatToChangeCtrl: _whatToChangeCtrl,
                      isSubmitting: _isSubmitting,
                      onSubmit: _submitAndLoadAi,
                      onBack: () => _goToStep(0),
                    ),

                    // Step 3: AI Insights + Plan Next Week
                    _InsightsAndPlanStep(
                      isLoadingAi: _isLoadingAi,
                      summary: _aiSummary,
                      focusRec: _aiFocusRec,
                      pattern: _aiPattern,
                      intentCtrl: _nextIntentCtrl,
                      isCreating: _isCreatingNextWeek,
                      onFinish: _createNextWeek,
                      onBack: () => _goToStep(1),
                    ),
                  ],
                ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step indicator
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
              color:
                  i <= current ? AppColors.kiwi400 : AppColors.borderSubtle,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 1: Celebrate — visual progress + wins + carry-forward
// ---------------------------------------------------------------------------

class _CelebrateStep extends StatelessWidget {
  const _CelebrateStep({
    required this.plan,
    required this.completedTasks,
    required this.incompleteTasks,
    required this.carryForwardIds,
    required this.onToggleCarry,
    required this.onNext,
  });

  final WeeklyPlan plan;
  final List<Task> completedTasks;
  final List<Task> incompleteTasks;
  final Set<String> carryForwardIds;
  final void Function(String id) onToggleCarry;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final total = completedTasks.length + incompleteTasks.length;
    final pct = total > 0
        ? (completedTasks.length / total * 100).round()
        : 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Progress summary
          Text(
            'This week\'s progress',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColors.content,
                ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '${completedTasks.length}',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      color: AppColors.kiwi500,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              Text(
                ' of $total tasks ($pct%)',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.contentSecondary,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total > 0 ? completedTasks.length / total : 0,
              minHeight: 8,
              backgroundColor: AppColors.surfaceAlt,
              color: AppColors.kiwi400,
            ),
          ),

          // Wins
          if (completedTasks.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Wins',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppColors.kiwi600,
                  ),
            ),
            const SizedBox(height: 8),
            ...completedTasks.take(5).map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle,
                          size: 18, color: AppColors.kiwi500),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(t.title,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: AppColors.content)),
                      ),
                    ],
                  ),
                )),
            if (completedTasks.length > 5)
              Text(
                '+${completedTasks.length - 5} more',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.contentTertiary,
                    ),
              ),
          ],

          // Carry forward
          if (incompleteTasks.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Carry forward?',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppColors.contentSecondary,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tap to keep or drop each task.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.contentTertiary,
                  ),
            ),
            const SizedBox(height: 8),
            ...incompleteTasks.map((t) {
              final carry = carryForwardIds.contains(t.id);
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: GestureDetector(
                  onTap: () => onToggleCarry(t.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
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
                          size: 16,
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
                          carry ? 'Keep' : 'Drop',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
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
          ],

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

// ---------------------------------------------------------------------------
// Step 2: Reflect — 2 focused questions
// ---------------------------------------------------------------------------

class _ReflectStep extends StatelessWidget {
  const _ReflectStep({
    required this.whatWorkedCtrl,
    required this.whatToChangeCtrl,
    required this.isSubmitting,
    required this.onSubmit,
    required this.onBack,
  });

  final TextEditingController whatWorkedCtrl;
  final TextEditingController whatToChangeCtrl;
  final bool isSubmitting;
  final VoidCallback onSubmit;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick reflection',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColors.content,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Two questions — be honest, be brief.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.contentSecondary,
                ),
          ),
          const SizedBox(height: 20),
          Text(
            'What worked well this week?',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppColors.content,
                ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: whatWorkedCtrl,
            autofocus: true,
            maxLines: 3,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'e.g. Stayed focused on the proposal, shipped on time',
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'What\'s one thing to change next week?',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppColors.content,
                ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: whatToChangeCtrl,
            maxLines: 3,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'e.g. Block 2 hours of focus time each morning',
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
                  onPressed: isSubmitting ? null : onSubmit,
                  child: isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Get insights'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 3: AI Insights + Plan Next Week (combined)
// ---------------------------------------------------------------------------

class _InsightsAndPlanStep extends StatelessWidget {
  const _InsightsAndPlanStep({
    required this.isLoadingAi,
    required this.summary,
    required this.focusRec,
    required this.pattern,
    required this.intentCtrl,
    required this.isCreating,
    required this.onFinish,
    required this.onBack,
  });

  final bool isLoadingAi;
  final String? summary;
  final String? focusRec;
  final String? pattern;
  final TextEditingController intentCtrl;
  final bool isCreating;
  final VoidCallback onFinish;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Insights & next week',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColors.content,
                ),
          ),
          const SizedBox(height: 16),

          // AI loading state
          if (isLoadingAi)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(color: AppColors.kiwi400),
                    SizedBox(height: 12),
                    Text('Analyzing your week...'),
                  ],
                ),
              ),
            ),

          // AI Summary
          if (summary != null) ...[
            KinwiiCard(
              color: AppColors.kiwi50,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome,
                          size: 16, color: AppColors.kiwi600),
                      const SizedBox(width: 6),
                      Text(
                        'AI Summary',
                        style:
                            Theme.of(context).textTheme.labelLarge?.copyWith(
                                  color: AppColors.kiwi600,
                                ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(summary!,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.content)),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Focus recommendation
          if (focusRec != null) ...[
            KinwiiCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.lightbulb_outline,
                          size: 16, color: AppColors.kiwi500),
                      const SizedBox(width: 6),
                      Text(
                        'Focus next week',
                        style:
                            Theme.of(context).textTheme.labelLarge?.copyWith(
                                  color: AppColors.kiwi600,
                                ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(focusRec!,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.content)),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Pattern insight
          if (pattern != null) ...[
            KinwiiCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.trending_up,
                          size: 16, color: AppColors.kiwi500),
                      const SizedBox(width: 6),
                      Text(
                        'Pattern noticed',
                        style:
                            Theme.of(context).textTheme.labelLarge?.copyWith(
                                  color: AppColors.kiwi600,
                                ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(pattern!,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.content)),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Next week intent
          if (!isLoadingAi) ...[
            const Divider(),
            const SizedBox(height: 16),
            Text(
              'Set next week\'s focus',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.content,
                  ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: intentCtrl,
              maxLines: 2,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'What will you focus on next week?',
              ),
            ),
            const SizedBox(height: 24),
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
                    onPressed: isCreating ? null : onFinish,
                    child: isCreating
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Finish review'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
