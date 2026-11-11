import 'package:flutter_test/flutter_test.dart';
import 'package:hatcher/providers/day_counter_provider.dart';

void main() {
  group('Lockdown (Day-18) Logic', () {
    const defaultStopFromDay = 18;

    test('Day 17 is NOT lockdown (alarms active)', () {
      final isLockdown = isLockdownDay(day: 17, stopFromDay: defaultStopFromDay);
      expect(isLockdown, isFalse);
    });

    test('Day 18 enters lockdown (alarms stop)', () {
      final isLockdown = isLockdownDay(day: 18, stopFromDay: defaultStopFromDay);
      expect(isLockdown, isTrue);
    });

    test('Days 19, 20, 21 remain in lockdown', () {
      expect(isLockdownDay(day: 19, stopFromDay: defaultStopFromDay), isTrue);
      expect(isLockdownDay(day: 20, stopFromDay: defaultStopFromDay), isTrue);
      expect(isLockdownDay(day: 21, stopFromDay: defaultStopFromDay), isTrue);
    });

    test('stopFromDay = 0 means alarms never stop (no lockdown)', () {
      expect(isLockdownDay(day: 18, stopFromDay: 0), isFalse);
      expect(isLockdownDay(day: 20, stopFromDay: 0), isFalse);
      expect(isLockdownDay(day: 21, stopFromDay: 0), isFalse);
    });

    test('Custom stopFromDay = 15 activates lockdown on Day 15', () {
      expect(isLockdownDay(day: 14, stopFromDay: 15), isFalse);
      expect(isLockdownDay(day: 15, stopFromDay: 15), isTrue);
      expect(isLockdownDay(day: 16, stopFromDay: 15), isTrue);
    });
  });
}
