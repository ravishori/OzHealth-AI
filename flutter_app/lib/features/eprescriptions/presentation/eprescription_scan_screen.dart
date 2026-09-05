import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:vitapulse_ai/core/utils/error_handler.dart';
import 'package:vitapulse_ai/features/eprescriptions/data/eprescription_api.dart';
import 'package:vitapulse_ai/shared/widgets/app_error_banner.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';

/// ePrescription scan screen — three input methods:
///   Tab 1 📷  Live QR camera scan   (MobileScanner)
///   Tab 2 🖼  Upload image           (image_picker → backend QR decode)
///   Tab 3 ⌨️  Manual token entry     (TextField)
class EPrescriptionScanScreen extends StatefulWidget {
  const EPrescriptionScanScreen({super.key});

  @override
  State<EPrescriptionScanScreen> createState() =>
      _EPrescriptionScanScreenState();
}

class _EPrescriptionScanScreenState extends State<EPrescriptionScanScreen>
    with SingleTickerProviderStateMixin {
  late final TabController           _tabs;
  late final MobileScannerController _scanner;

  bool    _scanned = false;
  bool    _loading = false;
  String  _loadMsg = '';
  String? _error;

  final _tokenCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs    = TabController(length: 3, vsync: this);
    _scanner = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
    _tabs.addListener(() {
      if (_tabs.indexIsChanging) {
        setState(() { _scanned = false; _error = null; });
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _scanner.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _validate(String rawToken) async {
    if (_loading) return;
    final token = rawToken.trim();
    if (token.isEmpty) return;

    setState(() {
      _loading = true;
      _loadMsg = 'Validating with eRx Script Exchange…';
      _error   = null;
    });

    try {
      final result = await EPrescriptionApi.validateToken(token: token);
      if (!mounted) return;
      final id = result['id'] as int;
      context.go('/home/eprescriptions/$id');
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _scanned = false;
          _error   = ErrorHandler.getMessage(e);
        });
      }
    }
  }

  void _onBarcode(BarcodeCapture capture) {
    if (_scanned || _loading) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;
    setState(() => _scanned = true);
    _validate(raw);
  }

  Future<void> _pickAndExtract() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source:       ImageSource.gallery,
      imageQuality: 90,
      maxWidth:     2048,
      maxHeight:    2048,
    );
    if (picked == null || !mounted) return;

    setState(() {
      _loading = true;
      _loadMsg = 'Reading QR code from image…';
      _error   = null;
    });

    try {
      final extracted = await EPrescriptionApi.extractTokenFromImage(
        File(picked.path),
      );
      if (!mounted) return;
      final token = extracted['token'] as String? ?? '';
      if (token.isEmpty) {
        setState(() {
          _loading = false;
          _error   = 'No QR code found in the selected image.';
        });
        return;
      }
      setState(() { _loadMsg = 'Validating…'; });
      await _validate(token);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error   = ErrorHandler.getMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
        title: const Text('Scan ePrescription'),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.qr_code_scanner), text: 'Scan QR'),
            Tab(icon: Icon(Icons.image_search),    text: 'Upload'),
            Tab(icon: Icon(Icons.keyboard),        text: 'Enter Token'),
          ],
        ),
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tabs,
            physics: _loading
                ? const NeverScrollableScrollPhysics()
                : const AlwaysScrollableScrollPhysics(),
            children: [
              _CameraTab(
                scanner:  _scanner,
                onDetect: _onBarcode,
                error:    _error,
              ),
              _UploadTab(
                onPick: _pickAndExtract,
                error:  _error,
              ),
              _ManualTab(
                controller: _tokenCtrl,
                onSubmit:   () => _validate(_tokenCtrl.text),
                error:      _error,
              ),
            ],
          ),
          if (_loading) _LoadingOverlay(message: _loadMsg),
        ],
      ),
    );
  }
}

// ─── Camera tab ──────────────────────────────────────────────────────────────

class _CameraTab extends StatelessWidget {
  final MobileScannerController scanner;
  final void Function(BarcodeCapture) onDetect;
  final String? error;

  const _CameraTab({
    required this.scanner,
    required this.onDetect,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              MobileScanner(
                controller: scanner,
                onDetect:   onDetect,
              ),
              Center(
                child: Container(
                  width:  240,
                  height: 240,
                  decoration: BoxDecoration(
                    border: Border.all(color: cs.primary, width: 3),
                    borderRadius: AppRadius.brLg,
                  ),
                ),
              ),
              Positioned(
                bottom: 24,
                left: 0, right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      borderRadius: AppRadius.brFull,
                    ),
                    child: const Text(
                      'Point camera at ePrescription QR code',
                      style:
                          TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (error != null) AppErrorBanner(message: error!),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ─── Upload tab ───────────────────────────────────────────────────────────────

class _UploadTab extends StatelessWidget {
  final VoidCallback onPick;
  final String? error;

  const _UploadTab({required this.onPick, required this.error});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.08),
              borderRadius: AppRadius.brFull,
              border: Border.all(
                  color: cs.primary.withValues(alpha: 0.2), width: 2),
            ),
            child: Column(
              children: [
                Icon(Icons.qr_code_2, size: 72, color: cs.primary),
                const SizedBox(height: 16),
                Text(
                  'Upload an image containing\nthe ePrescription QR code',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 15, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 14),
                  ),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Choose Image',
                      style: TextStyle(fontSize: 15)),
                  onPressed: onPick,
                ),
              ],
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            AppErrorBanner(message: error!),
          ],
        ],
      ),
    );
  }
}

// ─── Manual tab ───────────────────────────────────────────────────────────────

class _ManualTab extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSubmit;
  final String? error;

  const _ManualTab({
    required this.controller,
    required this.onSubmit,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          const Text(
            'Enter Token Manually',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Enter the alphanumeric token from your ePrescription document.',
            style: TextStyle(
                color: cs.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 20),
          TextField(
            controller:         controller,
            autocorrect:        false,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText:  'ePrescription Token',
              hintText:   'e.g. ABC123DEF456GHI789',
              prefixIcon: const Icon(Icons.qr_code),
              border: const OutlineInputBorder(
                  borderRadius: AppRadius.brMd),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () => controller.clear(),
              ),
            ),
            onSubmitted: (_) => onSubmit(),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 14),
            ),
            icon:  const Icon(Icons.check_circle_outline),
            label: const Text('Validate Token',
                style: TextStyle(fontSize: 15)),
            onPressed: onSubmit,
          ),
          if (error != null) ...[
            const SizedBox(height: 16),
            AppErrorBanner(message: error!),
          ],
        ],
      ),
    );
  }
}

class _LoadingOverlay extends StatelessWidget {
  final String message;
  const _LoadingOverlay({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: AppRadius.brLg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
