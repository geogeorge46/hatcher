import 'package:flutter_test/flutter_test.dart';
import 'package:hatcher/providers/day_counter_provider.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
  });

  group('Day Counter Logic', () {
    test('Placement day is Day 1', () {
      final now = DateTime(2026, 11, 10, 14, 30); // 10 Nov afternoon
      final day = computeIncubationDay('2026-11-10', now);
      expect(day, equals(1));
    });

    test('1 day elapsed is Day 2', () {
      final now = DateTime(2026, 11, 11, 8, 30); // 11 Nov morning
      final day = computeIncubationDay('2026-11-10', now);
      expect(day, equals(2));
    });

    test('20 days elapsed is Day 21 (Hatch Day)', () {
      final now = DateTime(2026, 11, 30, 20, 30); // 30 Nov evening (10 Nov + 20 days)
      final day = computeIncubationDay('2026-11-10', now);
      expect(day, equals(21));
    });

    test('Edge case: Device clock slightly behind placement date clamps to Day 1', () {
      final pastDate = DateTime(2026, 11, 9, 23, 59); // Clock is before placement day
      final day = computeIncubationDay('2026-11-10', pastDate);
      expect(day, equals(1));
    });

    test('Hatch date is exactly 21 days after placement date', () {
      final hatchDate = computeHatchDate('2026-11-10');
      final formatted = DateFormat('yyyy-MM-dd').format(hatchDate);
      expect(formatted, equals('2026-12-01'));
    });

    test('Timezone boundary: 23:59 vs 00:01 advances day counter', () {
      final kolkata = tz.getLocation('Asia/Kolkata');
      final nightBefore = tz.TZDateTime(kolkata, 2026, 11, 10, 23, 59, 50);
      final nextMorning = tz.TZDateTime(kolkata, 2026, 11, 11, 0, 0, 10);

      final dayNight = computeIncubationDay('2026-11-10', nightBefore);
      final dayMorning = computeIncubationDay('2026-11-10', nextMorning);

      expect(dayNight, equals(1));
      expect(dayMorning, equals(2));
    });
  });
}
