import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/features/reminders/presentation/add_reminder_screen.dart';

void main() {
  group('medicationFrequencyToApi', () {
    test('maps Title Case UI labels to canonical snake_case', () {
      expect(medicationFrequencyToApi('Daily'), 'daily');
      expect(medicationFrequencyToApi('Twice Daily'), 'twice_daily');
      expect(medicationFrequencyToApi('Three Times Daily'), 'three_times_daily');
      expect(medicationFrequencyToApi('Weekly'), 'weekly');
      expect(medicationFrequencyToApi('Monthly'), 'monthly');
      expect(medicationFrequencyToApi('As Needed'), 'as_needed');
    });
  });
}
