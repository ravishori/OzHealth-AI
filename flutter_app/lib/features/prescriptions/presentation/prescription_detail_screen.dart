import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/core/theme/app_theme.dart';

class PrescriptionDetailScreen extends StatefulWidget {
  final int prescriptionId;

  const PrescriptionDetailScreen({super.key, required this.prescriptionId});

  @override
  State<PrescriptionDetailScreen> createState() =>
      _PrescriptionDetailScreenState();
}

class _PrescriptionDetailScreenState extends State<PrescriptionDetailScreen> {
  bool _loading = true;
  String? _error;
  _PrescriptionDetail? _detail;

  @override
  void initState() {
    super.initState();
    _fetchDetail();
  }

  Future<void> _fetchDetail() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response =
          await ApiClient.get('/prescriptions/${widget.prescriptionId}');
      setState(() {
        _detail = _PrescriptionDetail.fromJson(
            response.data as Map<String, dynamic>);
        _loading = false;
      });
    } on DioException catch (e) {
      setState(() {
        _error = e.response?.data?['detail']?.toString() ??
            'Failed to load prescription.';
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _error = 'Unexpected error loading prescription.';
        _loading = false;
      });
    }
  }

  void _addToReminders(_PrescriptionMedicine medicine) {
    context.go(
      '/home/reminders/add',
      extra: {
        'medicineName': medicine.name,
        'dosage': medicine.dosage,
        'frequency': medicine.frequency,
      },
    );
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    try {
      final dt = DateTime.parse(raw);
      return DateFormat('dd MMM yyyy').format(dt);
    } catch (_) {
      return raw;
    }
  }

  Widget _buildLoadingShimmer() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(
          4,
          (i) => Container(
            margin: const EdgeInsets.only(bottom: 16),
            height: i == 2 ? 160 : 80,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline,
                size: 56, color: AppTheme.textSecondary),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _fetchDetail,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(_PrescriptionDetail detail) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0x1E1565C0),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.description_outlined,
                      color: AppTheme.secondary, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        detail.doctorName.isNotEmpty
                            ? 'Dr. ${detail.doctorName}'
                            : 'Unknown Doctor',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      if (detail.hospital.isNotEmpty)
                        Text(detail.hospital,
                            style: const TextStyle(
                                color: AppTheme.textSecondary, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.calendar_today_outlined,
                    size: 15, color: AppTheme.textSecondary),
                const SizedBox(width: 6),
                Text(
                  'Date: ${_formatDate(detail.date)}',
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMedicinesTable(_PrescriptionDetail detail) {
    if (detail.medicines.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'No medicines extracted.',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.medication_outlined,
                    color: AppTheme.primary, size: 22),
                SizedBox(width: 8),
                Text('Medicines',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 14),
            ...detail.medicines.map((med) => _MedicineTile(
                  medicine: med,
                  onAddReminder: () => _addToReminders(med),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildAiSummary(_PrescriptionDetail detail) {
    if (detail.aiSummary == null || detail.aiSummary!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0x1E1565C0),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.psychology_outlined,
                      color: AppTheme.secondary, size: 20),
                ),
                const SizedBox(width: 10),
                const Text(
                  'AI Summary',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0x1A1565C0),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Claude AI',
                    style: TextStyle(
                        color: AppTheme.secondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              detail.aiSummary!,
              style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.textPrimary,
                  height: 1.55),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final detail = _detail!;
    return RefreshIndicator(
      onRefresh: _fetchDetail,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(detail),
            const SizedBox(height: 12),
            _buildMedicinesTable(detail),
            const SizedBox(height: 12),
            _buildAiSummary(detail),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: const Text('Prescription',
            style: TextStyle(color: Colors.white)),
        centerTitle: true,
        leading: BackButton(
          color: Colors.white,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: _loading
          ? _buildLoadingShimmer()
          : _error != null
              ? _buildError()
              : _buildBody(),
    );
  }
}

// ─────────────────────────── Data models ───────────────────────────

class _PrescriptionMedicine {
  final String name;
  final String dosage;
  final String frequency;
  final String duration;

  const _PrescriptionMedicine({
    required this.name,
    required this.dosage,
    required this.frequency,
    required this.duration,
  });

  factory _PrescriptionMedicine.fromJson(Map<String, dynamic> json) {
    return _PrescriptionMedicine(
      name: json['name']?.toString() ?? json['medicine_name']?.toString() ?? '',
      dosage: json['dosage']?.toString() ?? '',
      frequency: json['frequency']?.toString() ?? '',
      duration: json['duration']?.toString() ?? '',
    );
  }
}

class _PrescriptionDetail {
  final int id;
  final String doctorName;
  final String hospital;
  final String? date;
  final String? aiSummary;
  final List<_PrescriptionMedicine> medicines;

  const _PrescriptionDetail({
    required this.id,
    required this.doctorName,
    required this.hospital,
    this.date,
    this.aiSummary,
    required this.medicines,
  });

  factory _PrescriptionDetail.fromJson(Map<String, dynamic> json) {
    final rawMeds = json['medicines'] ??
        json['medications'] ??
        json['items'] ??
        <dynamic>[];
    final medicines = (rawMeds as List<dynamic>)
        .map((e) =>
            _PrescriptionMedicine.fromJson(e as Map<String, dynamic>))
        .toList();

    return _PrescriptionDetail(
      id: (json['id'] as num?)?.toInt() ?? 0,
      doctorName: json['doctor_name']?.toString() ??
          json['doctorName']?.toString() ??
          '',
      hospital: json['hospital']?.toString() ??
          json['hospital_name']?.toString() ??
          '',
      date: json['date']?.toString() ?? json['prescription_date']?.toString(),
      aiSummary: json['ai_summary']?.toString() ??
          json['summary']?.toString() ??
          json['aiSummary']?.toString(),
      medicines: medicines,
    );
  }
}

// ─────────────────────────── Medicine tile widget ───────────────────────────

class _MedicineTile extends StatelessWidget {
  final _PrescriptionMedicine medicine;
  final VoidCallback onAddReminder;

  const _MedicineTile({
    required this.medicine,
    required this.onAddReminder,
  });

  Widget _infoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppTheme.textSecondary),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  medicine.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppTheme.textPrimary),
                ),
              ),
              TextButton.icon(
                onPressed: onAddReminder,
                icon: const Icon(Icons.alarm_add_outlined, size: 16),
                label: const Text('Remind',
                    style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (medicine.dosage.isNotEmpty)
                _infoChip(Icons.medication_outlined, medicine.dosage),
              if (medicine.frequency.isNotEmpty)
                _infoChip(Icons.repeat_outlined, medicine.frequency),
              if (medicine.duration.isNotEmpty)
                _infoChip(Icons.calendar_today_outlined, medicine.duration),
            ],
          ),
        ],
      ),
    );
  }
}
