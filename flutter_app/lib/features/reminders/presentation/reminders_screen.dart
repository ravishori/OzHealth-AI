import 'package:vitapulse_ai/core/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/core/theme/app_theme.dart';

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

  Future<void> _deleteReminder(Map<String, dynamic> reminder, int index) async {
    final id = reminder['id'];
    setState(() => _reminders.removeAt(index));
    try {
      await ApiClient.delete('/reminders/$id');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${reminder['medicine_name'] ?? 'Reminder'} deleted'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () async {
                setState(() => _reminders.insert(index, reminder));
                // Re-create on server
                try {
                  await ApiClient.post('/reminders/', data: reminder);
                } catch (_) {}
              },
            ),
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

  String _formatNextReminder(Map<String, dynamic> reminder) {
    final nextTime = reminder['next_reminder_time']?.toString() ?? '';
    if (nextTime.isEmpty) return 'No upcoming';
    try {
      final dt = DateTime.parse(nextTime).toLocal();
      final now = DateTime.now();
      final diff = dt.difference(now);
      if (diff.inMinutes < 60 && diff.inMinutes >= 0) {
        return 'In ${diff.inMinutes} min';
      } else if (diff.inHours < 24 && diff.inHours >= 0) {
        return 'Today ${_formatTime(dt)}';
      } else if (diff.inDays == 1) {
        return 'Tomorrow ${_formatTime(dt)}';
      } else if (diff.inDays < 0) {
        return 'Overdue';
      }
      return '${dt.day}/${dt.month} ${_formatTime(dt)}';
    } catch (_) {
      return nextTime;
    }
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  Color _frequencyColor(String freq) {
    switch (freq.toLowerCase()) {
      case 'daily':
        return AppTheme.primary;
      case 'twice daily':
        return AppTheme.secondary;
      case 'three times daily':
        return const Color(0xFF6A1B9A);
      case 'weekly':
        return const Color(0xFF00838F);
      case 'monthly':
        return const Color(0xFF558B2F);
      case 'as needed':
        return AppTheme.accent;
      default:
        return AppTheme.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Medication Reminders'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadReminders,
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/home/reminders/add');
          _loadReminders();
        },
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Reminder', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }

    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppTheme.error, size: 56),
              const SizedBox(height: 16),
              Text(_error, style: const TextStyle(color: AppTheme.textSecondary), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton(onPressed: _loadReminders, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (_reminders.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0x1400897B),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.alarm_off, color: AppTheme.primary, size: 56),
            ),
            const SizedBox(height: 24),
            const Text(
              'No reminders set',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap + to add your first medication reminder',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: _loadReminders,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        itemCount: _reminders.length,
        itemBuilder: (context, index) {
          final reminder = _reminders[index];
          return _buildDismissible(reminder, index);
        },
      ),
    );
  }

  Widget _buildDismissible(Map<String, dynamic> reminder, int index) {
    return Dismissible(
      key: ValueKey(reminder['id'] ?? index),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppTheme.error,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, color: Colors.white, size: 26),
            SizedBox(height: 4),
            Text('Delete', style: TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
      confirmDismiss: (_) async {
        return await _showDeleteConfirm(reminder);
      },
      onDismissed: (_) => _deleteReminder(reminder, index),
      child: _ReminderCard(
        reminder: reminder,
        nextReminderText: _formatNextReminder(reminder),
        frequencyColor: _frequencyColor(reminder['frequency']?.toString() ?? ''),
        onToggle: () => _toggleReminder(reminder),
      ),
    );
  }

  Future<bool> _showDeleteConfirm(Map<String, dynamic> reminder) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Reminder'),
            content: Text(
              'Delete reminder for ${reminder['medicine_name'] ?? 'this medicine'}?',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
  }
}

class _ReminderCard extends StatelessWidget {
  final Map<String, dynamic> reminder;
  final String nextReminderText;
  final Color frequencyColor;
  final VoidCallback onToggle;

  const _ReminderCard({
    required this.reminder,
    required this.nextReminderText,
    required this.frequencyColor,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final medicineName = reminder['medicine_name']?.toString() ?? 'Unknown Medicine';
    final dosage = reminder['dosage']?.toString() ?? '';
    final frequency = reminder['frequency']?.toString() ?? '';
    final isActive = reminder['is_active'] == true;
    final memberName = reminder['family_member_name']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0x1A00897B)
                    : const Color(0x1A9E9E9E),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.alarm,
                color: isActive ? AppTheme.primary : Colors.grey,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    medicineName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: isActive ? AppTheme.textPrimary : AppTheme.textSecondary,
                    ),
                  ),
                  if (dosage.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      dosage,
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (frequency.isNotEmpty)
                        _Chip(label: frequency, color: frequencyColor),
                      _Chip(
                        label: nextReminderText,
                        color: nextReminderText == 'Overdue' ? AppTheme.error : AppTheme.secondary,
                        icon: Icons.schedule,
                      ),
                      if (memberName.isNotEmpty)
                        _Chip(label: memberName, color: Colors.grey.shade600, icon: Icons.person),
                    ],
                  ),
                ],
              ),
            ),
            Switch(
              value: isActive,
              onChanged: (_) => onToggle(),
              activeColor: AppTheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const _Chip({required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Color.fromRGBO(color.red, color.green, color.blue, 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: 11),
            const SizedBox(width: 3),
          ],
          Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
