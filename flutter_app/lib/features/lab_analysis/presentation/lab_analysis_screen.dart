import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vitapulse_ai/core/utils/error_handler.dart';
import 'package:vitapulse_ai/features/lab_analysis/data/lab_analysis_api.dart';
import 'package:vitapulse_ai/features/legal/legal_copy.dart';
import 'package:vitapulse_ai/shared/widgets/clinical_safety_banner.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';

typedef LabAnalyzeFn = Future<Map<String, dynamic>> Function(File file);
typedef LabConfirmFn = Future<Map<String, dynamic>> Function(int recordId);
typedef LabRejectFn = Future<Map<String, dynamic>> Function(int recordId);
typedef LabPickImageFn = Future<XFile?> Function(ImageSource source);

/// HN-FUTURE-002 — Lab report extraction with mandatory review / confirm gate.
///
/// ANALYZED ≠ VERIFIED. AI/OCR extraction is shown as review-required until
/// the user confirms they checked it against the original report.
class LabAnalysisScreen extends StatefulWidget {
  const LabAnalysisScreen({
    super.key,
    this.analyzeFile,
    this.confirmAnalysis,
    this.rejectAnalysis,
    this.pickImage,
    this.initialFile,
  });

  final LabAnalyzeFn? analyzeFile;
  final LabConfirmFn? confirmAnalysis;
  final LabRejectFn? rejectAnalysis;
  final LabPickImageFn? pickImage;

  /// Test-only: preselect a synthetic file without opening the picker.
  final File? initialFile;

  @override
  State<LabAnalysisScreen> createState() => _LabAnalysisScreenState();
}

class _LabAnalysisScreenState extends State<LabAnalysisScreen> {
  File? _selectedFile;
  Map<String, dynamic>? _payload;
  Map<String, dynamic>? _analysis;
  int? _recordId;
  bool _loading = false;
  bool _confirming = false;
  bool _userConfirmed = false;
  String? _error;

  static const _refNotProvided = 'Reference range not provided';

  @override
  void initState() {
    super.initState();
    _selectedFile = widget.initialFile;
  }

  Future<void> _pickFile(ImageSource source) async {
    if (_loading || _confirming) return;
    final picker = ImagePicker();
    final pick = widget.pickImage ??
        ((src) => picker.pickImage(source: src, imageQuality: 90));
    final picked = await pick(source);
    if (picked != null) {
      setState(() {
        _selectedFile = File(picked.path);
        _payload = null;
        _analysis = null;
        _recordId = null;
        _userConfirmed = false;
        _error = null;
      });
    }
  }

