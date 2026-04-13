// OnboardingScreen — 7-screen high-conversion onboarding flow.
// 1. Welcome → 2. Benefits → 3. Life Areas → 4. Goal → 5. Why → 6. Pro → 7. Account

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../features/auth/presentation/screens/login_screen.dart';
import '../../../../services/google_auth_service.dart';
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
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isCreating = false;
  bool _isGoogleLoading = false;
  String? _error;

  @override
  void dispose() {
    _pageController.dispose();
    _goalCtrl.dispose();
    _whyCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
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
    if (_currentPage < 6) _goToPage(_currentPage + 1);
  }

  Future<void> _createAccount() async {
    if (_passwordCtrl.text.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters');
      return;
    }
    setState(() {
      _isCreating = true;
      _error = null;
    });
    try {
      final api = ref.read(apiServiceProvider);
      final auth = ref.read(authServiceProvider);

      final response = await api.post('/auth/register', data: {
        'email': _emailCtrl.text.trim(),
        'password': _passwordCtrl.text,
      });
      await auth.setToken(response.data['access_token']);
      await _submitGoalData(api);
      await auth.setOnboardingComplete();
      await auth.setOnboardingSeen();
      await ref.read(subscriptionProvider.notifier).refresh();
      if (mounted) context.go('/today');
    } catch (_) {
      if (mounted) {
        setState(() {
          _isCreating = false;
          _error = 'Registration failed. Email may already be in use.';
        });
      }
    }
  }

  Future<void> _googleSignIn() async {
    setState(() {
      _isGoogleLoading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiServiceProvider);
      final auth = ref.read(authServiceProvider);
      final googleAuth = GoogleAuthService(api, auth);
      await googleAuth.signIn();
      await _submitGoalData(api);
      await auth.setOnboardingComplete();
      await auth.setOnboardingSeen();
      await ref.read(subscriptionProvider.notifier).refresh();
      if (mounted) context.go('/today');
    } catch (_) {
      if (mounted) {
        setState(() {
          _isGoogleLoading = false;
          _error = 'Google sign-in failed. Please try again.';
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
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          // 1. Welcome
          _WelcomeScreen(
            onGetStarted: _next,
            onLogin: () => context.go('/auth/login'),
          ),
          // 2. Benefits
          _BenefitsScreen(onContinue: _next),
          // 3. Life areas
          _LifeAreasScreen(
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
          // 4. Goal
          _GoalScreen(
            controller: _goalCtrl,
            selectedAreas: _selectedAreas,
            onContinue: _next,
          ),
          // 5. Why
          _WhyScreen(
            controller: _whyCtrl,
            selectedWhy: _selectedWhy,
            onSelectWhy: (why) => setState(() => _selectedWhy = why),
            onContinue: _next,
            onSkip: _next,
          ),
          // 6. Pro upsell
          _ProUpsellScreen(
            onStartTrial: _next,
            onSkip: _next,
          ),
          // 7. Create account
          _CreateAccountScreen(
            emailCtrl: _emailCtrl,
            passwordCtrl: _passwordCtrl,
            isCreating: _isCreating,
            isGoogleLoading: _isGoogleLoading,
            error: _error,
            onCreateAccount: _createAccount,
            onGoogleSignIn: _googleSignIn,
            onLogin: () => context.go('/auth/login'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Screen 1: Welcome
// ---------------------------------------------------------------------------

class _WelcomeScreen extends StatelessWidget {
  const _WelcomeScreen({required this.onGetStarted, required this.onLogin});
  final VoidCallback onGetStarted;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.kiwi400, AppColors.kiwi600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 60, 32, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(flex: 2),
              Text(
                'Welcome to',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w400,
                    ),
              ),
              Text(
                'Kinwii',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 16),
              Text(
                'Plan with clarity.\nReflect with purpose.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.white.withValues(alpha: 0.8),
                      height: 1.5,
                    ),
              ),
              const Spacer(flex: 3),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onGetStarted,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.kiwi600,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Get Started'),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: GestureDetector(
                  onTap: onLogin,
                  child: Text(
                    'Already have an account? Log in',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
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
// Screen 2: Benefits
// ---------------------------------------------------------------------------

class _BenefitsScreen extends StatelessWidget {
  const _BenefitsScreen({required this.onContinue});
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.kiwi400, AppColors.kiwi500],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 40, 32, 40),
          child: Column(
            children: [
              const Spacer(),
              const _BenefitCard(
                icon: Icons.flag_outlined,
                title: 'Plan your goals',
                description:
                    'Set clear goals and break them into weekly focus areas.',
              ),
              const SizedBox(height: 16),
              const _BenefitCard(
                icon: Icons.trending_up,
                title: 'Track your progress',
                description:
                    'See how you\'re doing with smart insights and analytics.',
              ),
              const SizedBox(height: 16),
              const _BenefitCard(
                icon: Icons.auto_awesome,
                title: 'Reflect & improve',
                description:
                    'Weekly reviews powered by AI help you grow consistently.',
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.kiwi600,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Continue'),
                ),
              ),
            ],
          ),
        ),
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 32, color: Colors.white),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.8),
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
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'What areas of life\nmatter most to you?',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppColors.content,
                      fontWeight: FontWeight.w700,
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
                                        AppColors.kiwi400.withValues(alpha: 0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : [],
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
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed:
                      selectedAreas.isNotEmpty ? onContinue : null,
                  child: const Text('Continue'),
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
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
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
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _suggestions.map((s) {
                      return GestureDetector(
                        onTap: () => controller.text = s,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: AppColors.borderSubtle),
                          ),
                          child: Text(
                            s,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.content),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder(
                valueListenable: controller,
                builder: (_, value, __) {
                  final canContinue = value.text.trim().length >= 5;
                  return SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: canContinue ? onContinue : null,
                      child: const Text('Continue'),
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
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Why does this\ngoal matter?',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppColors.content,
                      fontWeight: FontWeight.w700,
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
                        color:
                            isSelected ? AppColors.kiwi400 : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.kiwi400
                              : AppColors.borderSubtle,
                        ),
                      ),
                      child: Text(
                        w,
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: isSelected
                                      ? Colors.white
                                      : AppColors.content,
                                  fontWeight: FontWeight.w500,
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
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onContinue,
                  child: const Text('Continue'),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: onSkip,
                  child: Text(
                    'Skip',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.contentTertiary,
                        ),
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
// Screen 6: Pro Upsell
// ---------------------------------------------------------------------------

class _ProUpsellScreen extends StatelessWidget {
  const _ProUpsellScreen({required this.onStartTrial, required this.onSkip});
  final VoidCallback onStartTrial;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.kiwi400, AppColors.kiwi700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 60, 32, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              const Icon(Icons.workspace_premium,
                  size: 48, color: Colors.white),
              const SizedBox(height: 20),
              Text(
                'Unlock the full\nexperience',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 24),
              const _ProBenefitRow(text: 'Unlimited goals'),
              const SizedBox(height: 12),
              const _ProBenefitRow(text: 'AI-powered coaching & insights'),
              const SizedBox(height: 12),
              const _ProBenefitRow(text: 'Smart daily focus suggestions'),
              const SizedBox(height: 12),
              const _ProBenefitRow(text: 'Progress analytics'),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onStartTrial,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.kiwi600,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Start 7-day free trial'),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: GestureDetector(
                  onTap: onSkip,
                  child: Text(
                    'Continue with Free',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
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

class _ProBenefitRow extends StatelessWidget {
  const _ProBenefitRow({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.check_circle,
            size: 20, color: Colors.white.withValues(alpha: 0.85)),
        const SizedBox(width: 12),
        Text(
          text,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.white.withValues(alpha: 0.9),
              ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Screen 7: Create Account
// ---------------------------------------------------------------------------

class _CreateAccountScreen extends StatelessWidget {
  const _CreateAccountScreen({
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.isCreating,
    required this.isGoogleLoading,
    this.error,
    required this.onCreateAccount,
    required this.onGoogleSignIn,
    required this.onLogin,
  });

  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final bool isCreating;
  final bool isGoogleLoading;
  final String? error;
  final VoidCallback onCreateAccount;
  final VoidCallback onGoogleSignIn;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Almost there!',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppColors.content,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Create an account to save your plan.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.contentSecondary,
                    ),
              ),
              const SizedBox(height: 32),

              // Google sign-in (primary)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: isGoogleLoading ? null : onGoogleSignIn,
                  icon: isGoogleLoading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Image.network(
                          'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                          height: 20,
                          width: 20,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.g_mobiledata, size: 20),
                        ),
                  label: const Text('Continue with Google'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),

              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'or',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.contentTertiary,
                          ),
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 20),

              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: passwordCtrl,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onCreateAccount(),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!,
                    style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isCreating ? null : onCreateAccount,
                  child: isCreating
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Create account'),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: onLogin,
                  child: const Text('Already have an account? Log in'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
