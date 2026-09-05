import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vitapulse_ai/core/utils/error_handler.dart';
import 'package:vitapulse_ai/features/lab_analysis/data/lab_analysis_api.dart';
import 'package:vitapulse_ai/shared/widgets/clinical_safety_banner.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';

class LabAnalysisScreen extends StatefulWidget {
  const LabAnalysisScreen({super.key});

  @override
  State<LabAnalysisScreen> createState() => _LabAnalysisScreenState();
}

class _LabAnalysisScreenState extends State<LabAnalysisScreen> {
  File? _selectedFile;
  Map<String, dynamic>? _result;
  bool _loading = false;

  Future<void> _pickFile(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 90);
    if (picked != null) {
      setState(() {
        _selectedFile = File(picked.path);
        _result = null;
      });
    }
  }

  Future<void> _analyze() async {
    if (_selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please select a lab report image first')),
      );
      return;
    }
    setState(() {
      _loading = true;
      _result = null;
    });
    try {
      final result = await LabAnalysisApi.analyzeFile(_selectedFile!);
      setState(
          () => _result = result['analysis'] as Map<String, dynamic>?);
    } catch (e) {
      if (mounted) ErrorHandler.show(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _statusColor(String? status, HealthcareColors hc, ColorScheme cs) {
    switch (status?.toLowerCase()) {
      case 'high':
        return hc.vitaWarning;
      case 'low':
        return cs.secondary;
      case 'critical':
        return hc.vitaCritical;
      default:
        return hc.vitaGood;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Lab Report Analyser'),
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ClinicalSafetyBanner(
              kind: ClinicalDisclaimerKind.lab,
              rounded: true,
              padding: EdgeInsets.all(12),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.08),
                borderRadius: AppRadius.brMd,
                border:
                    Border.all(color: cs.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.science, color: cs.primary, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Upload your lab report (blood test, urine test, etc.) and AI will explain each value in plain language.',
                      style: TextStyle(
                          fontSize: 13, color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // File selection
            if (_selectedFile != null)
              ClipRRect(
                borderRadius: AppRadius.brMd,
                child: Image.file(_selectedFile!,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover),
              )
            else
              Container(
                height: 160,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: AppRadius.brMd,
                  border: Border.all(
                      color: cs.outline, style: BorderStyle.solid),
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
                    onPressed: () => _pickFile(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Camera'),
                    style: OutlinedButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(vertical: 12),
                      shape: const RoundedRectangleBorder(
                          borderRadius: AppRadius.brSm),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickFile(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                    style: OutlinedButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(vertical: 12),
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
                onPressed: _loading ? null : _analyze,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.analytics),
                label: Text(_loading
                    ? 'Analysing report...'
                    : 'Analyse Lab Report'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),

            if (_result != null) ...[
              const SizedBox(height: 24),
              _buildResults(cs, hc),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResults(ColorScheme cs, HealthcareColors hc) {
    final results = (_result!['results'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    final abnormalCount = _result!['abnormal_count'] as int? ?? 0;
    final summary = _result!['summary'] as String?;
    final recommendations =
        (_result!['recommendations'] as List?)?.cast<String>() ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: abnormalCount > 0
                ? hc.vitaWarning.withValues(alpha: 0.1)
                : hc.vitaGood.withValues(alpha: 0.1),
            borderRadius: AppRadius.brLg,
            border: Border.all(
                color: abnormalCount > 0
                    ? hc.vitaWarning.withValues(alpha: 0.4)
                    : hc.vitaGood.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(
                  abnormalCount > 0
                      ? Icons.warning_amber
                      : Icons.check_circle,
                  color: abnormalCount > 0 ? hc.vitaWarning : hc.vitaGood,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  abnormalCount > 0
                      ? '$abnormalCount Abnormal Value(s) Found'
                      : 'All Values Normal',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: abnormalCount > 0
                        ? hc.vitaWarning
                        : hc.vitaGood,
                  ),
                ),
              ]),
              if (summary != null) ...[
                const SizedBox(height: 8),
                Text(summary, style: const TextStyle(fontSize: 13)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Parameter table
        if (results.isNotEmpty) ...[
          const Text('Test Results',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          ...results.map((r) => _ParameterCard(
              result: r,
              statusColor:
                  _statusColor(r['status'] as String?, hc, cs))),
          const SizedBox(height: 12),
        ],

        // Recommendations
        if (recommendations.isNotEmpty) ...[
          const Text('Follow-up Actions',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 15)),
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
      ],
    );
  }
}

class _ParameterCard extends StatelessWidget {
  final Map<String, dynamic> result;
  final Color statusColor;
  const _ParameterCard({required this.result, required this.statusColor});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);
    final isAbnormal =
        result['status']?.toString().toLowerCase() != 'normal';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.brMd,
        border: isAbnormal
            ? Border(
                left: BorderSide(color: statusColor, width: 4),
              )
            : null,
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
                child: Text(result['parameter'] ?? '',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13))),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: AppRadius.brFull),
              child: Text(
                (result['status'] ?? 'normal').toString().toUpperCase(),
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: statusColor),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
              'Value: ${result['value'] ?? '-'}  |  Reference: ${result['reference_range'] ?? '-'}',
              style:
                  TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          if (result['plain_explanation'] != null) ...[
            const SizedBox(height: 4),
            Text(result['plain_explanation'],
                style: const TextStyle(fontSize: 12)),
          ],
          if (result['action_needed'] == true)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  '⚠️ Action needed — discuss with your doctor',
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
