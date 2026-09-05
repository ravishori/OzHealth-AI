/// N09: expects POST_NOTIFICATIONS denied; orchestrator taps Don't allow if prompted.
library;

import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vitapulse_ai/core/notifications/local_reminder_notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalReminderNotifications.init();
  final before = await Permission.notification.status;
  // ignore: avoid_print
  print('N09_STATUS_BEFORE=$before');

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
  final after = await Permission.notification.status;
  // ignore: avoid_print
  print('N09_SCHEDULE_OK=$ok STATUS_AFTER=$after');
  await Future<void>.delayed(const Duration(seconds: 3));
}
