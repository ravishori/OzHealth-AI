import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/features/prescriptions/data/ocr_confidence.dart';
import 'package:vitapulse_ai/shared/widgets/clinical_safety_banner.dart';

/// Review OCR + catalogue matches before saving a prescription.
class PrescriptionReviewScreen extends StatefulWidget {
  const PrescriptionReviewScreen({
    super.key,
    required this.filePath,
    required this.ocrResult,
  });

  final String filePath;
  final Map<String, dynamic> ocrResult;

  @override
  State<PrescriptionReviewScreen> createState() =>
      _PrescriptionReviewScreenState();
}

class _EditableMedicine {
  _EditableMedicine({
    required this.nameController,
    required this.dosageController,
    required this.frequencyController,
    this.catalogMedicineId,
    this.artgNumber,
    this.matchStatus = 'UNMATCHED',
    this.candidates = const [],
    this.needsReview = true,
  });

  final TextEditingController nameController;
  final TextEditingController dosageController;
  final TextEditingController frequencyController;
  int? catalogMedicineId;
  String? artgNumber;
  String matchStatus;
  List<Map<String, dynamic>> candidates;
  bool needsReview;

  void dispose() {
    nameController.dispose();
    dosageController.dispose();
    frequencyController.dispose();
  }

  Map<String, dynamic> toPayload() => {
        'name': nameController.text.trim(),
        'dosage': dosageController.text.trim(),
        'frequency': frequencyController.text.trim(),
        if (catalogMedicineId != null) 'catalog_medicine_id': catalogMedicineId,
        if (artgNumber != null) 'artg_number': artgNumber,
        'match_status': matchStatus,
        'user_confirmed': true,
      };
}

class _PrescriptionReviewScreenState extends State<PrescriptionReviewScreen> {
  late final List<_EditableMedicine> _medicines;
  late final TextEditingController _doctorCtrl;
  bool _saving = false;
  double? _ocrConfidence;
  bool _ocrLowConfidence = true;
  bool _ocrAvailable = true;
  bool _ocrNeedsReview = true;

  bool get _anyMedicineNeedsReview =>
      _medicines.any((m) => m.needsReview);

  bool get _requiresReviewAcknowledgement =>
      _ocrNeedsReview || _ocrLowConfidence || !_ocrAvailable || _anyMedicineNeedsReview;

  @override
  void initState() {
    super.initState();
    final ocr = widget.ocrResult['ocr'];
    final summary = widget.ocrResult['summary'];
    if (ocr is Map) {
      _ocrConfidence = OcrConfidence.normalize(ocr['confidence']);
      _ocrAvailable = ocr['available'] != false;
      _ocrLowConfidence = ocr['low_confidence'] == true ||
          OcrConfidence.isLowConfidence(_ocrConfidence);
      _ocrNeedsReview = ocr['needs_review'] == true ||
          _ocrLowConfidence ||
          !_ocrAvailable;
    } else {
      _ocrAvailable = false;
      _ocrLowConfidence = true;
      _ocrNeedsReview = true;
    }
    if (summary is Map) {
      if (summary['ocr_available'] == false) {
        _ocrAvailable = false;
        _ocrNeedsReview = true;
      }
      if (summary['needs_review'] == true) {
        _ocrNeedsReview = true;
      }
    }
    _doctorCtrl = TextEditingController(
      text: widget.ocrResult['doctor_name']?.toString() ?? '',
    );
    final rawMeds = widget.ocrResult['medicines'];
    final list = rawMeds is List ? rawMeds : const [];
    _medicines = list.map((m) {
      final map = Map<String, dynamic>.from(m as Map);
      final candidates = (map['candidates'] is List)
          ? List<Map<String, dynamic>>.from((map['candidates'] as List)
              .map((c) => Map<String, dynamic>.from(c as Map)))
          : <Map<String, dynamic>>[];
      final top = candidates.isNotEmpty ? candidates.first : null;
      final extractedName =
          map['extracted_name']?.toString() ?? map['name']?.toString() ?? '';
      final matchStatus = map['match_status']?.toString() ??
          (top != null ? 'MATCHED' : 'UNMATCHED');
      final unmatched = matchStatus != 'MATCHED';
      return _EditableMedicine(
        nameController: TextEditingController(
          text: top?['trade_name']?.toString() ??
              top?['name']?.toString() ??
              extractedName,
        ),
        dosageController: TextEditingController(
          text: map['extracted_strength']?.toString() ??
              map['dosage']?.toString() ??
              '',
        ),
        frequencyController: TextEditingController(
          text: map['extracted_frequency']?.toString() ??
              map['frequency']?.toString() ??
              '',
        ),
        catalogMedicineId: top?['id'] as int? ?? top?['medicine_id'] as int?,
        artgNumber: top?['ARTG']?.toString() ?? top?['artg_number']?.toString(),
        matchStatus: matchStatus,
        candidates: candidates,
        // Low OCR confidence or unmatched catalogue → needs review.
        needsReview: unmatched || _ocrLowConfidence || !_ocrAvailable,
      );
    }).toList();
  }

  @override
  void dispose() {
    for (final m in _medicines) {
      m.dispose();
    }
    _doctorCtrl.dispose();
    super.dispose();
  }

