// OnboardingScreen - Under-2-minute setup flow.
// Usage: Registered as /onboarding route (no shell).
//
// Steps:
//   1. Select quarter (Q1–Q4 grid, auto-selects current quarter)
//   2. Enter goal title (min 10 chars to proceed)
//   3. Write why it matters (optional)
//   4. Set first weekly intent → "Start my week"
//
// On completion: POST /goals + POST /week → navigate /today + mark onboarding done.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../features/auth/presentation/screens/login_screen.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

int _currentQuarter() => ((DateTime.now().month - 1) ~/ 3) + 1; // 1-4

DateTime _quarterStart(int year, int q) =>
    DateTime(year, (q - 1) * 3 + 1, 1);

DateTime _quarterEnd(int year, int q) {
  final endMonth = q * 3;
  final lastDay = DateTime(year, endMonth + 1, 0).day;
  return DateTime(year, endMonth, lastDay);
}

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

  // Step 1
  int _selectedQuarter = _currentQuarter();
  final int _selectedYear = DateTime.now().year;

  // Step 2
  final _goalTitleController = TextEditingController();

  // Step 3
  final _whyController = TextEditingController();

  // Step 4
  final _intentController = TextEditingController();

  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _pageController.dispose();
    _goalTitleController.dispose();
    _whyController.dispose();
    _intentController.dispose();
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

  bool _canAdvance() {
    switch (_currentPage) {
      case 0:
        return true; // quarter always selected
      case 1:
        return _goalTitleController.text.trim().length >= 10;
      case 2:
        return true; // why is optional
      case 3:
        return _intentController.text.trim().isNotEmpty;
      default:
        return false;
    }
  }

  Future<void> _complete() async {
    if (!_canAdvance()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = ref.read(apiServiceProvider);
      final auth = ref.read(authServiceProvider);

      final start = _quarterStart(_selectedYear, _selectedQuarter);
      final end = _quarterEnd(_selectedYear, _selectedQuarter);

      // POST /goals
      final goalResponse = await api.post('/goals', data: {
        'title': _goalTitleController.text.trim(),
        'why': _whyController.text.trim(),
        'start_date': DateFormat('yyyy-MM-dd').format(start),
        'end_date': DateFormat('yyyy-MM-dd').format(end),
      });

      final goalId = goalResponse.data['id'] as String;

      // POST /week
      final weekStart = _mondayOfCurrentWeek();
      await api.post('/week', data: {
        'quarter_id': goalId,
        'week_start_date': DateFormat('yyyy-MM-dd').format(weekStart),
        'intent': _intentController.text.trim(),
      });

      await auth.setOnboardingComplete();

      if (mounted) context.go('/today');
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Something went wrong. Please try again.';
        });
      }
    }
  }

  DateTime _mondayOfCurrentWeek() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day - (now.weekday - 1));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Step indicator dots
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: _StepDots(currentPage: _currentPage, totalPages: 4),
            ),

            // Page content
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _Step1Quarter(
                    selectedQuarter: _selectedQuarter,
                    selectedYear: _selectedYear,
                    onSelect: (q) => setState(() => _selectedQuarter = q),
                  ),
                  _Step2GoalTitle(
                    controller: _goalTitleController,
                    onChanged: () => setState(() {}),
                  ),
                  _Step3Why(controller: _whyController),
                  _Step4Intent(controller: _intentController),
                ],
              ),
            ),

            // Error message
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),

            // Navigation buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.kiwi400,
                      ),
                    )
                  : Row(
                      children: [
                        if (_currentPage > 0)
                          Expanded(
                            flex: 1,
                            child: OutlinedButton(
                              onPressed: () => _goToPage(_currentPage - 1),
                              child: const Text('Back'),
                            ),
                          ),
                        if (_currentPage > 0) const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: _canAdvance()
                                ? () {
                                    if (_currentPage < 3) {
                                      _goToPage(_currentPage + 1);
                                    } else {
                                      _complete();
                                    }
                                  }
                                : null,
                            child: Text(
                              _currentPage == 3
                                  ? 'Start my week'
                                  : 'Continue',
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step indicator dots
// ---------------------------------------------------------------------------

class _StepDots extends StatelessWidget {
  const _StepDots({required this.currentPage, required this.totalPages});

  final int currentPage;
  final int totalPages;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(totalPages, (i) {
        final isActive = i == currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive ? AppColors.kiwi400 : AppColors.borderSubtle,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 1 — Select quarter
// ---------------------------------------------------------------------------

class _Step1Quarter extends StatelessWidget {
  const _Step1Quarter({
    required this.selectedQuarter,
    required this.selectedYear,
    required this.onSelect,
  });

  final int selectedQuarter;
  final int selectedYear;
  final void Function(int quarter) onSelect;

  static const _quarterDescriptions = {
    1: 'Jan – Mar',
    2: 'Apr – Jun',
    3: 'Jul – Sep',
    4: 'Oct – Dec',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Which quarter are you planning?',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppColors.content,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'We auto-selected the current quarter for you.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.contentSecondary,
                ),
          ),
          const SizedBox(height: 32),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.8,
            children: List.generate(4, (i) {
              final q = i + 1;
              final isSelected = selectedQuarter == q;
              return GestureDetector(
                onTap: () => onSelect(q),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.kiwi400 : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.kiwi400
                          : AppColors.borderSubtle,
                      width: isSelected ? 2 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Q$q',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(
                              color: isSelected
                                  ? Colors.white
                                  : AppColors.content,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _quarterDescriptions[q] ?? '',
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: isSelected
                                      ? Colors.white.withOpacity(0.85)
                                      : AppColors.contentSecondary,
                                ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 2 — Goal title
// ---------------------------------------------------------------------------

class _Step2GoalTitle extends StatelessWidget {
  const _Step2GoalTitle({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What is your #1 goal this quarter?',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppColors.content,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Be specific. One clear goal beats many vague ones.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.contentSecondary,
                ),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 120,
            onChanged: (_) => onChanged(),
            decoration: const InputDecoration(
              labelText: 'Goal title',
              hintText: 'e.g. Launch beta to 100 users',
              counterText: '',
            ),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder(
            valueListenable: controller,
            builder: (_, value, __) {
              final len = value.text.trim().length;
              final ready = len >= 10;
              return Text(
                ready
                    ? 'Looks good — keep going.'
                    : 'At least 10 characters (${10 - len} more)',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color:
                          ready ? AppColors.kiwi500 : AppColors.contentTertiary,
                    ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 3 — Why it matters
// ---------------------------------------------------------------------------

class _Step3Why extends StatelessWidget {
  const _Step3Why({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Why does this goal matter?',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppColors.content,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Optional — but your "why" keeps you going when it gets hard.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.contentSecondary,
                ),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: controller,
            autofocus: true,
            maxLines: 4,
            minLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Why it matters (optional)',
              hintText:
                  'e.g. Proves the concept and gives us data to raise a round',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 4 — First weekly intent
// ---------------------------------------------------------------------------

class _Step4Intent extends StatelessWidget {
  const _Step4Intent({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Set your intent for this week.',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppColors.content,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'One clear sentence about what this week is for.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.contentSecondary,
                ),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Weekly intent',
              hintText: 'e.g. Ship the onboarding flow and get 3 user calls',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.kiwi50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.tips_and_updates_outlined,
                  size: 16,
                  color: AppColors.kiwi600,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'A good weekly intent is specific, achievable, and connects directly to your quarterly goal.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.kiwi700,
                          height: 1.5,
                        ),
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
