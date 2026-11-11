import 'package:flutter_test/flutter_test.dart';
import 'package:hatcher/data/models/escalation_models.dart';

void main() {
  group('Phase 2 Phone Validation & Escalation Defaults', () {
    test('Accepts valid E.164 international phone numbers', () {
      expect(isValidE164Phone('+919876543210'), isTrue);
      expect(isValidE164Phone(' +919876543210 '), isTrue);
      expect(isValidE164Phone('+14155552671'), isTrue);
    });

    test('Rejects invalid or missing country code numbers', () {
      expect(isValidE164Phone('9876543210'), isFalse);
      expect(isValidE164Phone('+0123456789'), isFalse);
      expect(isValidE164Phone('abc'), isFalse);
      expect(isValidE164Phone('+91 98765 43210'), isFalse);
      expect(isValidE164Phone(''), isFalse);
    });

    test('Default escalation ladder matches specification', () {
      final defaults = EscalationSettings.defaults();
      expect(defaults.enabled, isTrue);
      expect(defaults.callOrder, equals(['George', 'Dolly', 'Leo']));
      expect(defaults.stopAfterMinutes, equals(60));
      expect(defaults.steps.map((s) => s.offsetMinutes).toList(),
          equals([10, 20, 30, 45]));
    });
  });
}
