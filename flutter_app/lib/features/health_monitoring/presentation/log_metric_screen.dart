import 'package:vitapulse_ai/core/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/core/theme/app_theme.dart';
import 'package:vitapulse_ai/shared/widgets/loading_button.dart';

class LogMetricScreen extends StatefulWidget {
  const LogMetricScreen({super.key});

  @override
  State<LogMetricScreen> createState() => _LogMetricScreenState();
}

class _LogMetricScreenState extends State<LogMetricScreen> {
  final _formKey = GlobalKey<FormState>();

  // Metric type
  String _metricType = 'Blood Pressure';

  // Controllers
  final _systolicController = TextEditingController();
  final _diastolicController = TextEditingController();
  final _valueController = TextEditingController();
  final _notesController = TextEditingController();

  // Date / time
  DateTime _loggedAt = DateTime.now();

  // Family members
  List<Map<String, dynamic>> _familyMembers = [];
  int? _selectedFamilyMemberId;
  bool _loadingFamily = true;

  bool _loading = false;

  static const _metricTypes = [
    'Blood Pressure',
    'Blood Sugar',
    'Heart Rate',
    'SpO2',
    'Weight',
    'Temperature',
  ];

  static const _unitMap = {
    'Blood Pressure': 'mmHg',
    'Blood Sugar': 'mg/dL',
    'Heart Rate': 'bpm',
    'SpO2': '%',
    'Weight': 'kg',
    'Temperature': '°C',
  };

  static const _hintMap = {
    'Blood Sugar': '70–200',
    'Heart Rate': '60–100',
    'SpO2': '95–100',
    'Weight': '50.0',
    'Temperature': '36.5',
  };

  static const _metricKeyMap = {
    'Blood Pressure': 'blood_pressure',
    'Blood Sugar': 'blood_sugar',
    'Heart Rate': 'heart_rate',
    'SpO2': 'oxygen_saturation',
    'Weight': 'weight',
    'Temperature': 'temperature',
  };

  @override
  void initState() {
    super.initState();
    _loadFamilyMembers();
  }

