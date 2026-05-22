import 'package:flutter_test/flutter_test.dart';
import 'package:kinwii/features/today/data/goal_tips.dart';

void main() {
  group('categorizeGoal', () {
    test('returns null for null or empty input', () {
      expect(categorizeGoal(null), isNull);
      expect(categorizeGoal(''), isNull);
      expect(categorizeGoal('   '), isNull);
    });

    test('returns null when no keyword matches', () {
      expect(categorizeGoal('Buy a new mattress'), isNull);
      expect(categorizeGoal('Visit grandma'), isNull);
    });

    test('fitness keywords map to fitness', () {
      expect(categorizeGoal('Run a half marathon'), 'fitness');
      expect(categorizeGoal('Get to the gym 3x/week'), 'fitness');
      expect(categorizeGoal('Lose 10 lbs'), 'fitness');
      expect(categorizeGoal('Daily yoga'), 'fitness');
      // case-insensitive
      expect(categorizeGoal('STRENGTH TRAINING'), 'fitness');
    });

    test('learning keywords map to learning', () {
      expect(categorizeGoal('Read 12 books this year'), 'learning');
      expect(categorizeGoal('Learn Spanish'), 'learning');
      expect(categorizeGoal('Complete React course'), 'learning');
      expect(categorizeGoal('Get AWS certification'), 'learning');
    });

    test('finance keywords map to finance', () {
      expect(categorizeGoal('Save \$10k'), 'finance');
      expect(categorizeGoal('Pay off debt'), 'finance');
      expect(categorizeGoal('Invest monthly'), 'finance');
      expect(categorizeGoal('Build wealth'), 'finance');
    });

    test('career keywords map to career', () {
      expect(categorizeGoal('Get a promotion'), 'career');
      expect(categorizeGoal('Launch my startup'), 'career');
      expect(categorizeGoal('Start a side hustle'), 'career');
    });

    test('mindfulness keywords map to mindfulness', () {
      expect(categorizeGoal('Meditate daily'), 'mindfulness');
      expect(categorizeGoal('Reduce stress'), 'mindfulness');
      expect(categorizeGoal('Journal every morning'), 'mindfulness');
    });

    test('creative keywords map to creative', () {
      expect(categorizeGoal('Write a novel'), 'creative');
      expect(categorizeGoal('Design my portfolio'), 'creative');
      expect(categorizeGoal('Paint every weekend'), 'creative');
    });

    test('first matching category wins (fitness before learning)', () {
      // contains both "run" (fitness) and "book" (learning) — fitness comes
      // first in the matching order
      expect(categorizeGoal('Run while listening to audiobook'), 'fitness');
    });
  });

  group('tipsForGoal', () {
    test('returns generic-only pool when category is null', () {
      final tips = tipsForGoal(null);
      expect(tips, equals(genericTips));
    });

    test('returns generic-only pool for unmatched goals', () {
      final tips = tipsForGoal('Visit Paris');
      expect(tips, equals(genericTips));
    });

    test('fitness goals start with fitness tips', () {
      final tips = tipsForGoal('Run 3x per week');
      expect(tips.length, fitnessTips.length + genericTips.length);
      expect(tips.first, fitnessTips.first);
      expect(tips.last, genericTips.last);
    });

    test('learning goals start with learning tips', () {
      final tips = tipsForGoal('Read 30 books');
      expect(tips.first, learningTips.first);
    });

    test('finance goals start with finance tips', () {
      final tips = tipsForGoal('Save for a house');
      expect(tips.first, financeTips.first);
    });

    test('career goals start with career tips', () {
      final tips = tipsForGoal('Get promoted to senior');
      expect(tips.first, careerTips.first);
    });

    test('mindfulness goals start with mindfulness tips', () {
      final tips = tipsForGoal('Meditate 10 min daily');
      expect(tips.first, mindfulnessTips.first);
    });

    test('creative goals start with creative tips', () {
      final tips = tipsForGoal('Write a song every week');
      expect(tips.first, creativeTips.first);
    });

    test('every pool is non-empty', () {
      for (final goal in [
        null,
        'random goal',
        'run',
        'learn',
        'invest',
        'career',
        'meditate',
        'write',
      ]) {
        final tips = tipsForGoal(goal);
        expect(tips, isNotEmpty,
            reason: 'tipsForGoal($goal) should never return empty');
      }
    });

    test('generic tips always present at the end', () {
      final categoryGoals = [
        'run',
        'read',
        'save',
        'promotion',
        'meditate',
        'write',
      ];
      for (final goal in categoryGoals) {
        final tips = tipsForGoal(goal);
        // The last several entries should be the generic tips
        final tail = tips.sublist(tips.length - genericTips.length);
        expect(tail, equals(genericTips),
            reason: 'generic tips should be appended for goal "$goal"');
      }
    });
  });
}
