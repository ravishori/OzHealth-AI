import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/core/theme/app_theme.dart';

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key});

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = true;
  List<Map<String, dynamic>> _records = [];

  static const _tabs = [
    _TabInfo('All', null, Icons.folder_outlined),
    _TabInfo('Prescriptions', 'prescription', Icons.receipt_long_outlined),
    _TabInfo('Lab Reports', 'lab_report', Icons.biotech_outlined),
    _TabInfo('Radiology', 'radiology', Icons.image_search_outlined),
    _TabInfo('Discharge', 'discharge', Icons.local_hospital_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) _loadRecords();
    });
    _loadRecords();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRecords() async {
    setState(() => _loading = true);
    try {
      final selectedTab = _tabs[_tabController.index];
      final queryParams = selectedTab.type != null
          ? {'record_type': selectedTab.type!}
          : null;
      final resp =
          await ApiClient.get('/records/', queryParameters: queryParams);
      setState(() {
        _records = (resp.data as List<dynamic>).cast<Map<String, dynamic>>();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load records'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      setState(() => _loading = false);
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
        return Icons.local_hospital_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  Color _colorForType(String? type) {
    switch (type) {
      case 'prescription':
        return const Color(0xFF1565C0);
      case 'lab_report':
        return const Color(0xFF558B2F);
      case 'radiology':
        return const Color(0xFF6A1B9A);
      case 'discharge':
        return AppTheme.accent;
      default:
        return AppTheme.primary;
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
        return 'Discharge';
      default:
        return 'Record';
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
          if (uploaded == true) _loadRecords();
        },
        backgroundColor: AppTheme.primary,
        child: const Icon(Icons.upload_file, color: Colors.white),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _tabs.map((_) => _buildTabContent()).toList(),
      ),
    );
  }

  Widget _buildTabContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_records.isEmpty) {
      return _buildEmptyState();
    }
    return RefreshIndicator(
      onRefresh: _loadRecords,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
        itemCount: _records.length,
        itemBuilder: (ctx, i) => _buildRecordCard(_records[i]),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open_outlined,
              size: 64, color: AppTheme.primary.withOpacity(0.4)),
          const SizedBox(height: 16),
          const Text('No records found',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          const Text(
            'Upload your medical records\nto keep them organised',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () async {
              final uploaded = await context.push('/home/records/upload');
              if (uploaded == true) _loadRecords();
            },
            icon: const Icon(Icons.upload_file),
            label: const Text('Upload Record'),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordCard(Map<String, dynamic> record) {
    final title = record['title'] as String? ?? 'Untitled';
    final type = record['record_type'] as String?;
    final fileType = record['file_type'] as String? ?? '';
    final date = _formatDate(record['record_date'] as String?);
    final color = _colorForType(type);
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
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
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
              if (fileType.isNotEmpty) _typeBadge(fileType.toUpperCase(), AppTheme.textSecondary),
              if (date.isNotEmpty) ...[
                const Spacer(),
                Icon(Icons.calendar_today_outlined,
                    size: 12, color: AppTheme.textSecondary),
                const SizedBox(width: 3),
                Text(date,
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textSecondary)),
              ],
            ],
          ),
        ),
        trailing:
            const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
        onTap: () {
          // View detail – future route
        },
      ),
    );
  }

  Widget _typeBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.w500),
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
