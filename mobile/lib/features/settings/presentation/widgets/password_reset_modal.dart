// PasswordResetModal — 3-step flow: enter email → enter code → new password.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../services/api_service.dart';

class PasswordResetModal extends StatefulWidget {
  const PasswordResetModal({
    super.key,
    required this.api,
    this.initialEmail,
  });

  final ApiService api;
  final String? initialEmail;

  @override
  State<PasswordResetModal> createState() => _PasswordResetModalState();
}

class _PasswordResetModalState extends State<PasswordResetModal> {
  int _step = 0; // 0=email, 1=code, 2=new password
  bool _loading = false;
  String? _error;

  late final TextEditingController _emailCtrl;
  final _codeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
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
          _step = 1;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not send code. Try again.';
        });
      }
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    setState(() {
      _error = null;
      _step = 2;
    });
  }

  Future<void> _resetPassword() async {
    final password = _passwordCtrl.text;
    final confirm = _confirmCtrl.text;
    if (password.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    if (password != confirm) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.api.post('/auth/reset-password', data: {
        'email': _emailCtrl.text.trim(),
        'code': _codeCtrl.text.trim(),
        'new_password': password,
      });
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password updated successfully.')),
        );
      }
    } on DioException catch (e) {
      final detail = e.response?.data?['detail'] as String?;
      if (mounted) {
        setState(() {
          _loading = false;
          _error = detail ?? 'Reset failed. Try again.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Reset failed. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            _step == 0
                ? 'Reset password'
                : _step == 1
                    ? 'Enter code'
                    : 'New password',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.content,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            _step == 0
                ? 'We\'ll send a 6-digit code to your email.'
                : _step == 1
                    ? 'We sent a code to ${_emailCtrl.text.trim()}'
                    : 'Choose a new password (min 8 characters).',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.contentSecondary,
                ),
          ),
          const SizedBox(height: 20),

          // Step 0: Email
          if (_step == 0) ...[
            TextField(
              controller: _emailCtrl,
              autofocus: widget.initialEmail == null,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _sendCode(),
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'your@email.com',
              ),
            ),
          ],

          // Step 1: Code
          if (_step == 1) ...[
            TextField(
              controller: _codeCtrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _verifyCode(),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    letterSpacing: 8,
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                counterText: '',
                hintText: '000000',
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: _loading ? null : _sendCode,
                child: const Text('Resend code'),
              ),
            ),
          ],

          // Step 2: New password
          if (_step == 2) ...[
            TextField(
              controller: _passwordCtrl,
              autofocus: true,
              obscureText: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'New password',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmCtrl,
              obscureText: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _resetPassword(),
              decoration: const InputDecoration(
                labelText: 'Confirm password',
              ),
            ),
          ],

          // Error
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: const TextStyle(color: Colors.red, fontSize: 13)),
          ],

          const SizedBox(height: 20),

          // Action button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading
                  ? null
                  : _step == 0
                      ? _sendCode
                      : _step == 1
                          ? _verifyCode
                          : _resetPassword,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _step == 0
                          ? 'Send code'
                          : _step == 1
                              ? 'Verify'
                              : 'Reset password',
                    ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
