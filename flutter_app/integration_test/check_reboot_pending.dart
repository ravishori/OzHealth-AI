/// Post-reboot pending verification without flutter-test uninstall.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vitapulse_ai/core/notifications/local_reminder_notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalReminderNotifications.init();
  final pending =
      await FlutterLocalNotificationsPlugin().pendingNotificationRequests();
  final restored = pending.any((p) =>
      (p.body ?? '').contains('Sprint1 Reboot Persist') ||
      (p.id >= 92008 * 10 && p.id < 92008 * 10 + 4));
  // ignore: avoid_print
  print(
      'N08_REBOOT_CHECK restored=$restored pending=${pending.length} ids=${pending.map((p) => p.id).toList()}');
  await Future<void>.delayed(const Duration(seconds: 2));
}