  Future<bool> _acknowledgeUncertainty() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Review required'),
        content: const Text(
          'OCR confidence is low, OCR was unavailable, or one or more '
          'medicines still need review. Please verify each medicine name, '
          'dose, and frequency carefully.\n\n'
          'Do not save if you are unsure — discard and try a clearer image, '
          'or ask your pharmacist or GP.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Go back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('I have reviewed — save'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _confirm() async {
    if (!_ocrAvailable && _medicines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'OCR was unavailable and no medicines were extracted. '
            'Nothing to save.',
          ),
        ),
      );
      return;
    }

    final payload = _medicines
        .map((m) => m.toPayload())
        .where((m) => (m['name'] as String).isNotEmpty)
        .toList();
    if (payload.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Add at least one medicine name before saving.')),
      );
      return;
    }

    if (_requiresReviewAcknowledgement) {
      final ok = await _acknowledgeUncertainty();
      if (!ok) return;
    }

    setState(() => _saving = true);
    try {
      final form = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          widget.filePath,
          filename: widget.filePath.split(Platform.pathSeparator).last,
        ),
        'medicines_json': jsonEncode(payload),
        if (_doctorCtrl.text.trim().isNotEmpty)
          'doctor_name': _doctorCtrl.text.trim(),
        'raw_ocr_text': widget.ocrResult['ocr'] is Map
            ? (widget.ocrResult['ocr']['text']?.toString() ?? '')
            : '',
      });
      final resp = await ApiClient.uploadFile('/prescriptions/confirm', form);
      final data = resp.data as Map<String, dynamic>;
      final id = data['id'] as int?;
      if (!mounted) return;
      if (id != null) {
        context.go('/home/prescriptions/$id');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Saved, but no prescription id returned.')),
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

  void _applyCandidate(_EditableMedicine med, Map<String, dynamic> c) {
    setState(() {
      med.nameController.text = c['trade_name']?.toString() ??
          c['name']?.toString() ??
          med.nameController.text;
      med.catalogMedicineId = c['id'] as int? ?? c['medicine_id'] as int?;
      med.artgNumber = c['ARTG']?.toString() ?? c['artg_number']?.toString();
      med.matchStatus = 'MATCHED';
      // Catalogue match clears unmatched flag; OCR low-confidence still
      // requires global acknowledgement before save.
      med.needsReview = _ocrLowConfidence || !_ocrAvailable;
    });
  }

  void _keepOcrOnly(_EditableMedicine med) {
    setState(() {
      med.catalogMedicineId = null;
      med.artgNumber = null;
      med.matchStatus = 'UNMATCHED';
      med.needsReview = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final confLabel = OcrConfidence.formatPercent(_ocrConfidence);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review prescription'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _saving ? null : () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const ClinicalSafetyBanner(
            kind: ClinicalDisclaimerKind.prescriptionOcr,
            rounded: true,
            padding: EdgeInsets.all(12),
          ),
          if (!_ocrAvailable) ...[
            const SizedBox(height: 8),
            Material(
              color: cs.errorContainer,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'OCR unavailable — no prescription text was extracted. '
                  'You cannot safely save from this scan.',
                  style: TextStyle(color: cs.onErrorContainer, fontSize: 13),
                ),
              ),
            ),
          ],
          if (_requiresReviewAcknowledgement && _ocrAvailable) ...[
            const SizedBox(height: 8),
            Material(
              color: cs.tertiaryContainer,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _ocrLowConfidence
                      ? 'Low or missing OCR confidence — review required before save.'
                      : 'One or more medicines need review before save.',
                  style: TextStyle(color: cs.onTertiaryContainer, fontSize: 13),
                ),
              ),
            ),
          ],
          if (confLabel != null) ...[
            const SizedBox(height: 8),
            Text(
              'OCR confidence: $confLabel',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _doctorCtrl,
            decoration: const InputDecoration(
              labelText: 'Prescriber / doctor (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text('Medicines', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_medicines.isEmpty)
            const Text(
                'No medicines extracted. You can discard and try another image.'),
          ..._medicines.asMap().entries.map((e) {
            final i = e.key;
            final med = e.value;
            final showNeedsReview = med.needsReview;
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Medicine ${i + 1}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Chip(
                          label: Text(
                            showNeedsReview
                                ? 'Needs review'
                                : (med.matchStatus == 'MATCHED'
                                    ? 'Catalog match'
                                    : 'Needs review'),
                            style: const TextStyle(fontSize: 11),
                          ),
                          backgroundColor: showNeedsReview
                              ? cs.errorContainer
                              : cs.primaryContainer,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: med.nameController,
                      decoration:
                          const InputDecoration(labelText: 'Medicine name'),
                    ),
                    TextField(
                      controller: med.dosageController,
                      decoration: const InputDecoration(
                          labelText: 'Dosage / strength'),
                    ),
                    TextField(
                      controller: med.frequencyController,
                      decoration:
                          const InputDecoration(labelText: 'Frequency'),
                    ),
                    if (med.candidates.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('Catalogue candidates',
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant)),
                      ...med.candidates.take(3).map((c) {
                        final label = c['trade_name']?.toString() ??
                            c['name']?.toString() ??
                            'Candidate';
                        final artg = c['ARTG']?.toString() ??
                            c['artg_number']?.toString();
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title:
                              Text(label, style: const TextStyle(fontSize: 13)),
                          subtitle: artg != null ? Text('ARTG $artg') : null,
                          trailing: TextButton(
                            onPressed: () => _applyCandidate(med, c),
                            child: const Text('Use'),
                          ),
                        );
                      }),
                      TextButton(
                        onPressed: () => _keepOcrOnly(med),
                        child: const Text('Keep OCR text only (unmatched)'),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _saving ? null : _confirm,
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _requiresReviewAcknowledgement
                        ? 'Review & save'
                        : 'Confirm & save',
                  ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _saving ? null : () => context.pop(),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
  }
}
