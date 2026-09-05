/// N09 — denied / disabled notification UX path.
///
/// Orchestrator should revoke POST_NOTIFICATIONS (and optionally set
/// appops POST_NOTIFICATION deny) BEFORE running. This test does not rely on
/// tapping the system Deny dialog (emulator often auto-grants).
///
///   adb -s emulator-5554 shell pm revoke com.vitapulse.vitapulse_ai android.permission.POST_NOTIFICATIONS
///   adb -s emulator-5554 shell cmd permission set-permission-flags \
///     com.vitapulse.vitapulse_ai android.permission.POST_NOTIFICATIONS user-set,user-fixed
///   adb -s emulator-5554 shell cmd appops set com.vitapulse.vitapulse_ai POST_NOTIFICATION deny
///   flutter test integration_test/notification_n09_denied_test.dart -d emulator-5554
library;

import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vitapulse_ai/core/notifications/local_reminder_notifications.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'N09 schedule returns false and does not claim success when notifications disabled',
      (tester) async {
    await LocalReminderNotifications.init();
    expect(Platform.isAndroid, isTrue);

    final status = await Permission.notification.status;
    final androidPlugin = FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    final enabled = await androidPlugin?.areNotificationsEnabled();

    tester.printToConsole(
        'N09_STATUS=$status areNotificationsEnabled=$enabled');

    // Precondition: either runtime permission is not granted, or the app-level
    // notifications toggle is off. If neither is true, orchestrator failed to
    // set up the denied state (often emulator auto-grant after request).
    final blocked = !status.isGranted || enabled == false;
    expect(
      blocked,
      isTrue,
      reason:
          'N09 requires denied/disabled notifications before schedule. '
          'Got status=$status areNotificationsEnabled=$enabled. '
          'If both are granted/enabled, sticky-Deny tap flakiness is '
          'emulator behaviour — re-run after pm revoke + user-fixed + appops deny.',
    );

    const scheduleId = 91009;
    await LocalReminderNotifications.cancelForSchedule(scheduleId);

    final t = DateTime.now().add(const Duration(minutes: 3));
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');

    final ok = await LocalReminderNotifications.scheduleMedicationReminders(
      scheduleId: scheduleId,
      medicineName: 'Sprint1 Denied N09',
      times: ['$hh:$mm'],
      dosage: '1 tab',
      frequencyApi: 'daily',
      startDate: DateTime.now(),
    );

    tester.printToConsole('N09_SCHEDULE_OK=$ok');

    // App must not claim scheduling succeeded.
    expect(ok, isFalse);

    final pending = await FlutterLocalNotificationsPlugin()
        .pendingNotificationRequests();
    final mine = pending.where((p) =>
        p.id >= scheduleId * 10 &&
        p.id < scheduleId * 10 + 4 &&
        (p.body ?? '').contains('Sprint1 Denied N09'));
    expect(
      mine.isEmpty,
      isTrue,
      reason: 'Denied path must not leave pending notifications',
    );

    // ensurePermission / schedule must not crash (we reached here).
    final statusAfter = await Permission.notification.status;
    tester.printToConsole('N09_STATUS_AFTER=$statusAfter');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
