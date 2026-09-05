import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/shared/widgets/loading_button.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';

class UploadRecordScreen extends StatefulWidget {
  const UploadRecordScreen({super.key});

  @override
  State<UploadRecordScreen> createState() => _UploadRecordScreenState();
}

class _UploadRecordScreenState extends State<UploadRecordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  String? _recordType;
  DateTime? _recordDate;
  File? _selectedFile;
  String? _selectedFileName;
  bool _isImage = false;
  bool _loading = false;

  List<_RecordTypeOption> _buildRecordTypes(
      HealthcareColors hc, ColorScheme cs) {
    return [
      _RecordTypeOption('Prescription', 'prescription',
          Icons.receipt_long_outlined, hc.prescription),
      _RecordTypeOption('Lab Report', 'lab_report', Icons.biotech_outlined,
          hc.labReport),
      _RecordTypeOption('Radiology', 'radiology',
          Icons.image_search_outlined, hc.radiology),
      _RecordTypeOption('Discharge Summary', 'discharge_summary',
          Icons.local_hospital_outlined, hc.discharge),
      _RecordTypeOption('Other', 'other',
          Icons.insert_drive_file_outlined, cs.primary),
    ];
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked != null) {
      setState(() {
        _selectedFile = File(picked.path);
        _selectedFileName = picked.name;
        _isImage = true;
      });
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: false,
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedFile = File(result.files.single.path!);
        _selectedFileName = result.files.single.name;
        _isImage = false;
      });
    }
  }

  Future<void> _showFilePicker() async {
    final cs = Theme.of(context).colorScheme;
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.bottomSheet,
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select File',
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.08),
                    borderRadius: AppRadius.brSm,
                  ),
                  child: Icon(Icons.image_outlined, color: cs.primary),
                ),
                title: const Text('Choose Image'),
                subtitle: const Text('JPG, PNG from gallery'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage();
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.error.withValues(alpha: 0.07),
                    borderRadius: AppRadius.brSm,
                  ),
                  child: Icon(Icons.picture_as_pdf, color: cs.error),
                ),
                title: const Text('Choose PDF'),
                subtitle: const Text('PDF document'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickFile();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _recordDate ?? now,
      firstDate: DateTime(1990),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _recordDate = picked);
    }
  }

  Future<void> _upload() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select a file to upload'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final formData = FormData.fromMap({
        'title': _titleCtrl.text.trim(),
        'record_type': _recordType,
        if (_notesCtrl.text.trim().isNotEmpty)
          'notes': _notesCtrl.text.trim(),
        if (_recordDate != null)
          'record_date': DateFormat('yyyy-MM-dd').format(_recordDate!),
        'file': await MultipartFile.fromFile(
          _selectedFile!.path,
          filename: _selectedFileName,
        ),
      });

      await ApiClient.uploadFile('/records/upload', formData);

      if (mounted) {
        final hc = HealthcareColors.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Record uploaded successfully'),
            backgroundColor: hc.vitaGood,
          ),
        );
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Upload failed. Please try again.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);
    final recordTypes = _buildRecordTypes(hc, cs);

    return Scaffold(
      appBar: AppBar(title: const Text('Upload Record')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Record Type
              _label('Record Type *'),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _recordType,
                decoration: const InputDecoration(
                  hintText: 'Select record type',
                  prefixIcon: Icon(Icons.insert_drive_file_outlined),
                ),
                items: recordTypes
                    .map(
                      (opt) => DropdownMenuItem(
                        value: opt.value,
                        child: Row(
                          children: [
                            Icon(opt.icon, size: 18, color: opt.color),
                            const SizedBox(width: 10),
                            Text(opt.label),
                          ],
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _recordType = v),
                validator: (v) =>
                    v == null ? 'Please select a record type' : null,
              ),
              const SizedBox(height: 16),

              // Title
              _label('Title *'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _titleCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'e.g. Blood Test Results - Jan 2025',
                  prefixIcon: Icon(Icons.title),
                ),
                validator: (v) =>
                    (v?.trim().isEmpty ?? true) ? 'Title is required' : null,
              ),
              const SizedBox(height: 16),

              // Notes
              _label('Notes'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _notesCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Optional notes about this record',
                  alignLabelWithHint: true,
                  prefixIcon: Padding(
                    padding: EdgeInsets.only(bottom: 48),
                    child: Icon(Icons.notes),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Record Date
              _label('Record Date'),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: AppRadius.brMd,
                    border: Border.all(color: cs.outline),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_outlined,
                          size: 20, color: cs.onSurfaceVariant),
                      const SizedBox(width: 12),
                      Text(
                        _recordDate != null
                            ? DateFormat('dd MMM yyyy').format(_recordDate!)
                            : 'Select date (optional)',
                        style: TextStyle(
                          fontSize: 15,
                          color: _recordDate != null
                              ? cs.onSurface
                              : cs.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      if (_recordDate != null)
                        GestureDetector(
                          onTap: () =>
                              setState(() => _recordDate = null),
                          child: Icon(Icons.clear,
                              size: 18, color: cs.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // File Picker Area
              _label('File *'),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: _loading ? null : _showFilePicker,
                child: _selectedFile != null
                    ? _buildFilePreview(cs)
                    : _buildFilePickerPlaceholder(cs),
              ),
              const SizedBox(height: 32),

              // Upload Button
              LoadingButton(
                text: 'Upload Record',
                loading: _loading,
                onPressed: _upload,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilePickerPlaceholder(ColorScheme cs) {
    return Container(
      height: 150,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.08),
        borderRadius: AppRadius.brMd,
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.4),
          style: BorderStyle.solid,
          width: 1.5,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_upload_outlined, size: 40, color: cs.primary),
            const SizedBox(height: 10),
            Text(
              'Tap to select file',
              style: TextStyle(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              'Supports JPG, PNG, PDF',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilePreview(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.brMd,
        border: Border.all(
            color: cs.primary.withValues(alpha: 0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04), blurRadius: 6),
        ],
      ),
      child: Column(
        children: [
          if (_isImage)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadius.md)),
              child: Image.file(
                _selectedFile!,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            )
          else
            Container(
              height: 100,
              decoration: BoxDecoration(
                color: cs.error.withValues(alpha: 0.06),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppRadius.md)),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.picture_as_pdf, size: 44, color: cs.error),
                    const SizedBox(height: 6),
                    Text('PDF Document',
                        style: TextStyle(
                            color: cs.error,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(
                  _isImage
                      ? Icons.image_outlined
                      : Icons.picture_as_pdf,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedFileName ?? '',
                    style: TextStyle(fontSize: 13, color: cs.onSurface),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() {
                    _selectedFile = null;
                    _selectedFileName = null;
                    _isImage = false;
                  }),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Color(0x1AD32F2F),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.close, size: 16, color: cs.error),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      text,
      style: TextStyle(
          fontWeight: FontWeight.w500, fontSize: 13, color: cs.onSurface),
    );
  }
}

class _RecordTypeOption {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _RecordTypeOption(this.label, this.value, this.icon, this.color);
}
