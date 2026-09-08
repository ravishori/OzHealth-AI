import 'package:flutter/material.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/core/notifications/local_reminder_notifications.dart';
import 'package:vitapulse_ai/features/appointments/data/appointment_api.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';

/// HN-REM-010 — create / edit appointment + local reminder schedule.
class AddAppointmentScreen extends StatefulWidget {
  final Map<String, dynamic>? initialAppointment;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> data)?
      createAppointment;
  final Future<Map<String, dynamic>> Function(
    int id,
    Map<String, dynamic> data,
  )? updateAppointment;
  final Future<bool> Function({
    required int appointmentId,
    required String title,
    required DateTime scheduledAt,
    int remindBeforeMinutes,
    String? notes,
  })? scheduleNotification;
  final Future<void> Function(int appointmentId)? cancelNotification;
  final Future<List<Map<String, dynamic>>> Function()? loadFamilyMembers;

  const AddAppointmentScreen({
    super.key,
    this.initialAppointment,
    this.createAppointment,
    this.updateAppointment,
    this.scheduleNotification,
    this.cancelNotification,
    this.loadFamilyMembers,
  });

  bool get isEdit => initialAppointment != null;

  @override
  State<AddAppointmentScreen> createState() => _AddAppointmentScreenState();
}

class _AddAppointmentScreenState extends State<AddAppointmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime _scheduledAt = DateTime.now().add(const Duration(hours: 24));
  int _remindBefore = 60;
  int? _familyMemberId;
  List<Map<String, dynamic>> _family = [];
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _hydrate();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFamily());
  }

  void _hydrate() {
    final initial = widget.initialAppointment;
    if (initial == null) return;
    _titleController.text = initial['title']?.toString() ?? '';
    _notesController.text = initial['notes']?.toString() ?? '';
    final scheduled = parseAppointmentApiDateTime(initial['scheduled_at']);
    if (scheduled != null) _scheduledAt = scheduled;
    final remind = initial['remind_before_minutes'];
    if (remind is int && kAllowedRemindBeforeMinutes.contains(remind)) {
      _remindBefore = remind;
    } else {
      final parsed = int.tryParse('$remind');
      if (parsed != null && kAllowedRemindBeforeMinutes.contains(parsed)) {
        _remindBefore = parsed;
      }
    }
    final fm = initial['family_member_id'];
    if (fm is int) {
      _familyMemberId = fm;
    } else if (fm != null) {
      _familyMemberId = int.tryParse('$fm');
    }
  }

  Future<void> _loadFamily() async {
    try {
      final loader = widget.loadFamilyMembers ??
          () async {
            final resp = await ApiClient.get('/family/');
            final data = resp.data;
            if (data is List) {
              return data
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
            }
            return <Map<String, dynamic>>[];
          };
      final members = await loader();
      if (!mounted) return;
      setState(() => _family = members);
    } catch (_) {
      // Family optional — leave empty on failure.
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _scheduledAt,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (pickedDate == null) return;
    if (!mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledAt),
    );
    if (pickedTime == null) return;
    setState(() {
      _scheduledAt = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  String _formatDateTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final tod = TimeOfDay.fromDateTime(dt);
    return '$y-$m-$d · ${tod.format(context)}';
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    final payload = buildAppointmentSavePayload(
      title: _titleController.text,
      scheduledAt: _scheduledAt,
      notes: _notesController.text,
      remindBeforeMinutes: _remindBefore,
      familyMemberId: _familyMemberId,
    );

    try {
      Map<String, dynamic> saved;
      if (widget.isEdit) {
        final rawId = widget.initialAppointment!['id'];
        final id = rawId is int ? rawId : int.parse('$rawId');
        final updater = widget.updateAppointment ??
            (int aid, Map<String, dynamic> data) =>
                AppointmentApi.updateAppointment(aid, data);
        saved = await updater(id, payload);
      } else {
        final creator = widget.createAppointment ??
            (Map<String, dynamic> data) =>
                AppointmentApi.createAppointment(data);
        saved = await creator(payload);
      }

      final rawId = saved['id'];
      final appointmentId = rawId is int ? rawId : int.parse('$rawId');
      final title = saved['title']?.toString() ?? _titleController.text.trim();
      final scheduled =
          parseAppointmentApiDateTime(saved['scheduled_at']) ?? _scheduledAt;
      final remind = saved['remind_before_minutes'] is int
          ? saved['remind_before_minutes'] as int
          : _remindBefore;
      final notes = saved['notes']?.toString();
      final active = saved['is_active'] != false;

      final schedule = widget.scheduleNotification ??
          ({
            required int appointmentId,
            required String title,
            required DateTime scheduledAt,
            int remindBeforeMinutes = 60,
            String? notes,
          }) =>
              LocalReminderNotifications.scheduleAppointmentReminder(
                appointmentId: appointmentId,
                title: title,
                scheduledAt: scheduledAt,
                remindBeforeMinutes: remindBeforeMinutes,
                notes: notes,
              );
      final cancel = widget.cancelNotification ??
          LocalReminderNotifications.cancelAppointmentNotification;

      var notificationScheduled = true;
      if (active) {
        notificationScheduled = await schedule(
          appointmentId: appointmentId,
          title: title,
          scheduledAt: scheduled,
          remindBeforeMinutes: remind,
          notes: notes,
        );
      } else {
        await cancel(appointmentId);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            notificationScheduled
                ? (widget.isEdit
                    ? 'Appointment updated (on-device reminder scheduled)'
                    : 'Appointment saved (on-device reminder scheduled)')
                : (widget.isEdit
                    ? 'Appointment updated, but notification permission is off. '
                        'Enable notifications in system settings to get alerts.'
                    : 'Appointment saved, but notification permission is off. '
                        'Enable notifications in system settings to get alerts.'),
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not save appointment. Please try again.';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      key: Key(widget.isEdit
          ? 'edit_appointment_screen'
          : 'add_appointment_screen'),
      appBar: AppBar(
        title: Text(widget.isEdit ? 'Edit Appointment' : 'Add Appointment'),
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            TextFormField(
              key: const Key('appointment_title_field'),
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title / reason',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                if (v.trim().length > 300) return 'Too long';
                return null;
              },
            ),
            const SizedBox(height: 16),
            InkWell(
              key: const Key('appointment_datetime_picker'),
              onTap: _pickDateTime,
              borderRadius: AppRadius.brMd,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date & time',
                  border: OutlineInputBorder(),
                ),
                child: Text(_formatDateTime(_scheduledAt)),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              key: const Key('appointment_remind_before'),
              value: _remindBefore,
              decoration: const InputDecoration(
                labelText: 'Remind me',
                border: OutlineInputBorder(),
              ),
              items: kAllowedRemindBeforeMinutes
                  .map(
                    (m) => DropdownMenuItem(
                      value: m,
                      child: Text(remindBeforeLabel(m)),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _remindBefore = v);
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('appointment_notes_field'),
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int?>(
              key: const Key('appointment_family_member'),
              value: _familyMemberId,
              decoration: const InputDecoration(
                labelText: 'For (optional)',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Self'),
                ),
                ..._family.map((m) {
                  final id = m['id'];
                  final intId = id is int ? id : int.tryParse('$id');
                  return DropdownMenuItem<int?>(
                    value: intId,
                    child: Text(m['name']?.toString() ?? 'Member'),
                  );
                }),
              ],
              onChanged: (v) => setState(() => _familyMemberId = v),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const Key('appointment_form_error'),
                style: TextStyle(color: cs.error),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('appointment_save_button'),
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(widget.isEdit ? 'Save changes' : 'Save appointment'),
            ),
          ],
        ),
      ),
    );
  }
}
