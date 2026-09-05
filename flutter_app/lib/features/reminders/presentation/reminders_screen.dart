import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/core/notifications/local_reminder_notifications.dart';
import 'package:vitapulse_ai/features/reminders/presentation/add_reminder_screen.dart';
import 'package:vitapulse_ai/shared/widgets/shimmer_box.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_spacing.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  List<Map<String, dynamic>> _reminders = [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadReminders());
  }

  Future<void> _loadReminders() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final resp = await ApiClient.get('/reminders/');
      setState(() {
        _reminders = List<Map<String, dynamic>>.from(
          resp.data is List ? resp.data : (resp.data['reminders'] ?? []),
        );
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load reminders.';
        _loading = false;
      });
    }
  }

  Future<void> _toggleReminder(Map<String, dynamic> reminder) async {
    final id = reminder['id'];
    final currentActive = reminder['is_active'] == true;
    setState(() {
      reminder['is_active'] = !currentActive;
    });
    try {
      await ApiClient.put('/reminders/$id', data: {'is_active': !currentActive});
      final scheduleId = id is int ? id : int.tryParse('$id');
      if (scheduleId != null) {
        if (currentActive) {
          // Turning OFF → cancel local notifications
          await LocalReminderNotifications.cancelForSchedule(scheduleId);
        } else {
          final times = (reminder['times'] is List)
              ? List<String>.from(reminder['times'].map((e) => e.toString()))
              : <String>[];
          await LocalReminderNotifications.scheduleMedicationReminders(
            scheduleId: scheduleId,
            medicineName: reminder['medicine_name']?.toString() ?? 'Medication',
            times: times,
            dosage: reminder['dosage']?.toString(),
            frequencyApi: reminder['frequency']?.toString() ?? 'daily',
            refillDate: parseReminderApiDate(reminder['refill_date']),
          );
        }
      }
    } catch (e) {
      setState(() {
        reminder['is_active'] = currentActive;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update reminder')),
        );
      }
    }
  }

  Future<void> _deleteReminder(
      Map<String, dynamic> reminder, int index) async {
    final id = reminder['id'];
    setState(() => _reminders.removeAt(index));
    try {
      await ApiClient.delete('/reminders/$id');
      final scheduleId = id is int ? id : int.tryParse('$id');
      if (scheduleId != null) {
        await LocalReminderNotifications.cancelForSchedule(scheduleId);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('${reminder['medicine_name'] ?? 'Reminder'} deleted'),
          ),
        );
      }
    } catch (e) {
      setState(() => _reminders.insert(index, reminder));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete reminder')),
        );
      }
    }
  }

  static String frequencyLabel(String raw) {
    switch (raw.toLowerCase().replaceAll(' ', '_')) {
      case 'daily':
        return 'Daily';
      case 'twice_daily':
        return 'Twice Daily';
      case 'three_times_daily':
        return 'Three Times Daily';
      case 'four_times_daily':
        return 'Four Times Daily';
      case 'weekly':
        return 'Weekly';
      case 'fortnightly':
        return 'Fortnightly';
      case 'monthly':
        return 'Monthly';
      case 'as_needed':
        return 'As Needed';
      default:
        return raw;
    }
  }

  String _formatNextReminder(Map<String, dynamic> reminder) {
    final times = reminder['times'];
    if (times is List && times.isNotEmpty) {
      final freq = frequencyLabel(reminder['frequency']?.toString() ?? '');
      return '$freq · ${times.first}';
    }
    final nextTime = reminder['next_reminder_time']?.toString() ?? '';
    if (nextTime.isEmpty) return 'Scheduled';
    return nextTime;
  }

  Color _frequencyColor(BuildContext context, String freq) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);
    final key = freq.toLowerCase().replaceAll(' ', '_');
    return switch (key) {
      'daily' => cs.primary,
      'twice_daily' => cs.secondary,
      'three_times_daily' => cs.tertiary,
      'weekly' || 'as_needed' || 'fortnightly' => hc.vitaWarning,
      'monthly' => hc.aiAccent,
      _ => cs.onSurfaceVariant,
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Medication Reminders',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            if (!_loading && !_error.isNotEmpty && _reminders.isNotEmpty)
              Text(
                '${_reminders.where((r) => r['is_active'] == true).length} active',
                style: TextStyle(
                  fontSize: 12,
                  color: hc.vitaGood,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loadReminders,
          ),
        ],
      ),
      body: _buildBody(context),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final added = await context.push('/home/reminders/add');
          if (added == true) _loadReminders();
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Reminder',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: const [
          ShimmerCard(height: 96),
          ShimmerCard(height: 96),
          ShimmerCard(height: 96),
          ShimmerCard(height: 96),
        ],
      );
    }

    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cs.errorContainer.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.error_outline_rounded,
                    color: cs.error, size: 48),
              ),
              const SizedBox(height: 16),
              Text(
                'Could not load reminders',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _loadReminders,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    if (_reminders.isEmpty) {
      return _buildEmptyState(context);
    }

    return RefreshIndicator(
      onRefresh: _loadReminders,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        itemCount: _reminders.length,
        itemBuilder: (context, index) {
          final reminder = _reminders[index];
          return _buildDismissible(context, reminder, index);
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    hc.vitaWarning.withValues(alpha: 0.15),
                    hc.vitaWarning.withValues(alpha: 0.04),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Container(
                margin: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: hc.vitaWarning.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.alarm_outlined,
                    color: hc.vitaWarning, size: 36),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No reminders yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Stay on track with your medications by setting up reminders.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () async {
                final added = await context.push('/home/reminders/add');
                if (added == true) _loadReminders();
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add your first reminder'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDismissible(
      BuildContext context, Map<String, dynamic> reminder, int index) {
    final cs = Theme.of(context).colorScheme;

    return Dismissible(
      key: ValueKey(reminder['id'] ?? index),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              cs.error.withValues(alpha: 0.0),
              cs.error,
            ],
          ),
          borderRadius: AppRadius.brMd,
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.white, size: 26),
            SizedBox(height: 4),
            Text('Delete',
                style: TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
      confirmDismiss: (_) async => _showDeleteConfirm(context, reminder),
      onDismissed: (_) => _deleteReminder(reminder, index),
      child: _ReminderCard(
        reminder: reminder,
        nextReminderText: _formatNextReminder(reminder),
        frequencyColor: _frequencyColor(
            context, reminder['frequency']?.toString() ?? ''),
        onToggle: () => _toggleReminder(reminder),
        onOpen: () async {
          final changed = await context.push(
            '/home/reminders/edit',
            extra: reminder,
          );
          if (changed == true && mounted) _loadReminders();
        },
      ),
    );
  }

  Future<bool> _showDeleteConfirm(
      BuildContext context, Map<String, dynamic> reminder) async {
    final cs = Theme.of(context).colorScheme;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: const Text('Delete Reminder'),
            content: Text(
              'Delete reminder for ${reminder['medicine_name'] ?? 'this medicine'}?',
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: cs.error),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
  }
}

