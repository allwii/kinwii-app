// WeeklyReviewScreen — 4-step guided weekly review flow.
// Steps: Review tasks → AI Insights → Reflect → Next Week

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

  // Data loaded in step 1
  WeeklyPlan? _plan;
  List<Task> _completedTasks = [];
  List<Task> _incompleteTasks = [];
  bool _isLoading = true;
  String? _loadError;

  // Carry-forward selections (step 1)
  final Set<String> _carryForwardIds = {};

  // AI insights (step 2)
  String? _aiSummary;
  String? _aiFocusRec;
  String? _aiPattern;
  bool _isLoadingAi = false;

  // Reflection form (step 3)
  final _movedNeedleCtrl = TextEditingController();
  final _drainedEnergyCtrl = TextEditingController();
  final _stopDoingCtrl = TextEditingController();
  final _focusNextWeekCtrl = TextEditingController();
  bool _isSubmittingReflection = false;

  // Next week (step 4)
  String? _suggestedIntent;
  bool _isLoadingSuggestion = false;
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
    _movedNeedleCtrl.dispose();
    _drainedEnergyCtrl.dispose();
    _stopDoingCtrl.dispose();
    _focusNextWeekCtrl.dispose();
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

  // Step 2: Submit reflection + get AI insights
  Future<void> _submitReflectionAndGetAi() async {
    final movedNeedle = _movedNeedleCtrl.text.trim();
    if (movedNeedle.isEmpty) return;

    setState(() => _isSubmittingReflection = true);

    try {
      final api = ref.read(apiServiceProvider);

      // POST reflection
      final reflResp = await api.post('/reflection', data: {
        'weekly_plan_id': widget.weeklyPlanId,
        'moved_needle': movedNeedle,
        'drained_energy': _drainedEnergyCtrl.text.trim(),
        'stop_doing': _stopDoingCtrl.text.trim(),
        'focus_next_week': _focusNextWeekCtrl.text.trim(),
      });

      final reflId = reflResp.data['id'] as String;
      if (!mounted) return;
      setState(() {
        _isSubmittingReflection = false;
        _isLoadingAi = true;
      });

      // Move to AI step immediately
      _goToStep(2);

      // POST AI summary
      final aiResp = await api.post('/ai/summarize-reflection', data: {
        'reflection_id': reflId,
      });

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
        _isSubmittingReflection = false;
        _isLoadingAi = false;
      });
    }
  }

  // Step 4: Suggest intent for next week
  Future<void> _loadSuggestedIntent() async {
    if (_suggestedIntent != null || _isLoadingSuggestion) return;
    setState(() => _isLoadingSuggestion = true);
    try {
      final api = ref.read(apiServiceProvider);
      final resp = await api.post('/ai/suggest-intent', data: {
        'goal_id': _plan!.quarterId,
        'previous_plan_id': widget.weeklyPlanId,
      });
      if (!mounted) return;
      final intent = resp.data['suggested_intent'] as String? ?? '';
      setState(() {
        _suggestedIntent = intent;
        _nextIntentCtrl.text = intent;
        _isLoadingSuggestion = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingSuggestion = false);
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: _StepIndicator(current: _currentStep, total: 4),
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
                    _Step1Review(
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
                    _Step2Reflect(
                      movedNeedleCtrl: _movedNeedleCtrl,
                      drainedEnergyCtrl: _drainedEnergyCtrl,
                      stopDoingCtrl: _stopDoingCtrl,
                      focusNextWeekCtrl: _focusNextWeekCtrl,
                      isSubmitting: _isSubmittingReflection,
                      onSubmit: _submitReflectionAndGetAi,
                      onBack: () => _goToStep(0),
                    ),
                    _Step3AiInsights(
                      isLoading: _isLoadingAi,
                      summary: _aiSummary,
                      focusRec: _aiFocusRec,
                      pattern: _aiPattern,
                      onNext: () {
                        _loadSuggestedIntent();
                        _goToStep(3);
                      },
                      onBack: () => _goToStep(1),
                    ),
                    _Step4NextWeek(
                      isLoadingSuggestion: _isLoadingSuggestion,
                      intentCtrl: _nextIntentCtrl,
                      isCreating: _isCreatingNextWeek,
                      onFinish: _createNextWeek,
                      onBack: () => _goToStep(2),
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
            color: i <= current ? AppColors.kiwi400 : AppColors.borderSubtle,
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 1: Review tasks
// ---------------------------------------------------------------------------

class _Step1Review extends StatelessWidget {
  const _Step1Review({
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
  final ValueChanged<String> onToggleCarry;
  final VoidCallback onNext;

  int get _total => completedTasks.length + incompleteTasks.length;
  int get _completionPct =>
      _total == 0 ? 0 : (completedTasks.length * 100 ~/ _total);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How did your week go?',
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(color: AppColors.content),
          ),
          const SizedBox(height: 4),
          Text(
            'Intent: ${plan.intent}',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.contentSecondary),
          ),
          const SizedBox(height: 20),

          // Completion summary card
          KinwiiCard(
            color: AppColors.kiwi50,
            child: Column(
              children: [
                Row(
                  children: [
                    Text(
                      '$_completionPct%',
                      style: Theme.of(context)
                          .textTheme
                          .headlineLarge
                          ?.copyWith(
                            color: AppColors.kiwi600,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${completedTasks.length} of $_total tasks completed',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: AppColors.content),
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: _total == 0
                                  ? 0
                                  : completedTasks.length / _total,
                              backgroundColor: AppColors.borderSubtle,
                              valueColor: const AlwaysStoppedAnimation(
                                  AppColors.kiwi400),
                              minHeight: 6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Completed tasks
          if (completedTasks.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Completed',
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: AppColors.kiwi600),
            ),
            const SizedBox(height: 8),
            ...completedTasks.map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle,
                          size: 18, color: AppColors.kiwi400),
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
                )),
          ],

          // Incomplete tasks — with carry-forward checkboxes
          if (incompleteTasks.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Incomplete — carry forward?',
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: AppColors.contentSecondary),
            ),
            const SizedBox(height: 8),
            ...incompleteTasks.map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: InkWell(
                    onTap: () => onToggleCarry(t.id),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            carryForwardIds.contains(t.id)
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                            size: 20,
                            color: carryForwardIds.contains(t.id)
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
                                  ?.copyWith(color: AppColors.content),
                            ),
                          ),
                          _EnergyPill(type: t.energyType),
                        ],
                      ),
                    ),
                  ),
                )),
          ],

          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onNext,
              child: const Text('Continue to reflection'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 2: Reflect
// ---------------------------------------------------------------------------

class _Step2Reflect extends StatelessWidget {
  const _Step2Reflect({
    required this.movedNeedleCtrl,
    required this.drainedEnergyCtrl,
    required this.stopDoingCtrl,
    required this.focusNextWeekCtrl,
    required this.isSubmitting,
    required this.onSubmit,
    required this.onBack,
  });

  final TextEditingController movedNeedleCtrl;
  final TextEditingController drainedEnergyCtrl;
  final TextEditingController stopDoingCtrl;
  final TextEditingController focusNextWeekCtrl;
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
            'Reflect on your week',
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(color: AppColors.content),
          ),
          const SizedBox(height: 4),
          Text(
            'Take a moment before moving forward.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.contentSecondary),
          ),
          const SizedBox(height: 20),
          _QuestionField(
            question: 'What moved the needle?',
            controller: movedNeedleCtrl,
            hint: 'e.g. Finished the feature spec',
          ),
          const SizedBox(height: 14),
          _QuestionField(
            question: 'What drained energy?',
            controller: drainedEnergyCtrl,
            hint: 'e.g. Too many status meetings',
          ),
          const SizedBox(height: 14),
          _QuestionField(
            question: 'What should you stop doing?',
            controller: stopDoingCtrl,
            hint: 'e.g. Checking email first thing',
          ),
          const SizedBox(height: 14),
          _QuestionField(
            question: 'What deserves more focus?',
            controller: focusNextWeekCtrl,
            hint: 'e.g. Deep work blocks',
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              TextButton(
                onPressed: onBack,
                child: const Text('Back'),
              ),
              const SizedBox(width: 12),
              Expanded(
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
                      : const Text('Get AI insights'),
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
// Step 3: AI Insights
// ---------------------------------------------------------------------------

class _Step3AiInsights extends StatelessWidget {
  const _Step3AiInsights({
    required this.isLoading,
    this.summary,
    this.focusRec,
    this.pattern,
    required this.onNext,
    required this.onBack,
  });

  final bool isLoading;
  final String? summary;
  final String? focusRec;
  final String? pattern;
  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.kiwi400),
            const SizedBox(height: 16),
            Text(
              'Analyzing your week...',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.contentSecondary),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome,
                  size: 22, color: AppColors.kiwi500),
              const SizedBox(width: 8),
              Text(
                'AI insights',
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(color: AppColors.content),
              ),
            ],
          ),
          const SizedBox(height: 20),

          if (summary != null) ...[
            KinwiiCard(
              color: AppColors.kiwi50,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Summary',
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: AppColors.kiwi600),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    summary!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.content,
                          height: 1.6,
                        ),
                  ),
                ],
              ),
            ),
          ],

          if (focusRec != null) ...[
            const SizedBox(height: 12),
            KinwiiCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline,
                      size: 18, color: AppColors.kiwi500),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Focus next week',
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(color: AppColors.contentSecondary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          focusRec!,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppColors.content),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (pattern != null) ...[
            const SizedBox(height: 12),
            KinwiiCard(
              color: AppColors.kiwi50,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.trending_up,
                      size: 18, color: AppColors.kiwi500),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pattern noticed',
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(color: AppColors.kiwi600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          pattern!,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: AppColors.content,
                                height: 1.5,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 28),
          Row(
            children: [
              TextButton(
                onPressed: onBack,
                child: const Text('Back'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: onNext,
                  child: const Text('Plan next week'),
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
// Step 4: Next Week
// ---------------------------------------------------------------------------

class _Step4NextWeek extends StatelessWidget {
  const _Step4NextWeek({
    required this.isLoadingSuggestion,
    required this.intentCtrl,
    required this.isCreating,
    required this.onFinish,
    required this.onBack,
  });

  final bool isLoadingSuggestion;
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
            'Set next week\'s intent',
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(color: AppColors.content),
          ),
          const SizedBox(height: 4),
          Text(
            'What one thing will make next week count?',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.contentSecondary),
          ),
          const SizedBox(height: 24),
          if (isLoadingSuggestion)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.kiwi400,
                    ),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'AI is suggesting an intent...',
                    style: TextStyle(
                      color: AppColors.contentSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          TextField(
            controller: intentCtrl,
            maxLines: 3,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'e.g. Ship the checkout flow and write tests',
              hintStyle: TextStyle(color: AppColors.contentTertiary),
              labelText: 'Weekly intent',
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              TextButton(
                onPressed: onBack,
                child: const Text('Back'),
              ),
              const SizedBox(width: 12),
              Expanded(
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
                      : const Text('Start next week'),
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
// Shared widgets
// ---------------------------------------------------------------------------

class _QuestionField extends StatelessWidget {
  const _QuestionField({
    required this.question,
    required this.controller,
    required this.hint,
  });

  final String question;
  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(color: AppColors.content),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: 3,
          minLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.contentTertiary),
          ),
        ),
      ],
    );
  }
}

class _EnergyPill extends StatelessWidget {
  const _EnergyPill({required this.type});
  final EnergyType type;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (type) {
      EnergyType.deep => ('Deep', AppColors.energyDeep),
      EnergyType.admin => ('Admin', AppColors.energyAdmin),
      EnergyType.creative => ('Creative', AppColors.energyCreative),
      EnergyType.personal => ('Personal', AppColors.energyPersonal),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, color: AppColors.content),
      ),
    );
  }
}
