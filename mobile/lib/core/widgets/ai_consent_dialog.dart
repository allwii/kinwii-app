// AI Data Consent Dialog — shown once before any AI feature is used.
// Required by App Store Guideline 5.1.1(i) for apps that share user
// data with third-party AI services.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';

/// Shows a one-time consent dialog explaining what data is sent to OpenAI.
/// Returns true if the user consents, false if they decline.
Future<bool> showAiConsentDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.auto_awesome, color: AppColors.kiwi500, size: 22),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('AI Features', style: TextStyle(fontSize: 18)),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Kinwii uses AI to provide personalized coaching, daily focus suggestions, and reflection insights.',
              style: TextStyle(height: 1.5),
            ),
            const SizedBox(height: 16),
            const Text(
              'What data is shared:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            _bullet('Your goals, weekly intents, and task titles'),
            _bullet('Your weekly reflection responses'),
            _bullet('Your messages to the AI Coach'),
            const SizedBox(height: 16),
            const Text(
              'Who receives this data:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            _bullet('OpenAI — to generate AI responses'),
            const SizedBox(height: 16),
            const Text(
              'Your data is sent securely via our server. It is not stored by OpenAI for training purposes.',
              style: TextStyle(height: 1.5, color: AppColors.contentSecondary),
            ),
            const SizedBox(height: 12),
            RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.contentSecondary,
                  height: 1.4,
                ),
                children: [
                  const TextSpan(text: 'For more details, see our '),
                  TextSpan(
                    text: 'Privacy Policy',
                    style: const TextStyle(
                      color: AppColors.kiwi600,
                      decoration: TextDecoration.underline,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => launchUrl(
                            Uri.parse('https://kinwii.com/privacy'),
                            mode: LaunchMode.externalApplication,
                          ),
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(
            'Not now',
            style: TextStyle(color: AppColors.contentSecondary),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('I agree'),
        ),
      ],
    ),
  );
  return result ?? false;
}

Widget _bullet(String text) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('  •  ', style: TextStyle(color: AppColors.contentSecondary)),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  height: 1.4, color: AppColors.contentSecondary)),
        ),
      ],
    ),
  );
}