// ─────────────────────────── Reminder card ───────────────────────────

class _ReminderCard extends StatelessWidget {
  final Map<String, dynamic> reminder;
  final String nextReminderText;
  final Color frequencyColor;
  final VoidCallback onToggle;
  final VoidCallback onOpen;

  const _ReminderCard({
    required this.reminder,
    required this.nextReminderText,
    required this.frequencyColor,
    required this.onToggle,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final medicineName =
        reminder['medicine_name']?.toString() ?? 'Unknown Medicine';
    final dosage = reminder['dosage']?.toString() ?? '';
    final frequency = _RemindersScreenState.frequencyLabel(
        reminder['frequency']?.toString() ?? '');
    final isActive = reminder['is_active'] == true;
    final memberName = reminder['family_member_name']?.toString() ?? '';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.x3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive
              ? frequencyColor.withValues(alpha: 0.2)
              : cs.outlineVariant.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left accent bar
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: isActive
                      ? frequencyColor
                      : cs.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              // Card content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Icon
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: isActive
                              ? frequencyColor.withValues(alpha: 0.12)
                              : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.medication_rounded,
                          color: isActive
                              ? frequencyColor
                              : cs.onSurfaceVariant,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Text block
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              medicineName,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: isActive
                                    ? cs.onSurface
                                    : cs.onSurfaceVariant,
                                height: 1.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (dosage.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                dosage,
                                style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  fontSize: 12,
                                  height: 1.2,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                if (frequency.isNotEmpty)
                                  _Badge(
                                    label: frequency,
                                    color: frequencyColor,
                                    icon: Icons.repeat_rounded,
                                  ),
                                _Badge(
                                  label: nextReminderText,
                                  color: nextReminderText == 'Overdue'
                                      ? cs.error
                                      : cs.secondary,
                                  icon: Icons.schedule_rounded,
                                ),
                                if (memberName.isNotEmpty)
                                  _Badge(
                                    label: 'For $memberName',
                                    color: cs.tertiary,
                                    icon: Icons.family_restroom,
                                  )
                                else
                                  _Badge(
                                    label: 'Personal',
                                    color: cs.onSurfaceVariant,
                                    icon: Icons.person_outline,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Toggle
                      Transform.scale(
                        scale: 0.85,
                        child: Switch(
                          value: isActive,
                          onChanged: (_) => onToggle(),
                          activeThumbColor: frequencyColor,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
        ),
      ),
    );
  }
}

// ─────────────────────────── Badge ───────────────────────────

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const _Badge({required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}
