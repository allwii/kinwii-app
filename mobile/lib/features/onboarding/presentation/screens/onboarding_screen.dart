// OnboardingScreen — 7-screen calm, minimal onboarding flow.
// 1. Welcome → 2. Benefits → 3. Life Areas → 4. Goal → 5. Why → 6. Pro → 7. Account
//
// Design principles:
// - All screens use the light background (#F8F9F6). Green is an accent, never a backdrop.
// - Progress bar on screens 2–7 (pages 1–6 internally).
// - Back button on screens 2–7.
// - Consistent 24px horizontal padding; Welcome uses 32px.
// - ElevatedButton: kiwi400 fill, white text, 16px vertical padding, full width, r=12.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../services/providers.dart';
import '../../../../services/subscription_service.dart';

// ---------------------------------------------------------------------------
// Goal suggestion data
// ---------------------------------------------------------------------------

const _goalSuggestions = <String, List<String>>{
  'career': ['Get promoted this year', 'Launch a side project', 'Find a new job'],
  'finance': ['Save \$10K this year', 'Pay off debt', 'Start investing'],
  'health': ['Exercise 3x per week', 'Run a 5K', 'Lose 10 pounds'],
  'growth': ['Read 12 books this year', 'Learn a new skill', 'Start journaling'],
  'relationships': ['Call family weekly', 'Make 3 new friends', 'Plan monthly date nights'],
  'creativity': ['Write every day', 'Start a creative project', 'Learn an instrument'],
  'wellbeing': ['Meditate daily', 'Sleep 8 hours', 'Reduce screen time'],
  'learning': ['Take an online course', 'Learn a language', 'Get certified'],
};

const _lifeAreas = <String, (IconData, String)>{
  'career': (Icons.work_outline, 'Career'),
  'finance': (Icons.savings_outlined, 'Finance'),
  'health': (Icons.fitness_center, 'Health & Fitness'),
  'growth': (Icons.psychology_outlined, 'Personal Growth'),
  'relationships': (Icons.favorite_outline, 'Relationships'),
  'creativity': (Icons.palette_outlined, 'Creativity'),
  'wellbeing': (Icons.self_improvement, 'Well-being'),
  'learning': (Icons.school_outlined, 'Learning'),
};

