/// Standalone scheduler for N08 reboot test — leave app installed.
/// Run: flutter run -d emulator-5554 -t integration_test/schedule_reboot_only.dart --release
/// Prefer: flutter drive / or just dart via test without teardown uninstall.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vitapulse_ai/core/notifications/local_reminder_notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalReminderNotifications.init();
  final allowed = await LocalReminderNotifications.ensurePermission();
  if (!allowed) {
    // ignore: avoid_print
    print('N08_SCHEDULE_FAIL permission_denied');
    return;
  }
  const scheduleId = 92008;
  await LocalReminderNotifications.cancelForSchedule(scheduleId);
  final when = DateTime.now().add(const Duration(minutes: 6));
  final hh = when.hour.toString().padLeft(2, '0');
  final mm = when.minute.toString().padLeft(2, '0');
  final ok = await LocalReminderNotifications.scheduleMedicationReminders(
    scheduleId: scheduleId,
    medicineName: 'Sprint1 Reboot Persist',
    times: ['$hh:$mm'],
    frequencyApi: 'daily',
  );
  final pending =
      await FlutterLocalNotificationsPlugin().pendingNotificationRequests();
  final has = pending.any((p) =>
      p.id >= scheduleId * 10 &&
      (p.body ?? '').contains('Sprint1 Reboot Persist'));
  // ignore: avoid_print
  print('N08_SCHEDULE ok=$ok pending=$has count=${pending.length} at=$hh:$mm');
  // Keep process alive briefly so AlarmManager commits.
  await Future<void>.delayed(const Duration(seconds: 2));
}
