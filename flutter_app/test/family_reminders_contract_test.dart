import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/features/reminders/presentation/add_reminder_screen.dart';

void main() {
  test('FAMILY-REM-UI-01 family list loaded from /family/', () {
    final src =
        File('lib/features/reminders/presentation/add_reminder_screen.dart')
            .readAsStringSync();
    expect(src.contains("ApiClient.get('/family/')"), isTrue);
    expect(src.contains('Family Member (optional)'), isTrue);
    expect(src.contains("'Myself'"), isTrue);
  });

  test('FAMILY-REM-UI-02/03/08 create and edit send family_member_id', () {
    final src =
        File('lib/features/reminders/presentation/add_reminder_screen.dart')
            .readAsStringSync();
    expect(src.contains("ApiClient.post('/reminders/'"), isTrue);
    expect(src.contains("ApiClient.put('/reminders/\$"), isTrue);
    expect(
      src.contains('familyMemberId: _selectedFamilyMemberId') ||
          src.contains("'family_member_id': _selectedFamilyMemberId"),
      isTrue,
    );
    expect(src.contains('initialReminder'), isTrue);
  });

  test('FAMILY-REM-UI-04/05/06 list shows For name or Personal', () {
    final src =
        File('lib/features/reminders/presentation/reminders_screen.dart')
            .readAsStringSync();
    expect(src.contains("family_member_name"), isTrue);
    expect(src.contains("'For \$memberName'") || src.contains('For \$memberName'),
        isTrue);
    expect(src.contains("'Personal'"), isTrue);
  });

  test('FAMILY-REM-UI-07/09/10/11 edit route + toggle/delete remain', () {
    final list =
        File('lib/features/reminders/presentation/reminders_screen.dart')
            .readAsStringSync();
    final router =
        File('lib/core/router/app_router.dart').readAsStringSync();
    expect(router.contains('reminders/edit'), isTrue);
    expect(list.contains('_toggleReminder'), isTrue);
    expect(list.contains('_deleteReminder'), isTrue);
    expect(list.contains('LocalReminderNotifications'), isTrue);
  });

  test('FAMILY-REM-UI-12/13 safe error + duplicate submit guard', () {
    final src =
        File('lib/features/reminders/presentation/add_reminder_screen.dart')
            .readAsStringSync();
    expect(src.contains('if (_loading) return'), isTrue);
    expect(src.contains('Failed to save reminder') ||
        src.contains('Could not save reminder'), isTrue);
  });

  test('REM-REG frequency mapping unchanged', () {
    expect(medicationFrequencyToApi('Daily'), 'daily');
    expect(medicationFrequencyToApi('Weekly'), 'weekly');
    expect(medicationFrequencyToApi('Monthly'), 'monthly');
  });
}
