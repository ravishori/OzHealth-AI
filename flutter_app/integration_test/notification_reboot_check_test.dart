/// Post-reboot pending check (run AFTER adb reboot + boot_completed=1).
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vitapulse_ai/core/notifications/local_reminder_notifications.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('N08b pending restored after reboot for reboot schedule id',
      (tester) async {
    await LocalReminderNotifications.init();
    // Boot receiver should have restored plugin-scheduled notifications.
    final pending = await FlutterLocalNotificationsPlugin()
        .pendingNotificationRequests();
    final restored = pending.any((p) =>
        (p.body ?? '').contains('Sprint1 Reboot Persist') ||
        (p.id >= 92008 * 10 && p.id < 92008 * 10 + 4));
    expect(restored, isTrue,
        reason:
            'Expected Sprint1 Reboot Persist notification to be restored after BOOT_COMPLETED');
  });
}
