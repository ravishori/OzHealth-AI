import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key});

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Per-tab cache — prevents all-tab flicker when switching tabs
  final Map<int, List<Map<String, dynamic>>> _recordsByTab = {};
  final Set<int> _loadingTabs = {};

  static const _tabs = [
    _TabInfo('All', null, Icons.folder_outlined),
    _TabInfo('Prescriptions', 'prescription', Icons.receipt_long_outlined),
    _TabInfo('Lab Reports', 'lab_report', Icons.biotech_outlined),
    _TabInfo('Radiology', 'radiology', Icons.image_search_outlined),
    _TabInfo('Discharge', 'discharge_summary', Icons.local_hospital_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _loadRecords(_tabController.index);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRecords(0));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRecords([int? tabIndex]) async {
    final idx = tabIndex ?? _tabController.index;
    setState(() => _loadingTabs.add(idx));
    try {
      final selectedTab = _tabs[idx];
      final queryParams = selectedTab.type != null
          ? {'record_type': selectedTab.type!}
          : null;
      final resp =
          await ApiClient.get('/records/', queryParameters: queryParams);
      if (mounted) {
        setState(() {
          _recordsByTab[idx] =
              (resp.data as List<dynamic>).cast<Map<String, dynamic>>();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to load records'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingTabs.remove(idx));
    }
  }

  IconData _iconForType(String? type) {
    switch (type) {
      case 'prescription':
        return Icons.receipt_long_outlined;
      case 'lab_report':
        return Icons.biotech_outlined;
      case 'radiology':
        return Icons.image_search_outlined;
      case 'discharge':
      case 'discharge_summary':
        return Icons.local_hospital_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  Color _colorForType(String? type, ColorScheme cs, HealthcareColors hc) {
    switch (type) {
      case 'prescription':
        return hc.prescription;
      case 'lab_report':
        return hc.labReport;
      case 'radiology':
        return hc.radiology;
      case 'discharge':
      case 'discharge_summary':
        return hc.discharge;
      default:
        return cs.primary;
    }
  }

  String _labelForType(String? type) {
    switch (type) {
      case 'prescription':
        return 'Prescription';
      case 'lab_report':
        return 'Lab Report';
      case 'radiology':
        return 'Radiology';
      case 'discharge':
      case 'discharge_summary':
        return 'Discharge';
      default:
        return 'Record';
    }
  }

  Future<void> _viewRecordFile(Map<String, dynamic> record) async {
    final id = record['id'];
    if (id == null) return;
    try {
      final resp = await ApiClient.downloadBytes('/records/$id/file');
      final bytes = resp.data;
      if (bytes is! List<int>) {
        throw Exception('Unexpected file payload');
      }
      final dir = await getTemporaryDirectory();
      final name = record['file_name']?.toString() ?? 'record_$id';
      final path = '${dir.path}${Platform.pathSeparator}$name';
      final file = File(path);
      await file.writeAsBytes(bytes, flush: true);
      final uri = Uri.file(path);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Downloaded to $path')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open file. Access denied or missing.')),
        );
      }
    }
  }

  Future<void> _deleteRecord(Map<String, dynamic> record) async {
    final id = record['id'];
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete record?'),
        content: const Text('This removes the record from your account.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient.delete('/records/$id');
      if (!mounted) return;
      Navigator.of(context).pop(); // close sheet
      _recordsByTab.clear();
      await _loadRecords(_tabController.index);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Record deleted')),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete record')),
        );
      }
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final dt = DateTime.parse(dateStr);
      return DateFormat('dd MMM yyyy').format(dt);
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Medical Records'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabAlignment: TabAlignment.start,
          tabs: _tabs
              .map((t) => Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(t.icon, size: 16),
                        const SizedBox(width: 6),
                        Text(t.label),
                      ],
                    ),
                  ))
              .toList(),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final uploaded = await context.push('/home/records/upload');
          if (uploaded == true) _loadRecords(_tabController.index);
        },
        backgroundColor: cs.primary,
        child: const Icon(Icons.upload_file, color: Colors.white),
      ),
      body: TabBarView(
        controller: _tabController,
        children: List.generate(_tabs.length, (i) => _buildTabContent(i)),
      ),
    );
  }

  Widget _buildTabContent(int tabIndex) {
    final isLoading = _loadingTabs.contains(tabIndex);
    if (isLoading && !_recordsByTab.containsKey(tabIndex)) {
      return const Center(child: CircularProgressIndicator());
    }
    final records = _recordsByTab[tabIndex] ?? [];
    if (records.isEmpty && !isLoading) {
      return _buildEmptyState(tabIndex);
    }
    return RefreshIndicator(
      onRefresh: () => _loadRecords(tabIndex),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
        itemCount: records.length,
        itemBuilder: (ctx, i) => _buildRecordCard(records[i]),
      ),
    );
  }

  Widget _buildEmptyState(int tabIndex) {
    final cs = Theme.of(context).colorScheme;
    final label =
        tabIndex == 0 ? 'records' : _tabs[tabIndex].label.toLowerCase();
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open_outlined,
              size: 64, color: cs.primary.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text('No $label found',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text(
            'Upload your medical records\nto keep them organised',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () async {
              final uploaded = await context.push('/home/records/upload');
              if (uploaded == true) _loadRecords(tabIndex);
            },
            icon: const Icon(Icons.upload_file),
            label: const Text('Upload Record'),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordCard(Map<String, dynamic> record) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);
    final title = record['title'] as String? ?? 'Untitled';
    final type = record['record_type'] as String?;
    final fileType = record['file_type'] as String? ?? '';
    final date = _formatDate(record['record_date'] as String?);
    final color = _colorForType(type, cs, hc);
    final icon = _iconForType(type);
    final typeLabel = _labelForType(type);

    return Card(
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: AppRadius.brSm,
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              _typeBadge(typeLabel, color),
              const SizedBox(width: 8),
              if (fileType.isNotEmpty)
                _typeBadge(fileType.toUpperCase(), cs.onSurfaceVariant),
              if (date.isNotEmpty) ...[
                const Spacer(),
                Icon(Icons.calendar_today_outlined,
                    size: 12, color: cs.onSurfaceVariant),
                const SizedBox(width: 3),
                Text(date,
                    style:
                        TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ],
            ],
          ),
        ),
        trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
        onTap: () => _showRecordDetail(record),
      ),
    );
  }

  void _showRecordDetail(Map<String, dynamic> record) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);
    final title = record['title'] as String? ?? 'Untitled';
    final type = record['record_type'] as String?;
    final fileType = record['file_type'] as String? ?? '';
    final date = _formatDate(record['record_date'] as String?);
    final notes = record['notes'] as String?;
    final color = _colorForType(type, cs, hc);
    final icon = _iconForType(type);
    final typeLabel = _labelForType(type);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: AppRadius.brMd,
                        ),
                        child: Icon(icon, color: color, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            _typeBadge(typeLabel, color),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 8),
                  if (date.isNotEmpty)
                    _detailRow(Icons.calendar_today_outlined, 'Date', date),
                  if (fileType.isNotEmpty)
                    _detailRow(Icons.insert_drive_file_outlined, 'File type',
                        fileType.toUpperCase()),
                  if (notes != null && notes.isNotEmpty)
                    _detailRow(Icons.notes_outlined, 'Notes', notes),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => _viewRecordFile(record),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('View / download file'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _deleteRecord(record),
                    icon: Icon(Icons.delete_outline, color: cs.error),
                    label: Text('Delete record', style: TextStyle(color: cs.error)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style:
                        TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(fontSize: 14, color: cs.onSurface)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _typeBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.brFull,
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _TabInfo {
  final String label;
  final String? type;
  final IconData icon;

  const _TabInfo(this.label, this.type, this.icon);
}
