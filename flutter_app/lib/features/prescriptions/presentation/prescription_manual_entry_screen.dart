import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/features/medicines/data/medicine_api.dart';
import 'package:vitapulse_ai/shared/widgets/clinical_safety_banner.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';

/// HN-RX-003 — manual prescription medicine entry (no OCR).
class PrescriptionManualEntryScreen extends StatefulWidget {
  const PrescriptionManualEntryScreen({super.key});

  @override
  State<PrescriptionManualEntryScreen> createState() =>
      _PrescriptionManualEntryScreenState();
}

class _ManualMedicineRow {
  _ManualMedicineRow()
      : nameController = TextEditingController(),
        dosageController = TextEditingController(),
        frequencyController = TextEditingController(),
        instructionsController = TextEditingController();

  final TextEditingController nameController;
  final TextEditingController dosageController;
  final TextEditingController frequencyController;
  final TextEditingController instructionsController;
  int? catalogMedicineId;
  String? artgNumber;
  String matchStatus = 'UNMATCHED';

  void dispose() {
    nameController.dispose();
    dosageController.dispose();
    frequencyController.dispose();
    instructionsController.dispose();
  }

  Map<String, dynamic> toDraft() => {
        'name': nameController.text.trim(),
        'dosage': dosageController.text.trim(),
        'frequency': frequencyController.text.trim(),
        'instructions': instructionsController.text.trim(),
        if (catalogMedicineId != null) 'catalog_medicine_id': catalogMedicineId,
        if (artgNumber != null && artgNumber!.isNotEmpty) 'artg_number': artgNumber,
        'match_status': matchStatus,
      };
}