// ---------------------------------------------------------------------------
// Total steps shown in the progress indicator (screens 2–7)
// ---------------------------------------------------------------------------
const _kProgressSteps = 5;

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  // Data
  final Set<String> _selectedAreas = {};
  final _goalCtrl = TextEditingController();
  String _selectedWhy = '';
  final _whyCtrl = TextEditingController();
  bool _isCreating = false;
  String? _error;

  @override
  void dispose() {
    _pageController.dispose();
    _goalCtrl.dispose();
    _whyCtrl.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
    setState(() {
      _currentPage = page;
      _error = null;
    });
  }

  void _next() {
    if (_currentPage < 5) _goToPage(_currentPage + 1);
  }

  void _back() {
    if (_currentPage > 0) _goToPage(_currentPage - 1);
  }

  Future<void> _finishOnboarding() async {
    setState(() {
      _isCreating = true;
      _error = null;
    });
    try {
      final auth = ref.read(authServiceProvider);
      final api = ref.read(apiServiceProvider);

      // Silently create anonymous account
      final deviceId = await auth.getOrCreateDeviceId();
      final response = await api.post('/auth/register-device', data: {
        'device_id': deviceId,
      });
      await auth.setToken(response.data['access_token']);

      // Submit onboarding goal data
      await _submitGoalData(api);

      await auth.setOnboardingComplete();
      await auth.setOnboardingSeen();
      await ref.read(subscriptionProvider.notifier).refresh();
      await ref.read(subscriptionProvider.notifier).identifyUser();
      if (mounted) context.go('/today');
    } catch (_) {
      if (mounted) {
        setState(() {
          _isCreating = false;
          _error = 'Something went wrong. Please try again.';
        });
      }
    }
  }

  Future<void> _submitGoalData(dynamic api) async {
    final title = _goalCtrl.text.trim();
    if (title.isEmpty) return;

    final now = DateTime.now();
    final endDate = DateTime(now.year, now.month + 3, now.day);
    final why = _whyCtrl.text.trim().isNotEmpty
        ? _whyCtrl.text.trim()
        : _selectedWhy.isNotEmpty
            ? _selectedWhy
            : '';

    try {
      final goalResp = await api.post('/goals', data: {
        'title': title,
        'why': why,
        'start_date': DateFormat('yyyy-MM-dd').format(now),
        'end_date': DateFormat('yyyy-MM-dd').format(endDate),
      });
      final goalId = goalResp.data['id'] as String;

      final monday = now.subtract(Duration(days: now.weekday - 1));
      await api.post('/week', data: {
        'quarter_id': goalId,
        'week_start_date': DateFormat('yyyy-MM-dd').format(monday),
        'intent': 'Focus on: $title',
      });
    } catch (_) {
      // Non-critical — user can set goals later
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          // 1. Welcome — full-bleed, no chrome
          _WelcomeScreen(
            onGetStarted: _next,
            onRecover: () => context.push('/sign-in'),
          ),
          // 2–7: wrapped with shared chrome (progress bar + back button)
          _OnboardingShell(
            currentStep: 1,
            onBack: _back,
            child: _BenefitsScreen(onContinue: _next),
          ),
          _OnboardingShell(
            currentStep: 2,
            onBack: _back,
            child: _LifeAreasScreen(
              selectedAreas: _selectedAreas,
              onToggle: (area) => setState(() {
                if (_selectedAreas.contains(area)) {
                  _selectedAreas.remove(area);
                } else {
                  _selectedAreas.add(area);
                }
              }),
              onContinue: _next,
            ),
          ),
          _OnboardingShell(
            currentStep: 3,
            onBack: _back,
            child: _GoalScreen(
              controller: _goalCtrl,
              selectedAreas: _selectedAreas,
              onContinue: _next,
            ),
          ),
          _OnboardingShell(
            currentStep: 4,
            onBack: _back,
            child: _WhyScreen(
              controller: _whyCtrl,
              selectedWhy: _selectedWhy,
              onSelectWhy: (why) => setState(() => _selectedWhy = why),
              onContinue: _next,
              onSkip: _next,
            ),
          ),
          _OnboardingShell(
            currentStep: 5,
            onBack: _back,
            child: _ProUpsellScreen(
              onStartTrial: _finishOnboarding,
              onSkip: _finishOnboarding,
              isLoading: _isCreating,
              error: _error,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared chrome for screens 2–7: SafeArea, progress bar, back button
// ---------------------------------------------------------------------------

class _OnboardingShell extends StatelessWidget {
  const _OnboardingShell({
    required this.currentStep,
    required this.onBack,
    required this.child,
  });

  /// 1-based step index within the progress indicator (1 = first step after welcome).
  final int currentStep;
  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top chrome: back button + progress bar
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 24, 0),
            child: Row(
              children: [
                // Back button
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  color: AppColors.contentSecondary,
                  onPressed: onBack,
                  tooltip: 'Back',
                ),
                const SizedBox(width: 4),
                // Step progress bar
                Expanded(
                  child: _StepProgressBar(
                    totalSteps: _kProgressSteps,
                    currentStep: currentStep,
                  ),
                ),
              ],
            ),
          ),
          // Screen content fills the remainder
          Expanded(child: child),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step progress bar widget
// ---------------------------------------------------------------------------

class _StepProgressBar extends StatelessWidget {
  const _StepProgressBar({
    required this.totalSteps,
    required this.currentStep,
  });

  final int totalSteps;

  /// 1-based. A step is "filled" if its index <= currentStep.
  final int currentStep;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(totalSteps, (i) {
        final filled = i < currentStep;
        return Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            height: 3,
            margin: EdgeInsets.only(left: i == 0 ? 0 : 4),
            decoration: BoxDecoration(
              color: filled ? AppColors.kiwi400 : AppColors.borderSubtle,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared full-width primary button
// ---------------------------------------------------------------------------

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.kiwi400,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.borderSubtle,
          disabledForegroundColor: AppColors.contentTertiary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(label),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Screen 1: Welcome
// ---------------------------------------------------------------------------

class _WelcomeScreen extends StatelessWidget {
  const _WelcomeScreen({required this.onGetStarted, required this.onRecover});
  final VoidCallback onGetStarted;
  final VoidCallback onRecover;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Soft light gradient: kiwi50 at the top fading to the standard background.
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.kiwi50, AppColors.background],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0.0, 0.65],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(flex: 2),

              // Accent icon
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.kiwi100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.eco_outlined,
                  size: 36,
                  color: AppColors.kiwi600,
                ),
              ),
              const SizedBox(height: 28),

              // Hero headline
              Text(
                'Welcome to',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      color: AppColors.contentSecondary,
                      fontWeight: FontWeight.w400,
                    ),
              ),
              Text(
                'Kinwii',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      color: AppColors.content,
                      letterSpacing: -1,
                    ),
              ),
              const SizedBox(height: 16),

              Text(
                'Plan with clarity.\nReflect with purpose.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.contentSecondary,
                      height: 1.6,
                    ),
              ),

              const Spacer(flex: 3),

              _PrimaryButton(
                label: 'Get Started',
                onPressed: onGetStarted,
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: onRecover,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.contentSecondary,
                  ),
                  child: const Text('I have an account'),
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
// Screen 2: Benefits
// ---------------------------------------------------------------------------

