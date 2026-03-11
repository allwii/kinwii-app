// ReflectScreen - "Am I improving?"
// Usage: Registered as /reflect route inside AppShell's ShellRoute.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/kinwii_card.dart';
import '../../../../models/weekly_plan.dart';
import '../../../../models/weekly_reflection.dart';
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

final _reflectionProvider =
    FutureProvider.autoDispose.family<WeeklyReflection?, String>(
  (ref, weeklyPlanId) async {
    final api = ref.read(apiServiceProvider);
    try {
      final response = await api.get('/reflection/$weeklyPlanId');
      if (response.data == null) return null;
      return WeeklyReflection.fromJson(
          response.data as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  },
);

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class ReflectScreen extends ConsumerWidget {
  const ReflectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(_currentWeekPlanProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: planAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.kiwi400),
          ),
          error: (_, __) => const Center(
            child: Text('Could not load weekly plan.'),
          ),
          data: (plan) => plan == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.self_improvement,
                          size: 64,
                          color: AppColors.kiwi300,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'No active week yet',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(color: AppColors.content),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Set up your weekly intent first, then come back to reflect.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppColors.contentSecondary),
                        ),
                        const SizedBox(height: 28),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => context.go('/week'),
                            icon: const Icon(Icons.view_week_outlined),
                            label: const Text('Go to Week'),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : _ReflectBody(plan: plan),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body — decides between read-only and form views
// ---------------------------------------------------------------------------

class _ReflectBody extends ConsumerWidget {
  const _ReflectBody({required this.plan});

  final WeeklyPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reflectionAsync = ref.watch(_reflectionProvider(plan.id));

    return reflectionAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.kiwi400),
      ),
      error: (_, __) => _StartReviewPrompt(plan: plan),
      data: (reflection) => reflection != null
          ? _ReflectionReadOnly(reflection: reflection)
          : _StartReviewPrompt(plan: plan),
    );
  }
}

// ---------------------------------------------------------------------------
// Start review prompt — replaces the old inline form
// ---------------------------------------------------------------------------

class _StartReviewPrompt extends StatelessWidget {
  const _StartReviewPrompt({required this.plan});
  final WeeklyPlan plan;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.self_improvement,
              size: 64,
              color: AppColors.kiwi300,
            ),
            const SizedBox(height: 20),
            Text(
              'Ready to reflect?',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(color: AppColors.content),
            ),
            const SizedBox(height: 8),
            Text(
              'Review your week, get AI insights, and plan ahead.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.contentSecondary),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => context.push('/reflect/review/${plan.id}'),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start weekly review'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Read-only view (reflection already submitted)
// ---------------------------------------------------------------------------

class _ReflectionReadOnly extends StatelessWidget {
  const _ReflectionReadOnly({required this.reflection});

  final WeeklyReflection reflection;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 4),
            child: Text(
              'Weekly reflection',
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    color: AppColors.content,
                  ),
            ),
          ),
        ),

        // AI summary card
        if (reflection.aiSummary != null) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: KinwiiCard(
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
                          'AI summary',
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: AppColors.kiwi600,
                                  ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      reflection.aiSummary!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.content,
                            height: 1.6,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],

        // AI focus recommendation
        if (reflection.aiFocusRecommendation != null) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: KinwiiCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.lightbulb_outline,
                      size: 18,
                      color: AppColors.kiwi500,
                    ),
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
                            reflection.aiFocusRecommendation!,
                            style:
                                Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: AppColors.content,
                                    ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],

        // AI pattern insight
        if (reflection.aiPatternInsight != null) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: KinwiiCard(
                color: AppColors.kiwi50,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.trending_up,
                      size: 18,
                      color: AppColors.kiwi500,
                    ),
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
                            reflection.aiPatternInsight!,
                            style:
                                Theme.of(context).textTheme.bodyMedium?.copyWith(
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
            ),
          ),
        ],

        // Answer cards
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
          sliver: SliverList.separated(
            itemCount: _readOnlyItems(reflection).length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final item = _readOnlyItems(reflection)[i];
              return KinwiiCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.$1,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: AppColors.contentSecondary,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.$2.isEmpty ? '—' : item.$2,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.content,
                          ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  List<(String, String)> _readOnlyItems(WeeklyReflection r) => [
        ('What moved the needle?', r.movedNeedle ?? ''),
        ('What drained energy?', r.drainedEnergy ?? ''),
        ('What should you stop doing?', r.stopDoing ?? ''),
        ('What deserves more focus?', r.focusNextWeek ?? ''),
      ];
}

// ---------------------------------------------------------------------------
// Form view
// ---------------------------------------------------------------------------

class _ReflectionForm extends ConsumerStatefulWidget {
  const _ReflectionForm({required this.plan});

  final WeeklyPlan plan;

  @override
  ConsumerState<_ReflectionForm> createState() => _ReflectionFormState();
}

