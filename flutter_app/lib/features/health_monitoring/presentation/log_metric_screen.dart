import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/features/health_monitoring/data/health_api.dart';
import 'package:vitapulse_ai/shared/widgets/loading_button.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';

/// Log a new metric, or edit an existing one (HN-HEALTH-005) when [initialMetric] is set.
class LogMetricScreen extends StatefulWidget {
  /// Existing metric map from summary history / list (must include `id`).
  final Map<String, dynamic>? initialMetric;

  /// Metric type key when editing (e.g. blood_pressure). Required with [initialMetric].
  final String? initialMetricTypeKey;

  const LogMetricScreen({
    super.key,
    this.initialMetric,
    this.initialMetricTypeKey,
  });

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

  static const _keyToLabel = {
    'blood_pressure': 'Blood Pressure',
    'blood_sugar': 'Blood Sugar',
    'heart_rate': 'Heart Rate',
    'oxygen_saturation': 'SpO2',
    'oxygen_level': 'SpO2',
    'weight': 'Weight',
    'temperature': 'Temperature',
  };

  bool get _isEdit => widget.initialMetric != null;

  int? get _editMetricId {
    final raw = widget.initialMetric?['id'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  @override
  void initState() {
    super.initState();
    _prefillFromInitial();
    _loadFamilyMembers();
  }

  void _prefillFromInitial() {
    final m = widget.initialMetric;
    if (m == null) return;

    final typeKey = (widget.initialMetricTypeKey ??
            m['metric_type']?.toString() ??
            'blood_pressure')
        .toLowerCase();
    _metricType = _keyToLabel[typeKey] ?? 'Blood Pressure';

    final v = (m['value'] as num?)?.toDouble();
    final v2 = (m['value2'] as num?)?.toDouble();
    if (_metricType == 'Blood Pressure') {
      if (v != null) {
        _systolicController.text =
            v % 1 == 0 ? v.toStringAsFixed(0) : v.toString();
      }
      if (v2 != null) {
        _diastolicController.text =
            v2 % 1 == 0 ? v2.toStringAsFixed(0) : v2.toString();
      }
    } else if (v != null) {
      _valueController.text =
          v % 1 == 0 ? v.toStringAsFixed(0) : v.toString();
    }

    final notes = m['notes']?.toString();
    if (notes != null && notes.isNotEmpty) {
      _notesController.text = notes;
    }

    final recorded = m['recorded_at']?.toString();
    if (recorded != null && recorded.isNotEmpty) {
      try {
        _loggedAt = DateTime.parse(recorded).toLocal();
      } catch (_) {}
    }

    final fm = m['family_member_id'];
    if (fm is int) {
      _selectedFamilyMemberId = fm;
    } else if (fm is num) {
      _selectedFamilyMemberId = fm.toInt();
    }
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
    );
    if (pickedDate == null) return;

    if (!mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_loggedAt),
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
    final isToday =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final dateStr = isToday ? 'Today' : '${dt.day}/${dt.month}/${dt.year}';
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$dateStr at $h:$m $ampm';
  }

  String _friendlyError(Object e) {
    if (e is DioException) {
      final status = e.response?.statusCode;
      if (status == 404) {
        return 'This reading was not found or you cannot edit it.';
      }
      if (status == 401 || status == 403) {
        return 'Your session has expired. Please sign in again.';
      }
      if (status == 422) {
        return 'Please check the values and try again.';
      }
      if (status != null && status >= 500) {
        return 'The server encountered a problem. Please try again.';
      }
      switch (e.type) {
        case DioExceptionType.connectionError:
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Could not reach the server. Check your connection and try again.';
        default:
          break;
      }
    }
    return _isEdit
        ? 'Failed to update metric. Please try again.'
        : 'Failed to log metric. Please try again.';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    final metricKey = _metricKeyMap[_metricType] ??
        _metricType.toLowerCase().replaceAll(' ', '_');

    try {
      if (_isEdit) {
        final id = _editMetricId;
        if (id == null) {
          throw StateError('Missing metric id');
        }
        final value = _isBP
            ? double.parse(_systolicController.text.trim())
            : double.parse(_valueController.text.trim());
        final value2 = _isBP
            ? double.parse(_diastolicController.text.trim())
            : null;
        final notesText = _notesController.text.trim();

        // Family ownership is frozen on edit — do not reassign subject.
        await HealthApi.updateMetric(
          metricId: id,
          value: value,
          value2: value2,
          clearValue2: !_isBP,
          unit: _unit,
          notes: notesText.isEmpty ? null : notesText,
          clearNotes: notesText.isEmpty,
          recordedAt: _loggedAt.toUtc().toIso8601String(),
        );
      } else {
        final data = <String, dynamic>{
          'metric_type': metricKey,
          'recorded_at': _loggedAt.toIso8601String(),
          'notes': _notesController.text.trim(),
          if (_selectedFamilyMemberId != null)
            'family_member_id': _selectedFamilyMemberId,
        };

        if (_isBP) {
          data['value'] = double.parse(_systolicController.text.trim());
          data['value2'] = double.parse(_diastolicController.text.trim());
        } else {
          data['value'] = double.parse(_valueController.text.trim());
        }

        await ApiClient.post('/health-metrics/', data: data);
      }

      if (mounted) {
        final hc = HealthcareColors.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text(_isEdit
                    ? '$_metricType updated'
                    : '$_metricType logged successfully'),
              ],
            ),
            backgroundColor: hc.vitaGood,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_friendlyError(e)),
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
      key: Key(_isEdit ? 'edit_metric_screen' : 'log_metric_screen'),
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Health Metric' : 'Log Health Metric'),
      ),
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
              key: const Key('metric_notes_field'),
              controller: _notesController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                hintText: 'e.g. Taken after rest, post-exercise...',
                prefixIcon: Icon(Icons.notes),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Informational reading only — not a diagnosis or treatment advice.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            LoadingButton(
              key: Key(_isEdit ? 'metric_save_edit_button' : 'metric_log_button'),
              text: _isEdit ? 'Save Changes' : 'Log $_metricType',
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
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.monitor_heart, color: cs.primary, size: 18),
            const SizedBox(width: 8),
            Text(
              'Metric Type',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface),
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
              // Metric type is identity — lock when editing.
              onSelected: _isEdit
                  ? null
                  : (_) => setState(() {
                        _metricType = type;
                        _valueController.clear();
                        _systolicController.clear();
                        _diastolicController.clear();
                      }),
              selectedColor: cs.primary,
              backgroundColor: Colors.white,
              labelStyle: TextStyle(
                color: selected ? Colors.white : cs.onSurface,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 13,
              ),
              side: BorderSide(
                color: selected ? cs.primary : cs.outline,
              ),
              shape: const RoundedRectangleBorder(
                  borderRadius: AppRadius.brXxl),
            );
          }).toList(),
        ),
        if (_isEdit) ...[
          const SizedBox(height: 8),
          Text(
            'Metric type cannot be changed when editing.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  Widget _buildValueSection() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.input, color: cs.primary, size: 18),
            const SizedBox(width: 8),
            Text(
              '$_metricType Value',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.08),
                borderRadius: AppRadius.brMd,
              ),
              child: Text(
                _unit,
                style: TextStyle(
                    color: cs.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_isBP) _buildBPFields() else _buildSingleValueField(),
      ],
    );
  }

  Widget _buildBPFields() {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            key: const Key('metric_systolic_field'),
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
        Text(
          '/',
          style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: cs.onSurfaceVariant),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextFormField(
            key: const Key('metric_diastolic_field'),
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
    final cs = Theme.of(context).colorScheme;
    final hint = _hintMap[_metricType] ?? '0';
    final ranges = _getValidationRange(_metricType);

    return TextFormField(
      key: const Key('metric_value_field'),
      controller: _valueController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: '$_metricType *',
        hintText: hint,
        suffixText: _unit,
        prefixIcon: Icon(_getMetricIcon(_metricType), color: cs.primary),
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
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.calendar_today, color: cs.primary, size: 18),
            const SizedBox(width: 8),
            Text(
              'Date & Time',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface),
            ),
          ],
        ),
        const SizedBox(height: 12),
        InkWell(
          key: const Key('metric_datetime_picker'),
          onTap: _pickDateTime,
          borderRadius: AppRadius.brMd,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border.all(color: cs.outline),
              borderRadius: AppRadius.brMd,
            ),
            child: Row(
              children: [
                Icon(Icons.access_time, color: cs.primary, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _formatDateTime(_loggedAt),
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(Icons.edit, color: cs.onSurfaceVariant, size: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFamilySection() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.family_restroom, color: cs.primary, size: 18),
            const SizedBox(width: 8),
            Text(
              'Logged For',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _loadingFamily
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: CircularProgressIndicator(
                      color: cs.primary, strokeWidth: 2),
                ),
              )
            : Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: cs.outline),
                  borderRadius: AppRadius.brMd,
                ),
                child: DropdownButton<int?>(
                  key: const Key('metric_family_member'),
                  value: _selectedFamilyMemberId,
                  isExpanded: true,
                  underline: const SizedBox(),
                  // Subject locked when correcting an existing reading.
                  items: [
                    const DropdownMenuItem<int?>(
                        value: null, child: Text('Myself')),
                    ..._familyMembers.map(
                      (m) => DropdownMenuItem<int?>(
                        value: m['id'] as int?,
                        child: Text(m['name']?.toString() ?? 'Unknown'),
                      ),
                    ),
                  ],
                  onChanged: _isEdit
                      ? null
                      : (v) => setState(() => _selectedFamilyMemberId = v),
                ),
              ),
        if (_isEdit) ...[
          const SizedBox(height: 8),
          Text(
            'Logged-for subject cannot be changed when editing.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}