class _BenefitsScreen extends StatelessWidget {
  const _BenefitsScreen({required this.onContinue});
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Everything you need\nto stay on track',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppColors.content,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Calm, focused, and built around you.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.contentSecondary,
                ),
          ),
          const SizedBox(height: 32),
          const _BenefitCard(
            icon: Icons.flag_outlined,
            title: 'Plan your goals',
            description:
                'Set clear goals and break them into weekly focus areas.',
          ),
          const SizedBox(height: 12),
          const _BenefitCard(
            icon: Icons.trending_up_rounded,
            title: 'Track your progress',
            description:
                'See how you\'re doing with smart insights and analytics.',
          ),
          const SizedBox(height: 12),
          const _BenefitCard(
            icon: Icons.auto_awesome_rounded,
            title: 'Reflect & improve',
            description:
                'Weekly reviews powered by AI help you grow consistently.',
          ),
          const Spacer(),
          _PrimaryButton(label: 'Continue', onPressed: onContinue),
        ],
      ),
    );
  }
}

class _BenefitCard extends StatelessWidget {
  const _BenefitCard({
    required this.icon,
    required this.title,
    required this.description,
  });
  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Green accent icon container
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.kiwi50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 22, color: AppColors.kiwi600),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColors.content,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.contentSecondary,
                        height: 1.5,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Screen 3: Life Areas
// ---------------------------------------------------------------------------

