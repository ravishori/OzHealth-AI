import 'package:flutter/material.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/core/notifications/local_reminder_notifications.dart';
import 'package:vitapulse_ai/shared/widgets/loading_button.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';

/// Maps UI labels to DB CHECK values (`daily`, `twice_daily`, …).
String medicationFrequencyToApi(String label) {
  switch (label) {
    case 'Daily':
      return 'daily';
    case 'Twice Daily':
      return 'twice_daily';
    case 'Three Times Daily':
      return 'three_times_daily';
    case 'Weekly':
      return 'weekly';
    case 'Monthly':
      return 'monthly';
    case 'As Needed':
      return 'as_needed';
    default:
      return label.trim().toLowerCase().replaceAll(' ', '_');
  }
}

/// Parse API `YYYY-MM-DD` (or ISO datetime) into a local calendar date.
DateTime? parseReminderApiDate(dynamic raw) {
  if (raw == null) return null;
  final s = raw.toString().trim();
  if (s.isEmpty) return null;
  final parsed = DateTime.tryParse(s);
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

/// Build create/update JSON for `/reminders` (HN-REM-009 refill_date).
///
/// On edit, `refill_date` is always sent (`null` clears). On create, omit when unset.
Map<String, dynamic> buildReminderSavePayload({
  required String medicineName,
  required String dosage,
  required String frequencyApi,
  required List<String> times,
  required String instructions,
  required bool isEdit,
  DateTime? startDate,
  DateTime? endDate,
  DateTime? refillDate,
  int? totalQuantity,
  int? remainingQuantity,
  int? familyMemberId,
}) {
  final data = <String, dynamic>{
    'medicine_name': medicineName,
    'dosage': dosage,
    'frequency': frequencyApi,
    'times': times,
    'instructions': instructions,
    'family_member_id': familyMemberId,
    if (!isEdit) 'is_active': true,
    if (!isEdit && startDate != null)
      'start_date': startDate.toIso8601String().split('T').first,
    if (endDate != null) 'end_date': endDate.toIso8601String().split('T').first,
    if (totalQuantity != null) 'total_quantity': totalQuantity,
    if (remainingQuantity != null) 'remaining_quantity': remainingQuantity,
  };
  if (isEdit || refillDate != null) {
    data['refill_date'] =
        refillDate?.toIso8601String().split('T').first;
  }
  return data;
}

class AddReminderScreen extends StatefulWidget {
  /// When set, screen edits an existing reminder via PUT.
  final Map<String, dynamic>? initialReminder;

  const AddReminderScreen({super.key, this.initialReminder});

  @override
  State<AddReminderScreen> createState() => _AddReminderScreenState();
}

class _AddReminderScreenState extends State<AddReminderScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _medicineNameController = TextEditingController();
  final _dosageController = TextEditingController();
  final _instructionsController = TextEditingController();
  final _totalQuantityController = TextEditingController();
  final _remainingQuantityController = TextEditingController();

  // State
  String _frequency = 'Daily';
  List<TimeOfDay> _times = [TimeOfDay.now()];
  DateTime? _startDate;
  DateTime? _endDate;
  DateTime? _refillDate;
  List<Map<String, dynamic>> _familyMembers = [];
  int? _selectedFamilyMemberId;
  bool _loading = false;
  bool _loadingFamily = true;

  bool get _isEdit => widget.initialReminder != null;
  int? get _editId {
    final id = widget.initialReminder?['id'];
    if (id is int) return id;
    return int.tryParse(id?.toString() ?? '');
  }

  static const List<String> _frequencies = [
    'Daily',
    'Twice Daily',
    'Three Times Daily',
    'Weekly',
    'Monthly',
    'As Needed',
  ];

  int _timesCountForFrequency(String freq) {
    switch (freq) {
      case 'Twice Daily':
        return 2;
      case 'Three Times Daily':
        return 3;
      default:
        return 1;
    }
  }

  /// Maps UI labels to DB CHECK values (`daily`, `twice_daily`, …).
  static String frequencyToApi(String label) => medicationFrequencyToApi(label);

  static String _apiFrequencyToLabel(String? api) {
    switch ((api ?? '').toLowerCase()) {
      case 'daily':
        return 'Daily';
      case 'twice_daily':
        return 'Twice Daily';
      case 'three_times_daily':
        return 'Three Times Daily';
      case 'weekly':
        return 'Weekly';
      case 'monthly':
        return 'Monthly';
      case 'as_needed':
        return 'As Needed';
      default:
        return 'Daily';
    }
  }

  static TimeOfDay? _parseTime(String raw) {
    final parts = raw.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  @override
  void initState() {
    super.initState();
    _startDate = DateTime.now();
    final initial = widget.initialReminder;
    if (initial != null) {
      _medicineNameController.text =
          initial['medicine_name']?.toString() ?? '';
      _dosageController.text = initial['dosage']?.toString() ?? '';
      _instructionsController.text =
          initial['instructions']?.toString() ?? '';
      _frequency = _apiFrequencyToLabel(initial['frequency']?.toString());
      final times = initial['times'];
      if (times is List && times.isNotEmpty) {
        _times = times
            .map((e) => _parseTime(e.toString()))
            .whereType<TimeOfDay>()
            .toList();
        if (_times.isEmpty) _times = [TimeOfDay.now()];
      }
      _startDate = parseReminderApiDate(initial['start_date']) ?? _startDate;
      _endDate = parseReminderApiDate(initial['end_date']);
      _refillDate = parseReminderApiDate(initial['refill_date']);
      final tq = initial['total_quantity'];
      if (tq != null) _totalQuantityController.text = tq.toString();
      final rq = initial['remaining_quantity'];
      if (rq != null) _remainingQuantityController.text = rq.toString();
      final fm = initial['family_member_id'];
      if (fm is int) {
        _selectedFamilyMemberId = fm;
      } else if (fm != null) {
        _selectedFamilyMemberId = int.tryParse(fm.toString());
      }
    }
    _loadFamilyMembers();
  }

  @override
  void dispose() {
    _medicineNameController.dispose();
    _dosageController.dispose();
    _instructionsController.dispose();
    _totalQuantityController.dispose();
    _remainingQuantityController.dispose();
    super.dispose();
  }

  Future<void> _loadFamilyMembers() async {
    try {
      final resp = await ApiClient.get('/family/');
      setState(() {
        _familyMembers = List<Map<String, dynamic>>.from(
          resp.data is List ? resp.data : (resp.data['members'] ?? []),
        );
        _loadingFamily = false;
      });
    } catch (_) {
      setState(() => _loadingFamily = false);
    }
  }

  void _onFrequencyChanged(String? freq) {
    if (freq == null) return;
    setState(() {
      _frequency = freq;
      final count = _timesCountForFrequency(freq);
      if (_times.length < count) {
        while (_times.length < count) {
          _times.add(TimeOfDay.now());
        }
      } else if (_times.length > count) {
        _times = _times.sublist(0, count);
      }
    });
  }

  Future<void> _pickTime(int index) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _times[index],
    );
    if (picked != null) {
      setState(() => _times[index] = picked);
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart
        ? (_startDate ?? DateTime.now())
        : (_endDate ?? DateTime.now().add(const Duration(days: 30)));
    final firstDate = isStart
        ? DateTime.now().subtract(const Duration(days: 365))
        : (_startDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate != null && _endDate!.isBefore(_startDate!)) {
            _endDate = null;
          }
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _pickRefillDate() async {
    final today = DateTime.now();
    final initial = _refillDate ?? today.add(const Duration(days: 7));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(today) ? today : initial,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365 * 3)),
    );
    if (picked != null) {
      setState(() => _refillDate = DateTime(picked.year, picked.month, picked.day));
    }
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return 'Not set';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  String _formatTime(TimeOfDay t) {
    final h = t.hour > 12 ? t.hour - 12 : (t.hour == 0 ? 12 : t.hour);
    final m = t.minute.toString().padLeft(2, '0');
    final ampm = t.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_loading) return;

    setState(() => _loading = true);

    final timesFormatted = _times.map((t) {
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }).toList();

    final data = buildReminderSavePayload(
      medicineName: _medicineNameController.text.trim(),
      dosage: _dosageController.text.trim(),
      frequencyApi: frequencyToApi(_frequency),
      times: timesFormatted,
      instructions: _instructionsController.text.trim(),
      isEdit: _isEdit,
      startDate: _startDate,
      endDate: _endDate,
      refillDate: _refillDate,
      totalQuantity: int.tryParse(_totalQuantityController.text.trim()),
      remainingQuantity:
          int.tryParse(_remainingQuantityController.text.trim()),
      familyMemberId: _selectedFamilyMemberId,
    );

    try {
      late final Map<String, dynamic> saved;
      if (_isEdit && _editId != null) {
        final resp = await ApiClient.put('/reminders/$_editId', data: data);
        saved = resp.data is Map
            ? Map<String, dynamic>.from(resp.data as Map)
            : <String, dynamic>{};
      } else {
        final resp = await ApiClient.post('/reminders/', data: data);
        saved = resp.data is Map
            ? Map<String, dynamic>.from(resp.data as Map)
            : <String, dynamic>{};
      }
      final scheduleId = saved['id'] as int? ??
          _editId ??
          DateTime.now().millisecondsSinceEpoch % 100000;
      final scheduled =
          await LocalReminderNotifications.scheduleMedicationReminders(
        scheduleId: scheduleId,
        medicineName: _medicineNameController.text.trim(),
        times: timesFormatted,
        dosage: _dosageController.text.trim(),
        frequencyApi: frequencyToApi(_frequency),
        startDate: _startDate,
        refillDate: _refillDate,
      );
      if (mounted) {
        final hc = HealthcareColors.of(context);
        final forWhom = saved['family_member_name']?.toString();
        final whoBit = (forWhom != null && forWhom.isNotEmpty)
            ? ' for $forWhom'
            : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  scheduled
                      ? Icons.check_circle
                      : Icons.notifications_off_outlined,
                  color: Colors.white,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    scheduled
                        ? '${_isEdit ? 'Reminder updated' : 'Reminder set'}'
                            '${whoBit.isEmpty ? '' : whoBit} '
                            '(on-device notification scheduled)'
                        : 'Reminder saved$whoBit, but notification permission is off. '
                            'Enable notifications in system settings to get alerts.',
                  ),
                ),
              ],
            ),
            backgroundColor: scheduled ? hc.vitaGood : hc.vitaWarning,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        final msg = e.toString().contains('404')
            ? 'Could not save reminder. Check the selected family member and try again.'
            : 'Failed to save reminder. Please try again.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(title: Text(_isEdit ? 'Edit Reminder' : 'Add Reminder')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _SectionHeader(
                title: 'Medicine Details', icon: Icons.medication),
            const SizedBox(height: 12),

            // Medicine name
            TextFormField(
              controller: _medicineNameController,
              decoration: const InputDecoration(
                labelText: 'Medicine Name *',
                hintText: 'e.g. Paracetamol 500mg',
                prefixIcon: Icon(Icons.medication_outlined),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty)
                      ? 'Medicine name is required'
                      : null,
            ),
            const SizedBox(height: 14),

            // Dosage
            TextFormField(
              controller: _dosageController,
              decoration: const InputDecoration(
                labelText: 'Dosage *',
                hintText: 'e.g. 1 tablet, 5ml',
                prefixIcon: Icon(Icons.scale),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Dosage is required' : null,
            ),
            const SizedBox(height: 20),

            const _SectionHeader(title: 'Schedule', icon: Icons.schedule),
            const SizedBox(height: 12),

            // Frequency dropdown
            DropdownButtonFormField<String>(
              initialValue: _frequency,
              decoration: const InputDecoration(
                labelText: 'Frequency *',
                prefixIcon: Icon(Icons.repeat),
              ),
              items: _frequencies
                  .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                  .toList(),
              onChanged: _onFrequencyChanged,
            ),
            const SizedBox(height: 14),

            // Time pickers
            if (_frequency != 'As Needed') ...[
              Text(
                _times.length == 1
                    ? 'Reminder Time'
                    : 'Reminder Times (${_times.length})',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              ...List.generate(_times.length, (i) {
                final label = _times.length == 1
                    ? 'Time'
                    : (i == 0
                        ? 'Morning'
                        : i == 1
                            ? 'Afternoon / Evening'
                            : 'Night');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    onTap: () => _pickTime(i),
                    borderRadius: AppRadius.brMd,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        border: Border.all(color: cs.outline),
                        borderRadius: AppRadius.brMd,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.access_time, color: cs.primary, size: 20),
                          const SizedBox(width: 12),
                          Text(
                            label,
                            style: TextStyle(
                                color: cs.onSurfaceVariant, fontSize: 14),
                          ),
                          const Spacer(),
                          Text(
                            _formatTime(_times[i]),
                            style: TextStyle(
                              color: cs.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.chevron_right,
                              color: cs.onSurfaceVariant, size: 18),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 6),
            ],

            // Date pickers
            Row(
              children: [
                Expanded(
                  child: _DatePickerTile(
                    label: 'Start Date',
                    value: _formatDate(_startDate),
                    icon: Icons.calendar_today,
                    onTap: () => _pickDate(isStart: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DatePickerTile(
                    label: 'End Date',
                    value: _formatDate(_endDate),
                    icon: Icons.event_available,
                    optional: true,
                    onTap: () => _pickDate(isStart: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _DatePickerTile(
              label: 'Refill Date',
              value: _formatDate(_refillDate),
              icon: Icons.local_pharmacy_outlined,
              optional: true,
              onTap: _pickRefillDate,
              onClear: _refillDate == null
                  ? null
                  : () => setState(() => _refillDate = null),
            ),
            const SizedBox(height: 20),

            const _SectionHeader(
                title: 'Instructions & Quantity', icon: Icons.info_outline),
            const SizedBox(height: 12),

            TextFormField(
              controller: _instructionsController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Instructions',
                hintText: 'e.g. Take after meals with water',
                prefixIcon: Icon(Icons.notes),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _totalQuantityController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Total Qty',
                      hintText: 'e.g. 30',
                      prefixIcon: Icon(Icons.inventory_2_outlined),
                    ),
                    validator: (v) {
                      if (v != null &&
                          v.isNotEmpty &&
                          int.tryParse(v) == null) {
                        return 'Must be a number';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _remainingQuantityController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Remaining Qty',
                      hintText: 'e.g. 30',
                      prefixIcon: Icon(Icons.medication_outlined),
                    ),
                    validator: (v) {
                      if (v != null &&
                          v.isNotEmpty &&
                          int.tryParse(v) == null) {
                        return 'Must be a number';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            const _SectionHeader(
                title: 'For Family Member', icon: Icons.family_restroom),
            const SizedBox(height: 12),

            _loadingFamily
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                          color: Theme.of(context).colorScheme.primary,
                          strokeWidth: 2),
                    ),
                  )
                : DropdownButtonFormField<int?>(
                    initialValue: _selectedFamilyMemberId,
                    decoration: const InputDecoration(
                      labelText: 'Family Member (optional)',
                      prefixIcon: Icon(Icons.person),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Myself'),
                      ),
                      ..._familyMembers.map((m) => DropdownMenuItem<int?>(
                            value: m['id'] as int?,
                            child: Text(m['name']?.toString() ?? 'Unknown'),
                          )),
                    ],
                    onChanged: (v) =>
                        setState(() => _selectedFamilyMemberId = v),
                  ),
            const SizedBox(height: 32),

            LoadingButton(
              text: 'Set Reminder',
              loading: _loading,
              onPressed: _submit,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, color: cs.primary, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: cs.onSurface,
          ),
        ),
      ],
    );
  }
}

class _DatePickerTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
  final bool optional;
  final VoidCallback? onClear;

  const _DatePickerTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.optional = false,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brMd,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border.all(color: cs.outline),
          borderRadius: AppRadius.brMd,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: cs.primary, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label + (optional ? ' (opt)' : ''),
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                  ),
                ),
                if (onClear != null)
                  InkWell(
                    onTap: onClear,
                    borderRadius: AppRadius.brSm,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.clear,
                        size: 16,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: value == 'Not set' ? cs.onSurfaceVariant : cs.primary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