  @override
  void dispose() {
    _systolicController.dispose();
    _diastolicController.dispose();
    _valueController.dispose();
    _notesController.dispose();
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

  bool get _isBP => _metricType == 'Blood Pressure';

  String get _unit => _unitMap[_metricType] ?? '';

  Future<void> _pickDateTime() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _loggedAt,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AppTheme.primary),
        ),
        child: child!,
      ),
    );
    if (pickedDate == null) return;

    if (!mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_loggedAt),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AppTheme.primary),
        ),
        child: child!,
      ),
    );
    if (pickedTime == null) return;

    setState(() {
      _loggedAt = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final dateStr = isToday ? 'Today' : '${dt.day}/${dt.month}/${dt.year}';
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$dateStr at $h:$m $ampm';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    final metricKey = _metricKeyMap[_metricType] ?? _metricType.toLowerCase().replaceAll(' ', '_');

    Map<String, dynamic> data = {
      'metric_type': metricKey,
      'logged_at': _loggedAt.toIso8601String(),
      'notes': _notesController.text.trim(),
      if (_selectedFamilyMemberId != null) 'family_member_id': _selectedFamilyMemberId,
    };

    if (_isBP) {
      data['systolic'] = double.parse(_systolicController.text.trim());
      data['diastolic'] = double.parse(_diastolicController.text.trim());
      data['value'] = double.parse(_systolicController.text.trim()); // convenience field
    } else {
      data['value'] = double.parse(_valueController.text.trim());
    }

    try {
      await ApiClient.post('/health-metrics/', data: data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text('$_metricType logged successfully'),
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
            content: Text('Failed to log metric. Please try again.'),
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
      appBar: AppBar(title: const Text('Log Health Metric')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildMetricTypeSelector(),
            const SizedBox(height: 20),
            _buildValueSection(),
            const SizedBox(height: 20),
            _buildDateTimeSection(),
            const SizedBox(height: 20),
            _buildFamilySection(),
            const SizedBox(height: 14),
            TextFormField(
              controller: _notesController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                hintText: 'e.g. Taken after rest, post-exercise...',
                prefixIcon: Icon(Icons.notes),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 32),
            LoadingButton(
              text: 'Log $_metricType',
              loading: _loading,
              onPressed: _submit,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.monitor_heart, color: AppTheme.primary, size: 18),
            SizedBox(width: 8),
            Text(
              'Metric Type',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _metricTypes.map((type) {
            final selected = _metricType == type;
            return ChoiceChip(
              label: Text(type),
              selected: selected,
              onSelected: (_) => setState(() {
                _metricType = type;
                _valueController.clear();
                _systolicController.clear();
                _diastolicController.clear();
              }),
              selectedColor: AppTheme.primary,
              backgroundColor: Colors.white,
              labelStyle: TextStyle(
                color: selected ? Colors.white : AppTheme.textPrimary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 13,
              ),
              side: BorderSide(
                color: selected ? AppTheme.primary : Colors.grey.shade300,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildValueSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.input, color: AppTheme.primary, size: 18),
            const SizedBox(width: 8),
            Text(
              '$_metricType Value',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0x1A00897B),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _unit,
                style: const TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_isBP)
          _buildBPFields()
        else
          _buildSingleValueField(),
      ],
    );
  }

  Widget _buildBPFields() {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: _systolicController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Systolic *',
              hintText: '120',
              suffixText: 'mmHg',
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              final n = double.tryParse(v.trim());
              if (n == null) return 'Invalid';
              if (n < 50 || n > 300) return '50–300';
              return null;
            },
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          '/',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextFormField(
            controller: _diastolicController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Diastolic *',
              hintText: '80',
              suffixText: 'mmHg',
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              final n = double.tryParse(v.trim());
              if (n == null) return 'Invalid';
              if (n < 30 || n > 200) return '30–200';
              return null;
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSingleValueField() {
    final hint = _hintMap[_metricType] ?? '0';
    final ranges = _getValidationRange(_metricType);

    return TextFormField(
      controller: _valueController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: '$_metricType *',
        hintText: hint,
        suffixText: _unit,
        prefixIcon: Icon(_getMetricIcon(_metricType), color: AppTheme.primary),
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Please enter a value';
        final n = double.tryParse(v.trim());
        if (n == null) return 'Please enter a valid number';
        if (ranges != null && (n < ranges.$1 || n > ranges.$2)) {
          return 'Expected range: ${ranges.$1}–${ranges.$2}';
        }
        return null;
      },
    );
  }

  (double, double)? _getValidationRange(String type) {
    switch (type) {
      case 'Blood Sugar':
        return (0, 600);
      case 'Heart Rate':
        return (20, 300);
      case 'SpO2':
        return (50, 100);
      case 'Weight':
        return (1, 500);
      case 'Temperature':
        return (30, 45);
      default:
        return null;
    }
  }

  IconData _getMetricIcon(String type) {
    switch (type) {
      case 'Blood Sugar':
        return Icons.water_drop;
      case 'Heart Rate':
        return Icons.favorite;
      case 'SpO2':
        return Icons.air;
      case 'Weight':
        return Icons.scale;
      case 'Temperature':
        return Icons.thermostat;
      default:
        return Icons.monitor_heart;
    }
  }

  Widget _buildDateTimeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.calendar_today, color: AppTheme.primary, size: 18),
            SizedBox(width: 8),
            Text(
              'Date & Time',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
          ],
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: _pickDateTime,
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
                Expanded(
                  child: Text(
                    _formatDateTime(_loggedAt),
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const Icon(Icons.edit, color: AppTheme.textSecondary, size: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFamilySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.family_restroom, color: AppTheme.primary, size: 18),
            SizedBox(width: 8),
            Text(
              'Logged For',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _loadingFamily
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2),
                ),
              )
            : DropdownButtonFormField<int?>(
                value: _selectedFamilyMemberId,
                decoration: const InputDecoration(
                  labelText: 'Family Member (optional)',
                  prefixIcon: Icon(Icons.person),
                ),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('Myself')),
                  ..._familyMembers.map(
                    (m) => DropdownMenuItem<int?>(
                      value: m['id'] as int?,
                      child: Text(m['name']?.toString() ?? 'Unknown'),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => _selectedFamilyMemberId = v),
              ),
      ],
    );
  }
}
