import 'package:flutter_test/flutter_test.dart';
import 'package:kinwii/models/task.dart';

Task _task({
  String? quarterId,
  EnergyType energyType = EnergyType.deep,
}) =>
    Task(
      id: 'tid',
      userId: 'uid',
      weeklyPlanId: 'pid',
      quarterId: quarterId,
      title: 'Test task',
      date: DateTime(2026, 5, 18),
      completed: false,
      energyType: energyType,
      createdAt: DateTime(2026, 5, 18),
    );

void main() {
  group('Task.isBigRock', () {
    test('true when quarterId is set and energy is deep', () {
      final t = _task(quarterId: 'goal-1', energyType: EnergyType.deep);
      expect(t.isBigRock, isTrue);
    });

    test('false when quarterId is null', () {
      final t = _task(quarterId: null, energyType: EnergyType.deep);
      expect(t.isBigRock, isFalse);
    });

    test('false when energy is not deep', () {
      for (final e in [
        EnergyType.admin,
        EnergyType.creative,
        EnergyType.personal,
      ]) {
        final t = _task(quarterId: 'goal-1', energyType: e);
        expect(t.isBigRock, isFalse,
            reason: 'energy $e should not qualify as big rock');
      }
    });

    test('false when both quarterId is null and energy is not deep', () {
      final t = _task(quarterId: null, energyType: EnergyType.admin);
      expect(t.isBigRock, isFalse);
    });

    test('a Task with same fields except quarterId has different isBigRock', () {
      final withGoal = _task(quarterId: 'g', energyType: EnergyType.deep);
      final withoutGoal = _task(quarterId: null, energyType: EnergyType.deep);
      expect(withGoal.isBigRock, isTrue);
      expect(withoutGoal.isBigRock, isFalse);
    });
  });
}
