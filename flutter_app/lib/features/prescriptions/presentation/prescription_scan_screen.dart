import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';

enum _ScanState { idle, extracting, analysing, done }

class PrescriptionScanScreen extends StatefulWidget {
  const PrescriptionScanScreen({super.key});

  @override
  State<PrescriptionScanScreen> createState() =>
      _PrescriptionScanScreenState();
}

class _PrescriptionScanScreenState extends State<PrescriptionScanScreen> {
  File? _pickedFile;
  _ScanState _scanState = _ScanState.idle;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 2000,
        maxHeight: 2000,
      );
      if (picked != null) {
        setState(() {
          _pickedFile = File(picked.path);
          _scanState = _ScanState.idle;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not pick image: $e')),
        );
      }
    }
  }

  Future<void> _scanPrescription() async {
    final file = _pickedFile;
    if (file == null) return;

    setState(() => _scanState = _ScanState.extracting);

    await Future.delayed(const Duration(milliseconds: 900));

    if (!mounted) return;
    setState(() => _scanState = _ScanState.analysing);

    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          file.path,
          filename: file.path.split(Platform.pathSeparator).last,
        ),
      });

      // Extract + catalogue match only — does NOT auto-save.
      final response =
          await ApiClient.uploadFile('/prescriptions/ocr', formData);

      final data = Map<String, dynamic>.from(response.data as Map);

      if (!mounted) return;
      setState(() => _scanState = _ScanState.done);
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      context.push(
        '/home/prescriptions/review',
        extra: {
          'filePath': file.path,
          'ocrResult': data,
        },
      );
      setState(() => _scanState = _ScanState.idle);
    } on DioException catch (e) {
      if (mounted) {
        final msg = e.response?.data?['detail']?.toString() ??
            'Failed to scan prescription. Please try again.';
        setState(() => _scanState = _ScanState.idle);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _scanState = _ScanState.idle);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unexpected error: $e')),
        );
      }
    }
  }

  bool get _isProcessing =>
      _scanState == _ScanState.extracting ||
      _scanState == _ScanState.analysing;

  String get _processingLabel {
    switch (_scanState) {
      case _ScanState.extracting:
        return 'Extracting text...';
      case _ScanState.analysing:
        return 'Matching medicines…';
      case _ScanState.done:
        return 'Ready for review';
      default:
        return '';
    }
  }

  Widget _buildSourceButtons() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      children: [
        const SizedBox(height: 32),
        Icon(Icons.document_scanner_outlined, size: 72, color: cs.primary),
        const SizedBox(height: 16),
        Text(
          'Scan Your Prescription',
          style: tt.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Take a photo or choose from gallery to extract medication details with AI.',
          textAlign: TextAlign.center,
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 40),
        Row(
          children: [
            Expanded(
              child: _SourceCard(
                icon: Icons.camera_alt_outlined,
                label: 'Camera',
                onTap: _isProcessing
                    ? null
                    : () => _pickImage(ImageSource.camera),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _SourceCard(
                icon: Icons.photo_library_outlined,
                label: 'Gallery',
                onTap: _isProcessing
                    ? null
                    : () => _pickImage(ImageSource.gallery),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildImagePreview() {
    return Column(
      children: [
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: AppRadius.brLg,
          child: Image.file(
            _pickedFile!,
            width: double.infinity,
            height: 300,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(height: 16),
        if (!_isProcessing)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() {
                    _pickedFile = null;
                    _scanState = _ScanState.idle;
                  }),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Choose Again'),
                ),
              ),
            ],
          ),
        const SizedBox(height: 12),
        _buildScanButton(),
      ],
    );
  }

  Widget _buildScanButton() {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);

    if (_isProcessing) {
      return Column(
        children: [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              _processingLabel,
              key: ValueKey(_processingLabel),
              style: TextStyle(
                fontSize: 15,
                color: cs.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    }

    if (_scanState == _ScanState.done) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, color: hc.vitaGood, size: 28),
          const SizedBox(width: 8),
          Text(
            'Analysis complete!',
            style: TextStyle(
              color: hc.vitaGood,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    return FilledButton.icon(
      onPressed: _scanPrescription,
      icon: const Icon(Icons.search),
      label: const Text('Scan & Analyse'),
      style: FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 52),
      ),
    );
  }

  Widget _buildTipsCard() {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.25),
        borderRadius: AppRadius.brMd,
        border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, size: 18, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                'Tips for best results',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: cs.primary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const _TipItem(text: 'Ensure the prescription is flat and fully visible'),
          const _TipItem(text: 'Good lighting helps text extraction accuracy'),
          const _TipItem(text: 'Keep the camera steady to avoid blur'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Prescription'),
        centerTitle: true,
        leading: BackButton(
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_pickedFile == null) _buildSourceButtons(),
            if (_pickedFile != null) _buildImagePreview(),
            const SizedBox(height: 24),
            _buildTipsCard(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ── Source selection card ─────────────────────────────────────────────────────

class _SourceCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _SourceCard({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AnimatedOpacity(
      opacity: onTap == null ? 0.5 : 1.0,
      duration: const Duration(milliseconds: 150),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: AppRadius.brLg,
          border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: AppRadius.brLg,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: 0.40),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: cs.primary, size: 32),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Tip bullet item ───────────────────────────────────────────────────────────

class _TipItem extends StatelessWidget {
  final String text;

  const _TipItem({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: TextStyle(color: cs.primary, fontSize: 13)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
