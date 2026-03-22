import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/core/theme/app_theme.dart';

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
          SnackBar(
            content: Text('Could not pick image: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _scanPrescription() async {
    final file = _pickedFile;
    if (file == null) return;

    setState(() => _scanState = _ScanState.extracting);

    // Brief delay so user sees "Extracting text..." phase
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

      final response =
          await ApiClient.uploadFile('/prescriptions/scan', formData);

      final data = response.data as Map<String, dynamic>;
      final prescriptionId = data['id'] as int? ?? data['prescription_id'] as int?;

      if (!mounted) return;

      if (prescriptionId != null) {
        setState(() => _scanState = _ScanState.done);
        await Future.delayed(const Duration(milliseconds: 400));
        if (mounted) {
          context.go('/home/prescriptions/$prescriptionId');
        }
      } else {
        setState(() => _scanState = _ScanState.idle);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Scan completed but no ID returned from server.'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } on DioException catch (e) {
      if (mounted) {
        final msg = e.response?.data?['detail']?.toString() ??
            'Failed to scan prescription. Please try again.';
        setState(() => _scanState = _ScanState.idle);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _scanState = _ScanState.idle);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unexpected error: $e'),
            backgroundColor: AppTheme.error,
          ),
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
        return 'Analysing with AI...';
      case _ScanState.done:
        return 'Done!';
      default:
        return '';
    }
  }

  Widget _buildSourceButtons() {
    return Column(
      children: [
        const SizedBox(height: 32),
        const Icon(Icons.document_scanner_outlined,
            size: 72, color: AppTheme.primary),
        const SizedBox(height: 16),
        const Text(
          'Scan Your Prescription',
          style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 8),
        const Text(
          'Take a photo or choose from gallery to extract medication details with AI.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
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
          borderRadius: BorderRadius.circular(14),
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
    if (_isProcessing) {
      return Column(
        children: [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
                strokeWidth: 3, color: AppTheme.primary),
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              _processingLabel,
              key: ValueKey(_processingLabel),
              style: const TextStyle(
                  fontSize: 15,
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      );
    }

    if (_scanState == _ScanState.done) {
      return const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, color: AppTheme.success, size: 28),
          SizedBox(width: 8),
          Text('Analysis complete!',
              style:
                  TextStyle(color: AppTheme.success, fontWeight: FontWeight.w600)),
        ],
      );
    }

    return ElevatedButton.icon(
      onPressed: _scanPrescription,
      icon: const Icon(Icons.search),
      label: const Text('Scan & Analyse'),
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 52),
      ),
    );
  }

  Widget _buildTipsCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline,
                  size: 18, color: AppTheme.primary),
              SizedBox(width: 6),
              Text('Tips for best results',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primary,
                      fontSize: 13)),
            ],
          ),
          SizedBox(height: 8),
          _TipItem(text: 'Ensure the prescription is flat and fully visible'),
          _TipItem(text: 'Good lighting helps text extraction accuracy'),
          _TipItem(text: 'Keep the camera steady to avoid blur'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: const Text('Scan Prescription',
            style: TextStyle(color: Colors.white)),
        centerTitle: true,
        leading: BackButton(
          color: Colors.white,
          onPressed: () => Navigator.of(context).maybePop(),
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

// ─────────────────────────── Supporting widgets ───────────────────────────

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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: onTap == null ? 0.5 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              )
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppTheme.primary, size: 32),
              ),
              const SizedBox(height: 10),
              Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppTheme.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TipItem extends StatelessWidget {
  final String text;

  const _TipItem({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ',
              style: TextStyle(color: AppTheme.primary, fontSize: 13)),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
