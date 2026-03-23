import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/core/theme/app_theme.dart';
import 'package:vitapulse_ai/shared/widgets/loading_button.dart';

class MedicineDetailScreen extends StatefulWidget {
  final String medicineId;
  final Map<String, dynamic>? extra;

  const MedicineDetailScreen({
    super.key,
    required this.medicineId,
    this.extra,
  });

  @override
  State<MedicineDetailScreen> createState() => _MedicineDetailScreenState();
}

class _MedicineDetailScreenState extends State<MedicineDetailScreen> {
  Map<String, dynamic>? _medicine;
  bool _loading = true;
  String _error = '';
  bool _addingReminder = false;

  @override
  void initState() {
    super.initState();
    if (widget.extra != null && widget.extra!.isNotEmpty) {
      _medicine = widget.extra;
      _loading = false;
      // If extra has limited data, fetch full AI info
      if (!_hasFullData(widget.extra!)) {
        _fetchAiInfo(widget.extra!['name']?.toString() ?? widget.medicineId);
      }
    } else {
      _fetchAiInfo(widget.medicineId);
    }
  }

  bool _hasFullData(Map<String, dynamic> data) {
    return data.containsKey('composition') ||
        data.containsKey('dosage') ||
        data.containsKey('side_effects');
  }

  Future<void> _fetchAiInfo(String name) async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final resp = await ApiClient.get('/medicines/ai-info/$name');
      setState(() {
        _medicine = Map<String, dynamic>.from(resp.data as Map);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load medicine information.';
        _loading = false;
      });
    }
  }

  String _medicineName() {
    if (_medicine != null) {
      return _medicine!['name']?.toString() ?? widget.medicineId;
    }
    return widget.medicineId;
  }

  String _getSchedule() => _medicine?['au_schedule']?.toString() ?? '';
  bool _isTgaRegistered() => _medicine?['tga_registered'] == true;

  Color _scheduleColor(String schedule) {
    switch (schedule.toUpperCase()) {
      case 'S2':
        return const Color(0xFF388E3C);
      case 'S3':
        return const Color(0xFF1565C0);
      case 'S4':
        return const Color(0xFFE65100);
      case 'S8':
        return const Color(0xFFD32F2F);
      default:
        return AppTheme.textSecondary;
    }
  }

  Future<void> _addToReminders() async {
    setState(() => _addingReminder = true);
    await Future.delayed(const Duration(milliseconds: 300));
    setState(() => _addingReminder = false);
    if (!mounted) return;
    context.go('/home/reminders/add');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(_medicineName()),
        actions: [
          if (!_loading && _medicine != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _fetchAiInfo(_medicine!['name']?.toString() ?? widget.medicineId),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _error.isNotEmpty
              ? _buildError()
              : _buildContent(),
      bottomNavigationBar: (!_loading && _medicine != null)
          ? _buildBottomBar()
          : null,
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppTheme.error, size: 56),
            const SizedBox(height: 16),
            Text(_error, style: const TextStyle(color: AppTheme.textSecondary), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => _fetchAiInfo(widget.medicineId),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final medicine = _medicine!;
    final schedule = _getSchedule();
    final tga = _isTgaRegistered();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        // Header card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0x1A00897B),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.medication, color: AppTheme.primary, size: 32),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            medicine['name']?.toString() ?? widget.medicineId,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          if (medicine['generic_name']?.toString().isNotEmpty == true) ...[
                            const SizedBox(height: 4),
                            Text(
                              medicine['generic_name'].toString(),
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              if (tga)
                                _Badge(
                                  label: 'TGA Registered',
                                  color: AppTheme.success,
                                  icon: Icons.verified,
                                ),
                              if (schedule.isNotEmpty)
                                _Badge(
                                  label: schedule,
                                  color: _scheduleColor(schedule),
                                  icon: Icons.label,
                                ),
                              if (medicine['drug_class']?.toString().isNotEmpty == true)
                                _Badge(
                                  label: medicine['drug_class'].toString(),
                                  color: AppTheme.secondary,
                                  icon: Icons.category,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (medicine['manufacturer']?.toString().isNotEmpty == true) ...[
                  const Divider(height: 24),
                  Row(
                    children: [
                      const Icon(Icons.business, size: 14, color: AppTheme.textSecondary),
                      const SizedBox(width: 6),
                      Text(
                        medicine['manufacturer'].toString(),
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        _SectionTile(
          title: 'Composition',
          icon: Icons.science,
          content: medicine['composition']?.toString() ?? '',
          initiallyExpanded: true,
        ),
        _SectionTile(
          title: 'Dosage',
          icon: Icons.schedule,
          content: medicine['dosage']?.toString() ?? '',
          initiallyExpanded: true,
        ),
        _SectionTile(
          title: 'Side Effects',
          icon: Icons.warning_amber,
          iconColor: const Color(0xFFE65100),
          content: medicine['side_effects']?.toString() ?? '',
        ),
        _SectionTile(
          title: 'Drug Interactions',
          icon: Icons.compare_arrows,
          iconColor: AppTheme.secondary,
          content: medicine['interactions']?.toString() ?? '',
        ),
        _SectionTile(
          title: 'Contraindications',
          icon: Icons.block,
          iconColor: AppTheme.error,
          content: medicine['contraindications']?.toString() ?? '',
        ),
        _SectionTile(
          title: 'Warnings & Precautions',
          icon: Icons.info_outline,
          iconColor: AppTheme.accent,
          content: medicine['warnings']?.toString() ?? '',
        ),

        if (medicine['storage']?.toString().isNotEmpty == true) ...[
          const SizedBox(height: 4),
          _SectionTile(
            title: 'Storage Instructions',
            icon: Icons.inventory_2,
            content: medicine['storage'].toString(),
          ),
        ],

        if (medicine['pregnancy_category']?.toString().isNotEmpty == true) ...[
          const SizedBox(height: 4),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.child_care, color: AppTheme.primary, size: 22),
                  const SizedBox(width: 10),
                  const Text(
                    'Pregnancy Category:',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    medicine['pregnancy_category'].toString(),
                    style: const TextStyle(color: AppTheme.secondary, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: const Color(0x14000000), blurRadius: 8, offset: const Offset(0, -2)),
        ],
      ),
      child: LoadingButton(
        text: 'Add to Reminders',
        loading: _addingReminder,
        onPressed: _addToReminders,
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color? iconColor;
  final String content;
  final bool initiallyExpanded;

  const _SectionTile({
    required this.title,
    required this.icon,
    this.iconColor,
    required this.content,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveContent = content.trim().isEmpty ? 'Information not available.' : content;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Color.fromRGBO((iconColor ?? AppTheme.primary).red, (iconColor ?? AppTheme.primary).green, (iconColor ?? AppTheme.primary).blue, 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor ?? AppTheme.primary, size: 18),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: AppTheme.textPrimary,
            ),
          ),
          children: [
            Text(
              effectiveContent,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _Badge({required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Color.fromRGBO(color.red, color.green, color.blue, 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Color.fromRGBO(color.red, color.green, color.blue, 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
