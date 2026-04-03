import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import 'login_screen.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  Future<void> _register() async {
    if (_passwordController.text.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final auth = ref.read(authServiceProvider);
      final api = ref.read(apiServiceProvider);

      // 1. Create account
      final response = await api.post('/auth/register', data: {
        'email': _emailController.text.trim(),
        'password': _passwordController.text,
      });
      final token = response.data['access_token'];
      await auth.setToken(token);

      // 2. Submit pending onboarding data collected before signup
      final pending = await auth.getPendingOnboarding();
      if (pending != null) {
        await _submitOnboardingData(api, pending);
        await auth.clearPendingOnboarding();
      }

      await auth.setOnboardingComplete();
      if (mounted) context.go('/today');
    } catch (e) {
      setState(
          () => _error = 'Registration failed. Email may already be in use.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitOnboardingData(dynamic api, Map<String, dynamic> data) async {
    // Save mission if provided
    final mission = data['mission'] as String? ?? '';
    if (mission.isNotEmpty) {
      await api.put('/mission', data: {'statement': mission});
    }

    // Create quarterly goal
    final goalResponse = await api.post('/goals', data: {
      'title': data['goal_title'],
      'why': data['goal_why'] ?? '',
      'start_date': data['start_date'],
      'end_date': data['end_date'],
    });

    final goalId = goalResponse.data['id'] as String;

    // Create first weekly plan
    await api.post('/week', data: {
      'quarter_id': goalId,
      'week_start_date': data['week_start_date'],
      'intent': data['intent'],
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Text(
                'Almost there!',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Create an account to save your plan.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.contentSecondary,
                    ),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _emailController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _register(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _register,
                  child: _isLoading
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
                  onPressed: () => context.go('/auth/login'),
                  child: const Text('Already have an account? Sign in'),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
