/// HN-NOTIF-006 — in-app notification inbox source.
///
/// There is no owner-scoped notification API and no ORM for the unused
/// `notification_logs` table. Local medication reminders are OS-scheduled
/// alerts, not persistent inbox rows. FCM/push history is deferred.
///
/// This loader therefore returns an empty list. Callers must not invent
/// records, unread counts, or timestamps.
class InAppNotificationInbox {
  InAppNotificationInbox._();

  static Future<List<InAppNotification>> load() async {
    return const [];
  }
}

class InAppNotification {
  final String title;
  final String body;
  final DateTime? createdAt;
  final bool? isUnread;

  const InAppNotification({
    required this.title,
    required this.body,
    this.createdAt,
    this.isUnread,
  });
}

typedef InAppNotificationLoader = Future<List<InAppNotification>> Function();
