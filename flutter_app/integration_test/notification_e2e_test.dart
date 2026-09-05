/// Sprint 1 Android notification E2E — run on a real emulator/device:
///   flutter test integration_test/notification_e2e_test.dart -d emulator-5554
library;

import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vitapulse_ai/core/notifications/local_reminder_notifications.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Sprint1 local notification E2E', () {
    testWidgets('N01 permission request path does not crash', (tester) async {
      await LocalReminderNotifications.init();
      final statusBefore = await Permission.notification.status;
      // Request; emulator may auto-grant or show dialog handled externally.
      final granted = await LocalReminderNotifications.ensurePermission();
      final statusAfter = await Permission.notification.status;
      // Soft assert: call completes; grant may be false if denied intentionally.
      expect(statusBefore.isDenied || statusBefore.isGranted || statusBefore.isLimited,
          isTrue);
      expect(granted == statusAfter.isGranted, isTrue);
    });

    testWidgets('N02 daily schedule creates pending notification', (tester) async {
      await LocalReminderNotifications.init();
      final allowed = await LocalReminderNotifications.ensurePermission();
      expect(allowed, isTrue,
          reason: 'Grant POST_NOTIFICATIONS on emulator before N02');

      final now = DateTime.now();
      final inTwoMin = now.add(const Duration(minutes: 2));
      final hh = inTwoMin.hour.toString().padLeft(2, '0');
      final mm = inTwoMin.minute.toString().padLeft(2, '0');

      const scheduleId = 91001;
      await LocalReminderNotifications.cancelForSchedule(scheduleId);
      final ok = await LocalReminderNotifications.scheduleMedicationReminders(
        scheduleId: scheduleId,
        medicineName: 'Sprint1 Daily Test',
        times: ['$hh:$mm'],
        dosage: '1 tab',
        frequencyApi: 'daily',
        startDate: now,
      );
      expect(ok, isTrue);

      final pending = await FlutterLocalNotificationsPlugin()
          .pendingNotificationRequests();
      final mine = pending.where((p) =>
          p.id >= scheduleId * 10 && p.id < scheduleId * 10 + 4);
      expect(mine.isNotEmpty, isTrue, reason: 'Expected pending daily notif');
      expect(mine.first.title, 'Medication reminder');
      expect(mine.first.body, contains('Sprint1 Daily Test'));
    });

    testWidgets('N03 weekly schedule creates pending (not daily-only id clash)',
        (tester) async {
      await LocalReminderNotifications.init();
      expect(await LocalReminderNotifications.ensurePermission(), isTrue);

      final now = DateTime.now();
      final inTwoMin = now.add(const Duration(minutes: 2));
      final hh = inTwoMin.hour.toString().padLeft(2, '0');
      final mm = inTwoMin.minute.toString().padLeft(2, '0');
      const scheduleId = 91002;

      await LocalReminderNotifications.cancelForSchedule(scheduleId);
      final ok = await LocalReminderNotifications.scheduleMedicationReminders(
        scheduleId: scheduleId,
        medicineName: 'Sprint1 Weekly Test',
        times: ['$hh:$mm'],
        frequencyApi: 'weekly',
        startDate: now,
      );
      expect(ok, isTrue);
      final pending = await FlutterLocalNotificationsPlugin()
          .pendingNotificationRequests();
      expect(
        pending.any((p) =>
            p.id >= scheduleId * 10 &&
            p.id < scheduleId * 10 + 4 &&
            (p.body ?? '').contains('Weekly')),
        isTrue,
      );
    });

    testWidgets('N04 monthly schedule creates pending', (tester) async {
      await LocalReminderNotifications.init();
      expect(await LocalReminderNotifications.ensurePermission(), isTrue);
      final now = DateTime.now();
      final inTwoMin = now.add(const Duration(minutes: 2));
      final hh = inTwoMin.hour.toString().padLeft(2, '0');
      final mm = inTwoMin.minute.toString().padLeft(2, '0');
      const scheduleId = 91003;
      await LocalReminderNotifications.cancelForSchedule(scheduleId);
      final ok = await LocalReminderNotifications.scheduleMedicationReminders(
        scheduleId: scheduleId,
        medicineName: 'Sprint1 Monthly Test',
        times: ['$hh:$mm'],
        frequencyApi: 'monthly',
        startDate: now,
      );
      expect(ok, isTrue);
      final pending = await FlutterLocalNotificationsPlugin()
          .pendingNotificationRequests();
      expect(
        pending.any((p) =>
            p.id >= scheduleId * 10 &&
            p.id < scheduleId * 10 + 4 &&
            (p.body ?? '').contains('Monthly')),
        isTrue,
      );
    });

    testWidgets('N05 toggle-off cancels pending', (tester) async {
      await LocalReminderNotifications.init();
      expect(await LocalReminderNotifications.ensurePermission(), isTrue);
      final now = DateTime.now().add(const Duration(minutes: 3));
      final hh = now.hour.toString().padLeft(2, '0');
      final mm = now.minute.toString().padLeft(2, '0');
      const scheduleId = 91004;
      await LocalReminderNotifications.scheduleMedicationReminders(
        scheduleId: scheduleId,
        medicineName: 'Sprint1 Cancel Test',
        times: ['$hh:$mm'],
        frequencyApi: 'daily',
      );
      var pending = await FlutterLocalNotificationsPlugin()
          .pendingNotificationRequests();
      expect(pending.any((p) => p.id >= scheduleId * 10 && p.id < scheduleId * 10 + 4),
          isTrue);

      await LocalReminderNotifications.cancelForSchedule(scheduleId);
      pending = await FlutterLocalNotificationsPlugin()
          .pendingNotificationRequests();
      expect(
        pending.any((p) => p.id >= scheduleId * 10 && p.id < scheduleId * 10 + 4),
        isFalse,
        reason: 'Pending notifications must be cleared after cancel',
      );
    });

    testWidgets('N06 toggle-on reschedules', (tester) async {
      await LocalReminderNotifications.init();
      expect(await LocalReminderNotifications.ensurePermission(), isTrue);
      const scheduleId = 91005;
      await LocalReminderNotifications.cancelForSchedule(scheduleId);
      final now = DateTime.now().add(const Duration(minutes: 3));
      final hh = now.hour.toString().padLeft(2, '0');
      final mm = now.minute.toString().padLeft(2, '0');
      final ok = await LocalReminderNotifications.scheduleMedicationReminders(
        scheduleId: scheduleId,
        medicineName: 'Sprint1 Reschedule Test',
        times: ['$hh:$mm'],
        frequencyApi: 'daily',
      );
      expect(ok, isTrue);
      final pending = await FlutterLocalNotificationsPlugin()
          .pendingNotificationRequests();
      expect(
        pending.any((p) => p.id >= scheduleId * 10 && p.id < scheduleId * 10 + 4),
        isTrue,
      );
    });

    testWidgets('N07 delete cancels', (tester) async {
      // Same cancel semantics as delete path in reminders_screen.
      await LocalReminderNotifications.init();
      const scheduleId = 91006;
      final t = DateTime.now().add(const Duration(minutes: 4));
      await LocalReminderNotifications.scheduleMedicationReminders(
        scheduleId: scheduleId,
        medicineName: 'Sprint1 Delete Test',
        times: [
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'
        ],
        frequencyApi: 'daily',
      );
      await LocalReminderNotifications.cancelForSchedule(scheduleId);
      final pending = await FlutterLocalNotificationsPlugin()
          .pendingNotificationRequests();
      expect(
        pending.any((p) => p.id >= scheduleId * 10 && p.id < scheduleId * 10 + 4),
        isFalse,
      );
    });

    testWidgets('N09 denied permission returns false and does not claim success',
        (tester) async {
      // This test expects permission already denied via adb revoke.
      await LocalReminderNotifications.init();
      if (!Platform.isAndroid) return;
      final status = await Permission.notification.status;
      if (!status.isDenied && !status.isPermanentlyDenied) {
        // Skip soft: orchestrator runs revoke separately.
        return;
      }
      const scheduleId = 91009;
      final t = DateTime.now().add(const Duration(minutes: 2));
      final ok = await LocalReminderNotifications.scheduleMedicationReminders(
        scheduleId: scheduleId,
        medicineName: 'Sprint1 Denied',
        times: [
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'
        ],
        frequencyApi: 'daily',
      );
      expect(ok, isFalse);
    });
  });
}
