// SignInScreen — combined sign in / create account page.
// Default mode: sign in (email + password).
// Toggle: "Don't have an account? Create one" switches to create mode.
// Create account uses /auth/register (standalone, no anonymous account needed).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';
import '../../services/providers.dart';
import '../../services/subscription_service.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _isSignIn = true; // true = sign in (default), false = create account
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (email.isEmpty) {
      setState(() => _error = 'Please enter your email.');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    if (_isSignIn) {
      await _doSignIn(email, password);
    } else {
      await _doCreateAccount(email, password);
    }
  }

  Future<void> _doCreateAccount(String email, String password) async {
    try {
      final api = ref.read(apiServiceProvider);
      final auth = ref.read(authServiceProvider);
      final resp = await api.post('/auth/register', data: {
        'email': email,
        'password': password,
      });
      await auth.setToken(resp.data['access_token']);

      // Update name if provided
      final name = _nameCtrl.text.trim();
      if (name.isNotEmpty) {
        try {
          await api.put('/auth/me', data: {'name': name});
        } catch (_) {}
      }

      await ref.read(subscriptionProvider.notifier).refresh();
      await ref.read(subscriptionProvider.notifier).identifyUser();
      // Pop back with 'created' so onboarding can continue the wizard
      if (mounted) context.pop('created');
    } catch (e) {
      if (mounted) {
        // Check if it's a 409 (email already exists)
        final is409 = e.toString().contains('409');
        setState(() {
          _loading = false;
          if (is409) {
            _error = 'This email already has an account. Sign in instead.';
            _isSignIn = true;
          } else {
            _error = 'Could not create account. Please try again.';
          }
        });
      }
    }
  }

  Future<void> _doSignIn(String email, String password) async {
    try {
      final api = ref.read(apiServiceProvider);
      final auth = ref.read(authServiceProvider);
      final resp = await api.post('/auth/login', data: {
        'email': email,
        'password': password,
      });
      await auth.setToken(resp.data['access_token']);
      await auth.setOnboardingComplete();
      await auth.setOnboardingSeen();
      await ref.read(subscriptionProvider.notifier).refresh();
      await ref.read(subscriptionProvider.notifier).identifyUser();
      if (mounted) context.go('/today');
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Incorrect email or password.';
        });
      }
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
          icon: const Icon(Icons.arrow_back, color: AppColors.content),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isSignIn ? 'Sign in' : 'Create account',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppColors.content,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                _isSignIn
                    ? 'Sign in with your email and password.'
                    : 'Add an email and password to secure your account.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.contentSecondary,
                    ),
              ),
              const SizedBox(height: 32),
              if (!_isSignIn) ...[
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name'),
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _emailCtrl,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordCtrl,
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                      color: AppColors.contentTertiary,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
              ),
              if (_isSignIn) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => _showForgotPassword(context),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.contentSecondary,
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Forgot password?'),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: const TextStyle(
                        color: Color(0xFFDC2626), fontSize: 13)),
              ],
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(_isSignIn ? 'Sign in' : 'Create account'),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () {
                    setState(() {
                      _isSignIn = !_isSignIn;
                      _error = null;
                    });
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.contentSecondary,
                  ),
                  child: Text(
                    _isSignIn
                        ? "Don't have an account? Create one"
                        : 'Already have an account? Sign in',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showForgotPassword(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ForgotPasswordSheet(
        api: ref.read(apiServiceProvider),
        initialEmail: _emailCtrl.text.trim(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Forgot password — two-step: send code → verify code + new password
// ---------------------------------------------------------------------------

class _ForgotPasswordSheet extends StatefulWidget {
  const _ForgotPasswordSheet({required this.api, this.initialEmail});
  final dynamic api;
  final String? initialEmail;

  @override
  State<_ForgotPasswordSheet> createState() => _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends State<_ForgotPasswordSheet> {
  late final TextEditingController _emailCtrl;
  final _codeCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  bool _codeSent = false;
  bool _loading = false;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _newPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Please enter your email.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.api.post('/auth/forgot-password', data: {'email': email});
      if (mounted) {
        setState(() {
          _loading = false;
          _codeSent = true;
          _success = 'Reset code sent to $email';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not send reset code. Please try again.';
        });
      }
    }
  }

  Future<void> _resetPassword() async {
    final code = _codeCtrl.text.trim();
    final newPassword = _newPasswordCtrl.text;
    if (code.length != 6) {
      setState(() => _error = 'Please enter the 6-digit code.');
      return;
    }
    if (newPassword.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _success = null;
    });
    try {
      await widget.api.post('/auth/reset-password', data: {
        'email': _emailCtrl.text.trim(),
        'code': code,
        'new_password': newPassword,
      });
      if (mounted) {
        setState(() {
          _loading = false;
          _success = 'Password reset! You can now sign in.';
        });
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Invalid or expired code.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reset password',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.content,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            _codeSent
                ? 'Enter the 6-digit code and your new password.'
                : "We'll send a reset code to your email.",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.contentSecondary,
                ),
          ),
          const SizedBox(height: 20),
          if (!_codeSent) ...[
            TextField(
              controller: _emailCtrl,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _sendCode(),
            ),
          ] else ...[
            TextField(
              controller: _codeCtrl,
              decoration: const InputDecoration(labelText: 'Reset code'),
              keyboardType: TextInputType.number,
              maxLength: 6,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newPasswordCtrl,
              decoration: const InputDecoration(labelText: 'New password'),
              obscureText: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _resetPassword(),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style:
                    const TextStyle(color: Color(0xFFDC2626), fontSize: 13)),
          ],
          if (_success != null) ...[
            const SizedBox(height: 10),
            Text(_success!,
                style: TextStyle(color: AppColors.kiwi600, fontSize: 13)),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : (_codeSent ? _resetPassword : _sendCode),
              child: _loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(_codeSent ? 'Reset password' : 'Send code'),
            ),
          ),
          if (_codeSent) ...[
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: _loading ? null : _sendCode,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.contentSecondary,
                ),
                child: const Text('Resend code'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
