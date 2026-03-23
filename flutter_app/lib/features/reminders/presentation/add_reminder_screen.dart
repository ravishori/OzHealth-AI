import 'package:vitapulse_ai/core/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/core/theme/app_theme.dart';
import 'package:vitapulse_ai/shared/widgets/loading_button.dart';

class AddReminderScreen extends StatefulWidget {
  const AddReminderScreen({super.key});

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
  List<Map<String, dynamic>> _familyMembers = [];
  int? _selectedFamilyMemberId;
  bool _loading = false;
  bool _loadingFamily = true;

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

  @override
  void initState() {
    super.initState();
    _startDate = DateTime.now();
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
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AppTheme.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _times[index] = picked);
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? (_startDate ?? DateTime.now()) : (_endDate ?? DateTime.now().add(const Duration(days: 30)));
    final firstDate = isStart ? DateTime.now().subtract(const Duration(days: 365)) : (_startDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AppTheme.primary),
        ),
        child: child!,
      ),
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

    setState(() => _loading = true);

    final timesFormatted = _times.map((t) {
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }).toList();

    final data = {
      'medicine_name': _medicineNameController.text.trim(),
      'dosage': _dosageController.text.trim(),
      'frequency': _frequency,
      'times': timesFormatted,
      'instructions': _instructionsController.text.trim(),
      'start_date': _startDate?.toIso8601String().split('T').first,
      if (_endDate != null) 'end_date': _endDate!.toIso8601String().split('T').first,
      if (_totalQuantityController.text.trim().isNotEmpty)
        'total_quantity': int.tryParse(_totalQuantityController.text.trim()),
      if (_remainingQuantityController.text.trim().isNotEmpty)
        'remaining_quantity': int.tryParse(_remainingQuantityController.text.trim()),
      if (_selectedFamilyMemberId != null) 'family_member_id': _selectedFamilyMemberId,
      'is_active': true,
    };

    try {
      await ApiClient.post('/reminders/', data: data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text('Reminder set for ${_medicineNameController.text.trim()}'),
              ],
            ),
            backgroundColor: AppTheme.success,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to create reminder. Please try again.'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Add Reminder')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SectionHeader(title: 'Medicine Details', icon: Icons.medication),
            const SizedBox(height: 12),

            // Medicine name
            TextFormField(
              controller: _medicineNameController,
              decoration: const InputDecoration(
                labelText: 'Medicine Name *',
                hintText: 'e.g. Paracetamol 500mg',
                prefixIcon: Icon(Icons.medication_outlined),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Medicine name is required' : null,
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
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Dosage is required' : null,
            ),
            const SizedBox(height: 20),

            _SectionHeader(title: 'Schedule', icon: Icons.schedule),
            const SizedBox(height: 12),

            // Frequency dropdown
            DropdownButtonFormField<String>(
              value: _frequency,
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
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: AppTheme.textPrimary,
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
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.access_time, color: AppTheme.primary, size: 20),
                          const SizedBox(width: 12),
                          Text(
                            label,
                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                          ),
                          const Spacer(),
                          Text(
                            _formatTime(_times[i]),
                            style: const TextStyle(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.chevron_right, color: AppTheme.textSecondary, size: 18),
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
            const SizedBox(height: 20),

            _SectionHeader(title: 'Instructions & Quantity', icon: Icons.info_outline),
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
                      if (v != null && v.isNotEmpty && int.tryParse(v) == null) {
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
                      if (v != null && v.isNotEmpty && int.tryParse(v) == null) {
                        return 'Must be a number';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            _SectionHeader(title: 'For Family Member', icon: Icons.family_restroom),
            const SizedBox(height: 12),

            _loadingFamily
                ? const Center(child: Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2),
                  ))
                : DropdownButtonFormField<int?>(
                    value: _selectedFamilyMemberId,
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
                    onChanged: (v) => setState(() => _selectedFamilyMemberId = v),
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
    return Row(
      children: [
        Icon(icon, color: AppTheme.primary, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
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

  const _DatePickerTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.optional = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppTheme.primary, size: 16),
                const SizedBox(width: 6),
                Text(
                  label + (optional ? ' (opt)' : ''),
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: value == 'Not set' ? AppTheme.textSecondary : AppTheme.primary,
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
