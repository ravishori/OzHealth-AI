import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vitapulse_ai/features/prescriptions/data/prescription_api.dart';
import 'package:vitapulse_ai/shared/widgets/clinical_safety_banner.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';

/// HN-RX-003 — review manually entered medicines before save.
class PrescriptionManualReviewScreen extends StatefulWidget {
  const PrescriptionManualReviewScreen({
    super.key,
    required this.medicines,
    this.doctorName,
    this.familyMemberId,
  });

  final List<Map<String, dynamic>> medicines;
  final String? doctorName;
  final int? familyMemberId;

  @override
  State<PrescriptionManualReviewScreen> createState() =>
      _PrescriptionManualReviewScreenState();
}

class _PrescriptionManualReviewScreenState
    extends State<PrescriptionManualReviewScreen> {
  late List<Map<String, dynamic>> _medicines;
  late final TextEditingController _doctorCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _medicines = widget.medicines
        .map((m) => Map<String, dynamic>.from(m))
        .toList(growable: true);
    _doctorCtrl = TextEditingController(text: widget.doctorName ?? '');
  }

  @override
  void dispose() {
    _doctorCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final payload = _medicines
        .map((m) {
          final name = (m['name']?.toString() ?? '').trim();
          return {
            'name': name,
            if ((m['dosage']?.toString() ?? '').trim().isNotEmpty)
              'dosage': m['dosage'].toString().trim(),
            if ((m['frequency']?.toString() ?? '').trim().isNotEmpty)
              'frequency': m['frequency'].toString().trim(),
            if ((m['instructions']?.toString() ?? '').trim().isNotEmpty)
              'instructions': m['instructions'].toString().trim(),
            if (m['catalog_medicine_id'] != null)
              'catalog_medicine_id': m['catalog_medicine_id'],
            if (m['artg_number'] != null) 'artg_number': m['artg_number'],
            'match_status': m['match_status'] ??
                (m['catalog_medicine_id'] != null ? 'MATCHED' : 'UNMATCHED'),
          };
        })
        .where((m) => (m['name'] as String).isNotEmpty)
        .toList();

    if (payload.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one medicine before saving.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final data = await PrescriptionApi.createManualPrescription(
        medicines: payload,
        doctorName: _doctorCtrl.text.trim().isEmpty
            ? null
            : _doctorCtrl.text.trim(),
        familyMemberId: widget.familyMemberId,
      );
      final id = data['id'] as int?;
      if (!mounted) return;
      if (id != null) {
        context.go('/home/prescriptions/$id');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved, but no prescription id returned.'),
          ),
        );
        context.pop();
      }
    } on DioException catch (e) {
      if (mounted) {
        final msg = e.response?.data?['detail']?.toString() ??
            'Could not save prescription.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unexpected error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);

    return Scaffold(
      key: const Key('prescription_manual_review_screen'),
      appBar: AppBar(
        title: const Text('Review & confirm'),
        actions: [
          TextButton(
            key: const Key('manual_rx_review_cancel'),
            onPressed: _saving ? null : () => context.pop(),
            child: const Text('Edit'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          const ClinicalSafetyBanner(
            kind: ClinicalDisclaimerKind.prescriptionManual,
          ),
          const SizedBox(height: 16),
          Text(
            'Confirm before saving',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: hc.prescription,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Check each medicine. Saving stores what you entered — '
            'it does not verify the prescription or doctor.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          ...List.generate(_medicines.length, (i) {
            final m = _medicines[i];
            final name = m['name']?.toString() ?? '';
            final dosage = m['dosage']?.toString() ?? '';
            final freq = m['frequency']?.toString() ?? '';
            final match = m['match_status']?.toString() ?? 'UNMATCHED';
            return ListTile(
              key: Key('manual_rx_review_med_$i'),
              contentPadding: EdgeInsets.zero,
              title: Text(name.isEmpty ? '(unnamed)' : name),
              subtitle: Text(
                [
                  if (dosage.isNotEmpty) dosage,
                  if (freq.isNotEmpty) freq,
                  match,
                  if (m['catalog_medicine_id'] != null)
                    'catalogue #${m['catalog_medicine_id']}',
                ].join(' · '),
              ),
            );
          }),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('manual_rx_review_doctor_name'),
            controller: _doctorCtrl,
            decoration: const InputDecoration(
              labelText: 'Doctor name (optional)',
              border: OutlineInputBorder(),
              helperText: 'User-supplied — not verified',
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('manual_rx_confirm_save'),
            onPressed: _saving ? null : _confirm,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Confirm & save'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('manual_rx_discard'),
            onPressed: _saving
                ? null
                : () {
                    // Cancel without saving — pop back to home prescriptions path.
                    context.go('/home');
                  },
            child: const Text('Cancel without saving'),
          ),
        ],
      ),
    );
  }
}
