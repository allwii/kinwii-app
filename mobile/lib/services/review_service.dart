// ReviewService — triggers the native App Store / Play Store review prompt
// after meaningful user actions, with rate-limiting to avoid spamming.

import 'package:hive_flutter/hive_flutter.dart';
import 'package:in_app_review/in_app_review.dart';

class ReviewService {
  static const _boxName = 'kinwii_flags';
  static const _keyLastPrompt = 'review_last_prompt';
  static const _keyPromptCount = 'review_prompt_count';
  // Don't prompt until the user has accumulated at least this much score.
  static const _minCompletions = 3;

  // Minimum days between prompts (Apple may further limit on its side).
  static const _cooldownDays = 60;

  // Maximum times we'll ever request (Apple caps at ~3/year anyway).
  static const _maxPrompts = 3;

  static const _keyScore = 'review_score';

  /// Record a major action (task complete, daily reflection, weekly review).
  /// Adds 1.0 to the score.
  static Future<void> recordCompletion() => _record(1.0);

  /// Record a minor action (AI coach chat, task creation).
  /// Adds 0.5 to the score — contributes but takes longer to trigger.
  static Future<void> recordMinorAction() => _record(0.5);

  static Future<void> _record(double weight) async {
    final box = await Hive.openBox(_boxName);

    final score =
        (box.get(_keyScore, defaultValue: 0.0) as num).toDouble() + weight;
    await box.put(_keyScore, score);

    if (score < _minCompletions) return;

    final promptCount = box.get(_keyPromptCount, defaultValue: 0) as int;
    if (promptCount >= _maxPrompts) return;

    final lastPrompt = box.get(_keyLastPrompt) as String?;
    if (lastPrompt != null) {
      final last = DateTime.tryParse(lastPrompt);
      if (last != null &&
          DateTime.now().difference(last).inDays < _cooldownDays) {
        return;
      }
    }

    final inAppReview = InAppReview.instance;
    if (await inAppReview.isAvailable()) {
      await inAppReview.requestReview();
      await box.put(_keyPromptCount, promptCount + 1);
      await box.put(_keyLastPrompt, DateTime.now().toIso8601String());
    }
  }
}