class _ReflectionFormState extends ConsumerState<_ReflectionForm>
    with TickerProviderStateMixin {
  final _movedNeedleController = TextEditingController();
  final _drainedEnergyController = TextEditingController();
  final _stopDoingController = TextEditingController();
  final _focusNextWeekController = TextEditingController();

  bool _isSubmitting = false;
  bool _isLoadingAi = false;
  String? _error;

  // Post-AI state
  String? _aiSummary;
  String? _aiFocusRecommendation;
  String? _aiPatternInsight;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
  }

  @override
  void dispose() {
    _movedNeedleController.dispose();
    _drainedEnergyController.dispose();
    _stopDoingController.dispose();
    _focusNextWeekController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final movedNeedle = _movedNeedleController.text.trim();
    final drainedEnergy = _drainedEnergyController.text.trim();
    final stopDoing = _stopDoingController.text.trim();
    final focusNextWeek = _focusNextWeekController.text.trim();

    if (movedNeedle.isEmpty) {
      setState(() => _error = 'Please answer at least the first question.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final api = ref.read(apiServiceProvider);

      // POST reflection
      final reflectionResponse = await api.post('/reflection', data: {
        'weekly_plan_id': widget.plan.id,
        'moved_needle': movedNeedle,
        'drained_energy': drainedEnergy,
        'stop_doing': stopDoing,
        'focus_next_week': focusNextWeek,
      });

      final reflection = WeeklyReflection.fromJson(
          reflectionResponse.data as Map<String, dynamic>);

      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _isLoadingAi = true;
      });

      // POST AI summary
      final aiResponse = await api.post('/ai/summarize-reflection', data: {
        'reflection_id': reflection.id,
      });

      if (!mounted) return;
      setState(() {
        _isLoadingAi = false;
        _aiSummary = aiResponse.data['summary'] as String?;
        _aiFocusRecommendation =
            aiResponse.data['focus_recommendation'] as String?;
        _aiPatternInsight =
            aiResponse.data['pattern_insight'] as String?;
      });
      _fadeController.forward();

      // Invalidate so next visit shows read-only
      ref.invalidate(_reflectionProvider(widget.plan.id));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _isLoadingAi = false;
        _error = 'Something went wrong. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show result after AI call
    if (_aiSummary != null) {
      return _AiResultView(
        summary: _aiSummary!,
        focusRecommendation: _aiFocusRecommendation,
        patternInsight: _aiPatternInsight,
        fadeAnimation: _fadeAnimation,
      );
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Weekly reflection',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        color: AppColors.content,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Take a moment to reflect before moving forward.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.contentSecondary,
                      ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          sliver: SliverList.separated(
            itemCount: 4,
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemBuilder: (context, index) {
              final questions = [
                ('What moved the needle?', _movedNeedleController,
                    'e.g. Finished the feature spec'),
                ('What drained energy?', _drainedEnergyController,
                    'e.g. Too many status meetings'),
                ('What should you stop doing?', _stopDoingController,
                    'e.g. Checking email first thing'),
                ('What deserves more focus?', _focusNextWeekController,
                    'e.g. Deep work blocks'),
              ];
              final q = questions[index];
              return _QuestionField(
                question: q.$1,
                controller: q.$2,
                hint: q.$3,
                isFirst: index == 0,
              );
            },
          ),
        ),
        if (_error != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_isSubmitting || _isLoadingAi) ? null : _submit,
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : _isLoadingAi
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Getting AI summary…',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(color: Colors.white),
                              ),
                            ],
                          )
                        : const Text('Complete reflection'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Question field
// ---------------------------------------------------------------------------

class _QuestionField extends StatelessWidget {
  const _QuestionField({
    required this.question,
    required this.controller,
    required this.hint,
    required this.isFirst,
  });

  final String question;
  final TextEditingController controller;
  final String hint;
  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.content,
              ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          autofocus: isFirst,
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

// ---------------------------------------------------------------------------
// AI result view (fades in after AI returns)
// ---------------------------------------------------------------------------

class _AiResultView extends StatelessWidget {
  const _AiResultView({
    required this.summary,
    required this.focusRecommendation,
    this.patternInsight,
    required this.fadeAnimation,
  });

  final String summary;
  final String? focusRecommendation;
  final String? patternInsight;
  final Animation<double> fadeAnimation;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: fadeAnimation,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.auto_awesome,
                  color: AppColors.kiwi500,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  'Reflection complete',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: AppColors.content,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Here is your AI-generated summary.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.contentSecondary,
                  ),
            ),
            const SizedBox(height: 20),

            // Summary card
            KinwiiCard(
              color: AppColors.kiwi50,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Summary',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: AppColors.kiwi600,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    summary,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.content,
                          height: 1.6,
                        ),
                  ),
                ],
              ),
            ),

            // Focus recommendation
            if (focusRecommendation != null) ...[
              const SizedBox(height: 12),
              KinwiiCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.lightbulb_outline,
                        size: 18,
                        color: AppColors.kiwi500,
                      ),
                    ),
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
                                ?.copyWith(
                                  color: AppColors.contentSecondary,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            focusRecommendation!,
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

            // Pattern insight (shows after 3+ weeks of reflections)
            if (patternInsight != null) ...[
              const SizedBox(height: 12),
              KinwiiCard(
                color: AppColors.kiwi50,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.trending_up,
                        size: 18,
                        color: AppColors.kiwi500,
                      ),
                    ),
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
                                ?.copyWith(
                                  color: AppColors.kiwi600,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            patternInsight!,
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
          ],
        ),
      ),
    );
  }
}
