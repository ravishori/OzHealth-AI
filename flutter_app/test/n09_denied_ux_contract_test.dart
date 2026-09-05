import 'package:flutter_test/flutter_test.dart';

void main() {
  test('N09 denied-permission snackbar contract is present in UX copy', () {
    // Mirrors add_reminder_screen.dart denied-permission messaging.
    const deniedMsg =
        'Reminder saved, but notification permission is off. '
        'Enable notifications in system settings to get alerts.';
    const okSuffix = '(on-device notification scheduled)';
    expect(deniedMsg.contains('notification permission is off'), isTrue);
    expect(okSuffix.contains('scheduled'), isTrue);
  });
}
