import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vitapulse_ai/core/utils/error_handler.dart';
import 'package:vitapulse_ai/features/notifications/data/in_app_notification_inbox.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_spacing.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';

/// HN-NOTIF-006 — in-app Notifications inbox.
///
/// Does not treat pending local reminder alarms as inbox items.
/// Does not invent unread state or timestamps.
class NotificationsScreen extends StatefulWidget {
  final InAppNotificationLoader? loader;

  const NotificationsScreen({super.key, this.loader});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _loading = true;
  bool _inFlight = false;
  String? _error;
  List<InAppNotification> _items = const [];

  InAppNotificationLoader get _loader =>
      widget.loader ?? InAppNotificationInbox.load;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (_inFlight) return;
    _inFlight = true;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _loader();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorHandler.getMessage(e);
        _loading = false;
      });
    } finally {
      _inFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(key: Key('notifications-loading')),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: AppSpacing.screenPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                key: const Key('notifications-error'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('notifications-retry'),
                onPressed: _loading ? null : _load,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return _EmptyInbox(onViewReminders: () => context.push('/home/reminders'));
    }
    return ListView.separated(
      padding: AppSpacing.screenPadding,
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _NotificationTile(item: _items[i]),
    );
  }
}

class _EmptyInbox extends StatelessWidget {
  final VoidCallback onViewReminders;
  const _EmptyInbox({required this.onViewReminders});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);
    return Center(
      child: Padding(
        padding: AppSpacing.screenPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none_outlined,
                size: 48, color: hc.discharge),
            const SizedBox(height: 16),
            Text(
              'No in-app notifications yet',
              key: const Key('notifications-empty'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Medication reminders use on-device alerts. '
              'This screen does not invent notification history.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onViewReminders,
              child: const Text('View medication reminders'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final InAppNotification item;
  const _NotificationTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final unread = item.isUnread == true;
    return Card(
      child: ListTile(
        leading: Icon(
          unread
              ? Icons.notifications_active_outlined
              : Icons.notifications_outlined,
        ),
        title: Text(item.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.body),
            if (item.createdAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  item.createdAt!.toLocal().toString(),
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
