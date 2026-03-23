import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/core/theme/app_theme.dart';
import 'package:vitapulse_ai/shared/widgets/loading_button.dart';

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

  static const _recordTypes = [
    _RecordTypeOption('Prescription', 'prescription',
        Icons.receipt_long_outlined, Color(0xFF1565C0)),
    _RecordTypeOption('Lab Report', 'lab_report', Icons.biotech_outlined,
        Color(0xFF558B2F)),
    _RecordTypeOption(
        'Radiology', 'radiology', Icons.image_search_outlined, Color(0xFF6A1B9A)),
    _RecordTypeOption('Discharge Summary', 'discharge',
        Icons.local_hospital_outlined, Color(0xFFE65100)),
    _RecordTypeOption('Other', 'other', Icons.insert_drive_file_outlined,
        AppTheme.primary),
  ];

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
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select File',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0x1A00897B),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.image_outlined,
                      color: AppTheme.primary),
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
                    color: const Color(0x1AD32F2F),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child:
                      const Icon(Icons.picture_as_pdf, color: AppTheme.error),
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
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppTheme.primary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _recordDate = picked);
    }
  }

  Future<void> _upload() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a file to upload'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final formData = FormData.fromMap({
        'title': _titleCtrl.text.trim(),
        'record_type': _recordType,
        if (_notesCtrl.text.trim().isNotEmpty) 'notes': _notesCtrl.text.trim(),
        if (_recordDate != null)
          'record_date':
              DateFormat('yyyy-MM-dd').format(_recordDate!),
        'file': await MultipartFile.fromFile(
          _selectedFile!.path,
          filename: _selectedFileName,
        ),
      });

      await ApiClient.uploadFile('/records/upload', formData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Record uploaded successfully'),
            backgroundColor: AppTheme.success,
          ),
        );
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Upload failed. Please try again.'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                value: _recordType,
                decoration: const InputDecoration(
                  hintText: 'Select record type',
                  prefixIcon:
                      Icon(Icons.insert_drive_file_outlined),
                ),
                items: _recordTypes
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
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined,
                          size: 20, color: AppTheme.textSecondary),
                      const SizedBox(width: 12),
                      Text(
                        _recordDate != null
                            ? DateFormat('dd MMM yyyy')
                                .format(_recordDate!)
                            : 'Select date (optional)',
                        style: TextStyle(
                          fontSize: 15,
                          color: _recordDate != null
                              ? AppTheme.textPrimary
                              : Colors.grey.shade500,
                        ),
                      ),
                      const Spacer(),
                      if (_recordDate != null)
                        GestureDetector(
                          onTap: () =>
                              setState(() => _recordDate = null),
                          child: const Icon(Icons.clear,
                              size: 18,
                              color: AppTheme.textSecondary),
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
                    ? _buildFilePreview()
                    : _buildFilePickerPlaceholder(),
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

  Widget _buildFilePickerPlaceholder() {
    return Container(
      height: 150,
      decoration: BoxDecoration(
        color: const Color(0x0A00897B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0x6600897B),
          style: BorderStyle.solid,
          width: 1.5,
        ),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_upload_outlined,
                size: 40, color: AppTheme.primary),
            SizedBox(height: 10),
            Text(
              'Tap to select file',
              style: TextStyle(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 15),
            ),
            SizedBox(height: 4),
            Text(
              'Supports JPG, PNG, PDF',
              style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilePreview() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: const Color(0x6600897B), width: 1.5),
        boxShadow: [
          BoxShadow(
              color: const Color(0x0D000000), blurRadius: 6),
        ],
      ),
      child: Column(
        children: [
          if (_isImage)
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(10)),
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
                color: const Color(0x0FD32F2F),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(10)),
              ),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.picture_as_pdf,
                        size: 44, color: AppTheme.error),
                    SizedBox(height: 6),
                    Text('PDF Document',
                        style: TextStyle(
                            color: AppTheme.error,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(
                  _isImage
                      ? Icons.image_outlined
                      : Icons.picture_as_pdf,
                  size: 18,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedFileName ?? '',
                    style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textPrimary),
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
                    decoration: BoxDecoration(
                      color: const Color(0x1AD32F2F),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close,
                        size: 16, color: AppTheme.error),
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
    return Text(
      text,
      style: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 13,
          color: AppTheme.textPrimary),
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
