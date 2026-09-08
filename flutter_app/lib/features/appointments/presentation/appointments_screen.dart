import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vitapulse_ai/core/notifications/local_reminder_notifications.dart';
import 'package:vitapulse_ai/features/appointments/data/appointment_api.dart';
import 'package:vitapulse_ai/shared/widgets/empty_state.dart';
import 'package:vitapulse_ai/shared/widgets/shimmer_box.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_spacing.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';

/// HN-REM-010 — upcoming appointment list with local reminder sync.
class AppointmentsScreen extends StatefulWidget {
  final Future<List<Map<String, dynamic>>> Function()? loadAppointments;
  final Future<void> Function(int id)? deleteAppointment;
  final Future<bool> Function({
    required int appointmentId,
    required String title,
    required DateTime scheduledAt,
    int remindBeforeMinutes,
    String? notes,
  })? scheduleNotification;
  final Future<void> Function(int appointmentId)? cancelNotification;

  const AppointmentsScreen({
    super.key,
    this.loadAppointments,
    this.deleteAppointment,
    this.scheduleNotification,
    this.cancelNotification,
  });

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final loader = widget.loadAppointments ??
          () => AppointmentApi.listAppointments(activeOnly: true);
      final data = await loader();
      if (!mounted) return;
      setState(() {
        _items = data;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load appointments.';
        _loading = false;
      });
    }
  }

  Future<void> _delete(Map<String, dynamic> appt, int index) async {
    final rawId = appt['id'];
    final id = rawId is int ? rawId : int.tryParse('$rawId');
    if (id == null) return;

    setState(() => _items.removeAt(index));
    try {
      final deleter =
          widget.deleteAppointment ?? AppointmentApi.deleteAppointment;
      await deleter(id);
      final cancel = widget.cancelNotification ??
          LocalReminderNotifications.cancelAppointmentNotification;
      await cancel(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Appointment cancelled')),
        );
      }
    } catch (_) {
      setState(() => _items.insert(index, appt));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to cancel appointment')),
        );
      }
    }
  }

  String _fmt(DateTime? dt) {
    if (dt == null) return '—';
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      key: const Key('appointments_screen'),
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Appointments',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            key: const Key('appointments_refresh'),
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('appointments_add_fab'),
        onPressed: () async {
          final added = await context.push('/home/appointments/add');
          if (added == true) _load();
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);

    if (_loading) {
      return ListView(
        key: const Key('appointments_loading'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: const [
          ShimmerCard(height: 88),
          ShimmerCard(height: 88),
          ShimmerCard(height: 88),
        ],
      );
    }

    if (_error.isNotEmpty) {
      return Center(
        key: const Key('appointments_error'),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, color: cs.error, size: 48),
              const SizedBox(height: 12),
              Text(_error, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return EmptyState(
        key: const Key('appointments_empty'),
        icon: Icons.event_available_rounded,
        title: 'No appointments yet',
        subtitle: 'Add a GP visit, specialist, or other appointment reminder.',
        actionLabel: 'Add appointment',
        onAction: () async {
          final added = await context.push('/home/appointments/add');
          if (added == true) _load();
        },
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        key: const Key('appointments_list'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final appt = _items[index];
          final scheduled = parseAppointmentApiDateTime(appt['scheduled_at']);
          final remind = appt['remind_before_minutes'] is int
              ? appt['remind_before_minutes'] as int
              : int.tryParse('${appt['remind_before_minutes']}') ?? 60;
          final member = appt['family_member_name']?.toString() ?? '';

          return Dismissible(
            key: ValueKey(appt['id'] ?? index),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 24),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: cs.error,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.delete_outline, color: Colors.white),
            ),
            confirmDismiss: (_) async {
              return await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Cancel appointment?'),
                      content: Text(
                        'Cancel "${appt['title'] ?? 'this appointment'}"?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Keep'),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: cs.error,
                          ),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ) ??
                  false;
            },
            onDismissed: (_) => _delete(appt, index),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: Key('appointment_tile_${appt['id']}'),
                onTap: () async {
                  final changed = await context.push(
                    '/home/appointments/edit',
                    extra: appt,
                  );
                  if (changed == true && mounted) _load();
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.x3),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appt['title']?.toString() ?? 'Appointment',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _fmt(scheduled),
                        style: TextStyle(
                          fontSize: 13,
                          color: hc.vitaGood,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        remindBeforeLabel(remind),
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      if (member.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          member,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
