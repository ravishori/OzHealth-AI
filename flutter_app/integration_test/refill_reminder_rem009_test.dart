/// HN-REM-009 Android verification for local refill one-shot notifications.
///   flutter test integration_test/refill_reminder_rem009_test.dart -d emulator-5554
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:vitapulse_ai/core/notifications/local_reminder_notifications.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('REM9-10..12 refill schedule / fire / cancel lifecycle',
      (tester) async {
    await LocalReminderNotifications.init();
    expect(await LocalReminderNotifications.ensurePermission(), isTrue);

    const scheduleId = 93009;
    final refillId =
        LocalReminderNotifications.refillNotificationId(scheduleId);
    expect(refillId, scheduleId * 10 + 9);

    await LocalReminderNotifications.cancelForSchedule(scheduleId);

    // REM9-10 — schedule dose + near-future refill one-shot
    final now = DateTime.now();
    final refillAt =
        DateTime(now.year, now.month, now.day, now.hour, now.minute)
            .add(const Duration(minutes: 1));
    final doseAt = refillAt.add(const Duration(minutes: 2));
    final doseHh = doseAt.hour.toString().padLeft(2, '0');
    final doseMm = doseAt.minute.toString().padLeft(2, '0');

    final ok = await LocalReminderNotifications.scheduleMedicationReminders(
      scheduleId: scheduleId,
      medicineName: 'REM9 Synthetic Refill',
      times: ['$doseHh:$doseMm'],
      dosage: '1 tab',
      frequencyApi: 'daily',
      startDate: now,
      refillDate: refillAt,
      refillHour: refillAt.hour,
      refillMinute: refillAt.minute,
    );
    expect(ok, isTrue);

    var pending =
        await FlutterLocalNotificationsPlugin().pendingNotificationRequests();
    expect(
      pending.any((p) => p.id == refillId),
      isTrue,
      reason: 'REM9-10 refill pending notification must be scheduled',
    );
    expect(
      pending.any((p) => p.id == scheduleId * 10),
      isTrue,
      reason: 'Dose slot must still be scheduled',
    );

    // REM9-11 — wait for refill delivery (bounded)
    final waitUntil = tz.TZDateTime(
      tz.local,
      refillAt.year,
      refillAt.month,
      refillAt.day,
      refillAt.hour,
      refillAt.minute,
    ).add(const Duration(seconds: 40));
    var fired = false;
    while (tz.TZDateTime.now(tz.local).isBefore(waitUntil)) {
      await Future<void>.delayed(const Duration(seconds: 3));
      final active = await FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.getActiveNotifications();
      if (active?.any(
            (n) =>
                (n.title ?? '').toLowerCase().contains('refill') ||
                (n.body ?? '').toLowerCase().contains('refill'),
          ) ==
          true) {
        fired = true;
        break;
      }
    }
    expect(fired, isTrue, reason: 'REM9-11 refill notification must fire');

    // REM9-12A-C — edit reschedule
    final nextRefill = DateTime.now().add(const Duration(minutes: 5));
    final ok2 = await LocalReminderNotifications.scheduleMedicationReminders(
      scheduleId: scheduleId,
      medicineName: 'REM9 Synthetic Refill',
      times: ['$doseHh:$doseMm'],
      dosage: '1 tab',
      frequencyApi: 'daily',
      startDate: now,
      refillDate: nextRefill,
      refillHour: nextRefill.hour,
      refillMinute: nextRefill.minute,
    );
    expect(ok2, isTrue);

    pending =
        await FlutterLocalNotificationsPlugin().pendingNotificationRequests();
    expect(pending.any((p) => p.id == refillId), isTrue);

    // REM9-12D-E — delete/cancel
    await LocalReminderNotifications.cancelForSchedule(scheduleId);
    pending =
        await FlutterLocalNotificationsPlugin().pendingNotificationRequests();
    expect(
      pending.any((p) => p.id == refillId),
      isFalse,
      reason: 'REM9-12 delete/cancel must remove refill notification',
    );
    expect(
      pending.any((p) => p.id >= scheduleId * 10 && p.id < scheduleId * 10 + 4),
      isFalse,
      reason: 'Dose slots must also be cancelled',
    );
  }, timeout: const Timeout(Duration(minutes: 4)));
}