class _PrescriptionManualEntryScreenState
    extends State<PrescriptionManualEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _doctorCtrl = TextEditingController();
  final List<_ManualMedicineRow> _rows = [_ManualMedicineRow()];
  List<Map<String, dynamic>> _familyMembers = [];
  int? _selectedFamilyMemberId;
  bool _loadingFamily = true;

  @override
  void initState() {
    super.initState();
    _loadFamilyMembers();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    _doctorCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFamilyMembers() async {
    try {
      final resp = await ApiClient.get('/family/');
      if (!mounted) return;
      setState(() {
        _familyMembers = List<Map<String, dynamic>>.from(
          resp.data is List ? resp.data : (resp.data['members'] ?? []),
        );
        _loadingFamily = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingFamily = false);
    }
  }

  void _addRow() => setState(() => _rows.add(_ManualMedicineRow()));

  void _removeRow(int index) {
    if (_rows.length <= 1) return;
    setState(() {
      _rows[index].dispose();
      _rows.removeAt(index);
    });
  }

  Future<void> _pickFromCatalogue(int index) async {
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => const _MedicineCataloguePicker(),
    );
    if (selected == null || !mounted) return;
    final row = _rows[index];
    setState(() {
      row.nameController.text =
          selected['trade_name']?.toString() ??
          selected['name']?.toString() ??
          row.nameController.text;
      row.catalogMedicineId =
          selected['id'] as int? ?? selected['medicine_id'] as int?;
      row.artgNumber =
          selected['ARTG']?.toString() ?? selected['artg_number']?.toString();
      row.matchStatus =
          row.catalogMedicineId != null ? 'MATCHED' : 'UNMATCHED';
      final strength = selected['strength']?.toString();
      if (strength != null &&
          strength.isNotEmpty &&
          row.dosageController.text.trim().isEmpty) {
        row.dosageController.text = strength;
      }
    });
  }

  void _clearCatalogueMatch(int index) {
    setState(() {
      _rows[index].catalogMedicineId = null;
      _rows[index].artgNumber = null;
      _rows[index].matchStatus = 'UNMATCHED';
    });
  }

  void _continueToReview() {
    if (!_formKey.currentState!.validate()) return;
    final medicines = _rows
        .map((r) => r.toDraft())
        .where((m) => (m['name'] as String).isNotEmpty)
        .toList();
    if (medicines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least one medicine name.')),
      );
      return;
    }
    context.push(
      '/home/prescriptions/manual/review',
      extra: {
        'medicines': medicines,
        'doctor_name': _doctorCtrl.text.trim(),
        'family_member_id': _selectedFamilyMemberId,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);

    return Scaffold(
      key: const Key('prescription_manual_entry_screen'),
      appBar: AppBar(
        title: const Text('Manual prescription'),
        actions: [
          TextButton(
            key: const Key('manual_rx_cancel'),
            onPressed: () => context.pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          children: [
            const ClinicalSafetyBanner(
              kind: ClinicalDisclaimerKind.prescriptionManual,
            ),
            const SizedBox(height: 16),
            Text(
              'Enter medicines',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: hc.prescription,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Type details yourself or match from the medicine catalogue. '
              'Nothing is saved until you confirm on the next screen.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            ...List.generate(_rows.length, (i) => _buildMedicineCard(i, cs)),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('manual_rx_add_medicine'),
                onPressed: _addRow,
                icon: const Icon(Icons.add),
                label: const Text('Add medicine'),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('manual_rx_doctor_name'),
              controller: _doctorCtrl,
              decoration: const InputDecoration(
                labelText: 'Doctor name (optional)',
                hintText: 'As written on the prescription',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (_loadingFamily)
              const LinearProgressIndicator()
            else
              DropdownButtonFormField<int?>(
                key: const Key('manual_rx_family_member'),
                initialValue: _selectedFamilyMemberId,
                decoration: const InputDecoration(
                  labelText: 'For (family member)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Self'),
                  ),
                  ..._familyMembers.map((m) {
                    final id = m['id'];
                    final mid = id is int ? id : int.tryParse('$id');
                    final name = m['name']?.toString() ?? 'Member';
                    return DropdownMenuItem<int?>(
                      value: mid,
                      child: Text(name),
                    );
                  }),
                ],
                onChanged: (v) => setState(() => _selectedFamilyMemberId = v),
              ),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('manual_rx_continue_review'),
              onPressed: _continueToReview,
              child: const Text('Review'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMedicineCard(int index, ColorScheme cs) {
    final row = _rows[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'Medicine ${index + 1}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const Spacer(),
                  if (_rows.length > 1)
                    IconButton(
                      tooltip: 'Remove',
                      onPressed: () => _removeRow(index),
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
              TextFormField(
                key: Key('manual_rx_medicine_name_$index'),
                controller: row.nameController,
                decoration: InputDecoration(
                  labelText: 'Medicine name',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    key: Key('manual_rx_catalogue_pick_$index'),
                    tooltip: 'Search catalogue',
                    onPressed: () => _pickFromCatalogue(index),
                    icon: const Icon(Icons.search),
                  ),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
                onChanged: (_) {
                  if (row.catalogMedicineId != null &&
                      row.nameController.text.trim().isEmpty) {
                    _clearCatalogueMatch(index);
                  }
                },
              ),
              if (row.catalogMedicineId != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Catalogue match #${row.catalogMedicineId}'
                  '${row.artgNumber != null ? ' · ARTG ${row.artgNumber}' : ''}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.primary,
                      ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => _clearCatalogueMatch(index),
                    child: const Text('Clear catalogue match'),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              TextFormField(
                key: Key('manual_rx_dosage_$index'),
                controller: row.dosageController,
                decoration: const InputDecoration(
                  labelText: 'Dosage / strength',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: Key('manual_rx_frequency_$index'),
                controller: row.frequencyController,
                decoration: const InputDecoration(
                  labelText: 'Frequency / instructions',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: row.instructionsController,
                decoration: const InputDecoration(
                  labelText: 'Extra notes (optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MedicineCataloguePicker extends StatefulWidget {
  const _MedicineCataloguePicker();

  @override
  State<_MedicineCataloguePicker> createState() =>
      _MedicineCataloguePickerState();
}

class _MedicineCataloguePickerState extends State<_MedicineCataloguePicker> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  List<Map<String, dynamic>> _results = [];
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _search(q.trim());
    });
  }

  Future<void> _search(String q) async {
    if (q.length < 2) {
      setState(() {
        _results = [];
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await MedicineApi.search(q, limit: 15);
      final raw = data['results'] ?? data['medicines'] ?? data['items'];
      final list = raw is List
          ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _results = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Search failed';
        _results = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Text(
              'Catalogue search',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                key: const Key('manual_rx_catalogue_search'),
                controller: _ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Search medicines',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: _onQuery,
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_error!),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (ctx, i) {
                  final m = _results[i];
                  final name = m['trade_name']?.toString() ??
                      m['name']?.toString() ??
                      'Medicine';
                  final sub = [
                    if (m['strength'] != null) m['strength'].toString(),
                    if (m['generic_name'] != null) m['generic_name'].toString(),
                  ].where((s) => s.isNotEmpty).join(' · ');
                  return ListTile(
                    title: Text(name),
                    subtitle: sub.isEmpty ? null : Text(sub),
                    onTap: () => Navigator.pop(ctx, m),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