class _LifeAreasScreen extends StatelessWidget {
  const _LifeAreasScreen({
    required this.selectedAreas,
    required this.onToggle,
    required this.onContinue,
  });
  final Set<String> selectedAreas;
  final void Function(String) onToggle;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What areas of life\nmatter most to you?',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppColors.content,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose at least one. We\'ll personalize your experience.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.contentSecondary,
                ),
          ),
          const SizedBox(height: 28),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 2.4,
              padding: EdgeInsets.zero,
              children: _lifeAreas.entries.map((e) {
                final selected = selectedAreas.contains(e.key);
                return GestureDetector(
                  onTap: () => onToggle(e.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.kiwi400 : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected
                            ? AppColors.kiwi400
                            : AppColors.borderSubtle,
                      ),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color:
                                    AppColors.kiwi400.withValues(alpha: 0.25),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          e.value.$1,
                          size: 20,
                          color: selected
                              ? Colors.white
                              : AppColors.contentSecondary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          e.value.$2,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: selected
                                    ? Colors.white
                                    : AppColors.content,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          _PrimaryButton(
            label: 'Continue',
            onPressed: selectedAreas.isNotEmpty ? onContinue : null,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Screen 4: Set Goal
// ---------------------------------------------------------------------------

class _GoalScreen extends StatelessWidget {
  const _GoalScreen({
    required this.controller,
    required this.selectedAreas,
    required this.onContinue,
  });
  final TextEditingController controller;
  final Set<String> selectedAreas;
  final VoidCallback onContinue;

  List<String> get _suggestions {
    final list = <String>[];
    for (final area in selectedAreas) {
      final areaSuggestions = _goalSuggestions[area];
      if (areaSuggestions != null) {
        list.addAll(areaSuggestions.take(2));
      }
    }
    return list.take(6).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Set your first goal',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppColors.content,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap a suggestion or type your own.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.contentSecondary,
                ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: controller,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 120,
            decoration: const InputDecoration(
              hintText: 'My goal is...',
              counterText: '',
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: controller,
              builder: (_, value, __) => SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _suggestions.map((s) {
                    final isSelected = value.text == s;
                    return GestureDetector(
                      onTap: () => controller.text = s,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.kiwi50 : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.kiwi400
                                : AppColors.borderSubtle,
                            width: isSelected ? 1.5 : 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Text(
                          s,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: isSelected
                                    ? AppColors.kiwi600
                                    : AppColors.content,
                                fontWeight: isSelected
                                    ? FontWeight.w500
                                    : FontWeight.w400,
                              ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder(
            valueListenable: controller,
            builder: (_, value, __) {
              final canContinue = value.text.trim().length >= 5;
              return _PrimaryButton(
                label: 'Continue',
                onPressed: canContinue ? onContinue : null,
              );
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Screen 5: Why
// ---------------------------------------------------------------------------

class _WhyScreen extends StatelessWidget {
  const _WhyScreen({
    required this.controller,
    required this.selectedWhy,
    required this.onSelectWhy,
    required this.onContinue,
    required this.onSkip,
  });
  final TextEditingController controller;
  final String selectedWhy;
  final void Function(String) onSelectWhy;
  final VoidCallback onContinue;
  final VoidCallback onSkip;

  static const _whyOptions = [
    'I want to grow',
    'I want to feel accomplished',
    'I want to be healthier',
    'I want financial freedom',
    'I want more balance',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Why does this\ngoal matter?',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppColors.content,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Optional — your "why" keeps you going.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.contentSecondary,
                ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _whyOptions.map((w) {
              final isSelected = selectedWhy == w;
              return GestureDetector(
                onTap: () => onSelectWhy(isSelected ? '' : w),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.kiwi50 : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.kiwi400
                          : AppColors.borderSubtle,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    w,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isSelected
                              ? AppColors.kiwi600
                              : AppColors.content,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: controller,
            textCapitalization: TextCapitalization.sentences,
            maxLines: 2,
            minLines: 1,
            decoration: const InputDecoration(
              hintText: 'Or write your own...',
            ),
          ),
          const Spacer(),
          _PrimaryButton(label: 'Continue', onPressed: onContinue),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: onSkip,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.contentTertiary,
              ),
              child: const Text('Skip'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Screen 6: Pro Upsell
// ---------------------------------------------------------------------------

class _ProUpsellScreen extends StatelessWidget {
  const _ProUpsellScreen({
    required this.onStartTrial,
    required this.onSkip,
    this.isLoading = false,
    this.error,
  });
  final VoidCallback onStartTrial;
  final VoidCallback onSkip;
  final bool isLoading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Premium badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.kiwi50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.kiwi200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.workspace_premium_rounded,
                  size: 16,
                  color: AppColors.kiwi600,
                ),
                const SizedBox(width: 6),
                Text(
                  'Kinwii Pro',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.kiwi600,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          Text(
            'Unlock the full\nexperience',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppColors.content,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Everything you need to stay focused and grow.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.contentSecondary,
                ),
          ),
          const SizedBox(height: 28),

          // Benefits card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderSubtle),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Column(
              children: [
                _ProBenefitRow(text: 'Unlimited goals'),
                SizedBox(height: 14),
                _ProBenefitRow(text: 'AI-powered coaching & insights'),
                SizedBox(height: 14),
                _ProBenefitRow(text: 'Smart daily focus suggestions'),
                SizedBox(height: 14),
                _ProBenefitRow(text: 'Progress analytics'),
              ],
            ),
          ),

          const Spacer(),

          if (error != null) ...[
            Center(
              child: Text(
                error!,
                style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13),
              ),
            ),
            const SizedBox(height: 8),
          ],
          _PrimaryButton(
            label: 'Continue with Free Trial',
            onPressed: onStartTrial,
            isLoading: isLoading,
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              'Free for 3 days. No commitment.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.contentTertiary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProBenefitRow extends StatelessWidget {
  const _ProBenefitRow({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            color: AppColors.kiwi50,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_rounded,
            size: 14,
            color: AppColors.kiwi600,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.content,
                fontWeight: FontWeight.w500,
              ),
        ),
      ],
    );
  }
}