  Future<void> _analyze() async {
    if (_loading || _confirming) return;
    if (_selectedFile == null) {
      setState(() => _error = 'Please select a lab report image first');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _payload = null;
      _analysis = null;
      _recordId = null;
      _userConfirmed = false;
    });
    try {
      final analyze = widget.analyzeFile ?? LabAnalysisApi.analyzeFile;
      final result = await analyze(_selectedFile!);
      if (!mounted) return;
      final analysis = result['analysis'];
      setState(() {
        _payload = result;
        _analysis =
            analysis is Map ? Map<String, dynamic>.from(analysis) : null;
        _recordId = result['record_id'] as int?;
        _userConfirmed = result['user_confirmed'] == true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorHandler.getMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirm() async {
    if (_confirming || _loading || _recordId == null || _userConfirmed) return;
    setState(() {
      _confirming = true;
      _error = null;
    });
    try {
      final confirm = widget.confirmAnalysis ?? LabAnalysisApi.confirm;
      final result = await confirm(_recordId!);
      if (!mounted) return;
      final analysis = result['analysis'];
      setState(() {
        _payload = result;
        _analysis =
            analysis is Map ? Map<String, dynamic>.from(analysis) : _analysis;
        _userConfirmed = result['user_confirmed'] == true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorHandler.getMessage(e));
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  Future<void> _reject() async {
    if (_confirming || _loading) return;
    final id = _recordId;
    setState(() {
      _payload = null;
      _analysis = null;
      _recordId = null;
      _userConfirmed = false;
      _error = null;
    });
    if (id == null) return;
    try {
      final reject = widget.rejectAnalysis ?? LabAnalysisApi.reject;
      await reject(id);
    } catch (_) {
      // Local discard already applied; backend reject is best-effort.
    }
  }

  Color _statusColor(String? status, HealthcareColors hc, ColorScheme cs) {
    switch (status?.toLowerCase()) {
      case 'high':
      case 'abnormal':
        return hc.vitaWarning;
      case 'low':
        return cs.secondary;
      case 'critical':
        return hc.vitaCritical;
      case 'normal':
        return hc.vitaGood;
      default:
        return cs.onSurfaceVariant;
    }
  }

  String _refRange(Map<String, dynamic> result) {
    final original = result['original_reference_range'];
    if (original != null && original.toString().trim().isNotEmpty) {
      return original.toString();
    }
    final ref = result['reference_range']?.toString().trim();
    if (ref == null ||
        ref.isEmpty ||
        ref == '-' ||
        ref.toLowerCase() == 'n/a') {
      return _refNotProvided;
    }
    return ref;
  }

  String _displayValue(Map<String, dynamic> result) {
    final original = result['original_value'] ?? result['value'];
    if (original == null || original.toString().trim().isEmpty) {
      return '—';
    }
    final unit = result['original_unit'] ?? result['unit'];
    final unitStr =
        (unit != null && unit.toString().trim().isNotEmpty) ? ' $unit' : '';
    return '${original.toString()}$unitStr';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);
    return Scaffold(
      key: const Key('lab_analysis_screen'),
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Lab Report Review'),
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ClinicalSafetyBanner(
              key: Key('lab_safety_banner'),
              kind: ClinicalDisclaimerKind.lab,
              rounded: true,
              padding: EdgeInsets.all(12),
            ),
            const SizedBox(height: 12),
            Container(
              key: const Key('lab_purpose_banner'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.08),
                borderRadius: AppRadius.brMd,
                border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.science, color: cs.primary, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Upload a lab report image. Extracted values are '
                      'informational only — review them against your original '
                      'report before confirming. HealthNest does not diagnose.',
                      style: TextStyle(
                          fontSize: 13, color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            if (_selectedFile != null)
              ClipRRect(
                key: const Key('lab_selected_preview'),
                borderRadius: AppRadius.brMd,
                child: kIsWeb
                    ? Container(
                        height: 160,
                        alignment: Alignment.center,
                        color: cs.surfaceContainerHighest,
                        child: Text(_selectedFile!.path,
                            textAlign: TextAlign.center),
                      )
                    : Image.file(
                        _selectedFile!,
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          height: 160,
                          alignment: Alignment.center,
                          color: cs.surfaceContainerHighest,
                          child: const Text('Selected report ready'),
                        ),
                      ),
              )
            else
              Container(
                key: const Key('lab_empty_preview'),
                height: 160,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: AppRadius.brMd,
                  border: Border.all(color: cs.outline),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.upload_file,
                        size: 40, color: cs.onSurfaceVariant),
                    const SizedBox(height: 8),
                    Text('No file selected',
                        style: TextStyle(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),

            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('lab_camera_button'),
                    onPressed:
                        _loading || _confirming
                            ? null
                            : () => _pickFile(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Camera'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: const RoundedRectangleBorder(
                          borderRadius: AppRadius.brSm),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('lab_gallery_button'),
                    onPressed:
                        _loading || _confirming
                            ? null
                            : () => _pickFile(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: const RoundedRectangleBorder(
                          borderRadius: AppRadius.brSm),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                key: const Key('lab_analyze_button'),
                onPressed: _loading || _confirming ? null : _analyze,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.analytics),
                label: Text(_loading
                    ? 'Extracting report...'
                    : 'Extract Lab Values'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                key: const Key('lab_error_banner'),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: hc.vitaCritical.withValues(alpha: 0.08),
                  borderRadius: AppRadius.brMd,
                  border: Border.all(
                      color: hc.vitaCritical.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_error!,
                        style: TextStyle(
                            color: hc.vitaCritical, fontSize: 13)),
                    const SizedBox(height: 8),
                    TextButton(
                      key: const Key('lab_retry_button'),
                      onPressed: _loading ? null : _analyze,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ],

            if (_analysis != null) ...[
              const SizedBox(height: 24),
              _buildResults(cs, hc),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResults(ColorScheme cs, HealthcareColors hc) {
    final results = (_analysis!['results'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        [];
    final abnormalCount = _analysis!['abnormal_count'] as int? ?? 0;
    final summary = _analysis!['summary'] as String?;
    final recommendations =
        (_analysis!['recommendations'] as List?)?.cast<String>() ?? [];
    final lowConfidence = _analysis!['ocr_low_confidence'] == true ||
        (_analysis!['ocr'] is Map &&
            (_analysis!['ocr'] as Map)['low_confidence'] == true);
    final reviewRequired =
        !_userConfirmed && (_payload?['review_required'] != false);

    return Column(
      key: const Key('lab_results_section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (reviewRequired)
          Container(
            key: const Key('lab_review_gate'),
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: hc.vitaWarning.withValues(alpha: 0.1),
              borderRadius: AppRadius.brLg,
              border: Border.all(
                  color: hc.vitaWarning.withValues(alpha: 0.45)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.fact_check, color: hc.vitaWarning, size: 22),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Review required',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                const Text(
                  'Please review the extracted information against your '
                  'original report. Extracted values are not clinician '
                  'verified and are not a diagnosis.',
                  style: TextStyle(fontSize: 13),
                ),
                if (lowConfidence) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Extraction confidence is low or uncertain — check every value carefully.',
                    style: TextStyle(
                        fontSize: 12,
                        color: hc.vitaWarning,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ],
            ),
          )
        else
          Container(
            key: const Key('lab_confirmed_banner'),
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.08),
              borderRadius: AppRadius.brLg,
              border:
                  Border.all(color: cs.primary.withValues(alpha: 0.3)),
            ),
            child: const Text(
              'You confirmed this extraction against your original report. '
              'This is still not clinician verification or a diagnosis.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        const SizedBox(height: 16),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: AppRadius.brLg,
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                abnormalCount > 0
                    ? '$abnormalCount value(s) flagged on the report — needs review'
                    : 'Extracted results — informational only',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15),
              ),
              if (_analysis!['test_name'] != null) ...[
                const SizedBox(height: 6),
                Text('Panel: ${_analysis!['test_name']}',
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurfaceVariant)),
              ],
              if (_analysis!['test_date'] != null) ...[
                Text('Report date: ${_analysis!['test_date']}',
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurfaceVariant)),
              ],
              if (summary != null) ...[
                const SizedBox(height: 8),
                Text(summary, style: const TextStyle(fontSize: 13)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (results.isNotEmpty) ...[
          const Text('Extracted results',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          ...results.map((r) => _ParameterCard(
                result: r,
                statusColor: _statusColor(r['status'] as String?, hc, cs),
                displayValue: _displayValue(r),
                referenceRange: _refRange(r),
              )),
          const SizedBox(height: 12),
        ],

        if (recommendations.isNotEmpty) ...[
          const Text('When to seek care',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 6),
          ...recommendations.map((rec) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.arrow_right, color: cs.primary, size: 20),
                      const SizedBox(width: 4),
                      Expanded(
                          child: Text(rec,
                              style: const TextStyle(fontSize: 13))),
                    ]),
              )),
          const SizedBox(height: 8),
        ],

        Text(
          _analysis!['disclaimer']?.toString() ?? LegalCopy.labBanner,
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 16),

        if (reviewRequired) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              key: const Key('lab_confirm_button'),
              onPressed: _confirming ? null : _confirm,
              icon: _confirming
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_circle_outline),
              label: Text(_confirming
                  ? 'Confirming...'
                  : 'Confirm extraction'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('lab_reject_button'),
                  onPressed: _confirming ? null : _reject,
                  child: const Text('Reject / retry'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  key: const Key('lab_cancel_button'),
                  onPressed: _confirming
                      ? null
                      : () {
                          if (context.canPop()) {
                            context.pop();
                          }
                        },
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ParameterCard extends StatelessWidget {
  final Map<String, dynamic> result;
  final Color statusColor;
  final String displayValue;
  final String referenceRange;

  const _ParameterCard({
    required this.result,
    required this.statusColor,
    required this.displayValue,
    required this.referenceRange,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);
    final status = (result['status'] ?? 'unknown').toString();
    final missing = (result['missing_fields'] as List?) ?? const [];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.brMd,
        border: Border(
          left: BorderSide(color: statusColor, width: 4),
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04), blurRadius: 4)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
                child: Text(result['parameter'] ?? 'Unnamed test',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13))),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: AppRadius.brFull),
              child: Text(
                'REPORTED: ${status.toUpperCase()}',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: statusColor),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text('Reported result: $displayValue',
              style: const TextStyle(fontSize: 12)),
          Text('Reported reference range: $referenceRange',
              style:
                  TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text('Status: Needs review / informational',
              style: TextStyle(
                  fontSize: 11,
                  color: hc.vitaWarning,
                  fontWeight: FontWeight.w500)),
          if (result['plain_explanation'] != null) ...[
            const SizedBox(height: 4),
            Text(
              'Explanation (educational): ${result['plain_explanation']}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
          if (missing.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Missing fields: ${missing.join(', ')} — verify on original report',
                style: TextStyle(fontSize: 11, color: hc.vitaCritical),
              ),
            ),
          if (result['action_needed'] == true)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  'Discuss this result with your healthcare professional',
                  style: TextStyle(
                      fontSize: 11,
                      color: hc.vitaWarning,
                      fontWeight: FontWeight.w500)),
            ),
        ],
      ),
    );
  }
}
