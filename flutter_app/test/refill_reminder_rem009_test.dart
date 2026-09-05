import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/core/notifications/local_reminder_notifications.dart';
import 'package:vitapulse_ai/features/reminders/presentation/add_reminder_screen.dart';

void main() {
  group('HN-REM-009 refill payload + notification contracts', () {
    test('REM9-07 create form payload sends refill_date', () {
      final payload = buildReminderSavePayload(
        medicineName: 'Amoxicillin',
        dosage: '250mg',
        frequencyApi: 'daily',
        times: ['08:00'],
        instructions: '',
        isEdit: false,
        startDate: DateTime(2026, 9, 5),
        refillDate: DateTime(2026, 10, 15),
        totalQuantity: 30,
        familyMemberId: null,
      );
      expect(payload['refill_date'], '2026-10-15');
      expect(payload['total_quantity'], 30);
      expect(payload.containsKey('is_active'), isTrue);
    });

    test('REM9-07b create without refill_date omits key', () {
      final payload = buildReminderSavePayload(
        medicineName: 'Ibuprofen',
        dosage: '200mg',
        frequencyApi: 'daily',
        times: ['08:00'],
        instructions: '',
        isEdit: false,
        refillDate: null,
      );
      expect(payload.containsKey('refill_date'), isFalse);
    });

    test('REM9-08 edit form hydrates existing refill_date', () {
      final hydrated = parseReminderApiDate('2026-10-15');
      expect(hydrated, DateTime(2026, 10, 15));
      expect(parseReminderApiDate(null), isNull);
      expect(parseReminderApiDate(''), isNull);
    });

    test('REM9-09 edit sends updated and cleared refill_date', () {
      final updated = buildReminderSavePayload(
        medicineName: 'Metformin',
        dosage: '500mg',
        frequencyApi: 'daily',
        times: ['08:00'],
        instructions: 'with food',
        isEdit: true,
        refillDate: DateTime(2026, 11, 1),
        remainingQuantity: 10,
      );
      expect(updated['refill_date'], '2026-11-01');
      expect(updated['remaining_quantity'], 10);

      final cleared = buildReminderSavePayload(
        medicineName: 'Metformin',
        dosage: '500mg',
        frequencyApi: 'daily',
        times: ['08:00'],
        instructions: '',
        isEdit: true,
        refillDate: null,
      );
      expect(cleared.containsKey('refill_date'), isTrue);
      expect(cleared['refill_date'], isNull);
    });

    test('refill notification id is outside dose slot range', () {
      const scheduleId = 42;
      final refillId = LocalReminderNotifications.refillNotificationId(scheduleId);
      expect(refillId, scheduleId * 10 + 9);
      for (var i = 0; i < 4; i++) {
        expect(refillId, isNot(scheduleId * 10 + i));
      }
      // Next schedule's dose block starts at (scheduleId+1)*10
      expect(refillId, lessThan((scheduleId + 1) * 10));
    });

    test('source wires refill into create/edit and cancel paths', () {
      final add = File('lib/features/reminders/presentation/add_reminder_screen.dart')
          .readAsStringSync();
      final list = File('lib/features/reminders/presentation/reminders_screen.dart')
          .readAsStringSync();
      final notif =
          File('lib/core/notifications/local_reminder_notifications.dart')
              .readAsStringSync();

      expect(add.contains('refillDate: _refillDate'), isTrue);
      expect(add.contains('buildReminderSavePayload'), isTrue);
      expect(add.contains('Refill Date'), isTrue);
      expect(list.contains('refillDate: parseReminderApiDate'), isTrue);
      expect(notif.contains('refillNotificationId'), isTrue);
      expect(notif.contains('scheduleId * 10 + 9'), isTrue);
    });
  });
}
