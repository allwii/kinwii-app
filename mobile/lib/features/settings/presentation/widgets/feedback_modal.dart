import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../services/api_service.dart';

class FeedbackModal extends StatefulWidget {
  const FeedbackModal({
    super.key,
    required this.api,
    this.userEmail,
  });

  final ApiService api;

  /// If the user already has a linked email, pass it here.
  /// The email field will be hidden and the email sent automatically.
  final String? userEmail;

  @override
  State<FeedbackModal> createState() => _FeedbackModalState();
}

class _FeedbackModalState extends State<FeedbackModal> {
  final _msgCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  bool get _hasLinkedEmail => widget.userEmail != null;

  @override
  void dispose() {
    _msgCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final message = _msgCtrl.text.trim();
    if (message.isEmpty) {
      setState(() => _error = 'Please enter your feedback.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = <String, dynamic>{'message': message};
      // Include email: linked email takes priority, otherwise use the optional input
      final email = widget.userEmail ?? _emailCtrl.text.trim();
      if (email.isNotEmpty) {
        data['email'] = email;
      }
      await widget.api.post('/feedback', data: data);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thanks for your feedback!')),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not send feedback. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    return SizedBox(
      height: screenHeight * 0.75,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset > 0
            ? bottomInset
            : MediaQuery.of(context).padding.bottom),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Help & Feedback',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: AppColors.content,
                            )),
                    const SizedBox(height: 4),
                    Text(
                      'Tell us what you think or report an issue.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.contentSecondary,
                          ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _msgCtrl,
                      autofocus: true,
                      maxLines: null,
                      minLines: 8,
                      textCapitalization: TextCapitalization.sentences,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.content,
                            height: 1.5,
                          ),
                      decoration: InputDecoration(
                        hintText: 'Your feedback...',
                        hintStyle:
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: AppColors.contentTertiary,
                                ),
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: AppColors.borderSubtle),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: AppColors.borderSubtle),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: AppColors.kiwi400),
                        ),
                        contentPadding: const EdgeInsets.all(16),
                      ),
                    ),
                    if (!_hasLinkedEmail) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Want to hear back from us? Add your email (optional)',
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppColors.contentSecondary,
                                ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          hintText: 'your@email.com',
                          hintStyle: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppColors.contentTertiary),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: AppColors.borderSubtle),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: AppColors.borderSubtle),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: AppColors.kiwi400),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(_error!,
                          style: const TextStyle(
                              color: Color(0xFFDC2626), fontSize: 13)),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Submit'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
