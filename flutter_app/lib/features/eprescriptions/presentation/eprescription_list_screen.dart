import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vitapulse_ai/core/utils/error_handler.dart';
import 'package:vitapulse_ai/features/eprescriptions/data/eprescription_api.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';

/// Displays a list of the user's validated ePrescriptions.
class EPrescriptionListScreen extends StatefulWidget {
  const EPrescriptionListScreen({super.key});

  @override
  State<EPrescriptionListScreen> createState() =>
      _EPrescriptionListScreenState();
}

class _EPrescriptionListScreenState
    extends State<EPrescriptionListScreen> {
  List<Map<String, dynamic>> _items = [];
  bool    _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await EPrescriptionApi.list();
      if (mounted) setState(() { _items = data; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error   = ErrorHandler.getMessage(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _delete(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete ePrescription'),
        content: const Text(
          'This record will be permanently removed. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await EPrescriptionApi.delete(id);
      if (mounted) {
        setState(() => _items.removeWhere((e) => e['id'] == id));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ePrescription deleted.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorHandler.getMessage(e)),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
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
        title: const Text('My ePrescriptions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan new ePrescription',
            onPressed: () => context.go('/home/eprescriptions/scan'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Scan ePrescription'),
        onPressed: () => context.go('/home/eprescriptions/scan'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final cs = Theme.of(context).colorScheme;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off,
                  size: 48, color: cs.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.qr_code_2,
                    size: 56, color: cs.primary),
              ),
              const SizedBox(height: 20),
              const Text('No ePrescriptions yet',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                'Scan a QR code from your doctor\'s ePrescription to get started.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                  shape: const RoundedRectangleBorder(
                      borderRadius: AppRadius.brSm),
                ),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan ePrescription'),
                onPressed: () =>
                    context.go('/home/eprescriptions/scan'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _EPrescriptionCard(
        item:     _items[i],
        onTap:    () =>
            context.go('/home/eprescriptions/${_items[i]['id']}'),
        onDelete: () => _delete(_items[i]['id'] as int),
      ),
    );
  }
}

// ─── Card ──────────────────────────────────────────────────────────────────

class _EPrescriptionCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _EPrescriptionCard({
    required this.item,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs           = Theme.of(context).colorScheme;
    final hc           = HealthcareColors.of(context);
    final provider     = (item['provider'] as String? ?? 'erx').toUpperCase();
    final patientName  = item['patient_name']  as String? ?? 'Unknown Patient';
    final prescriber   = item['prescriber_name'] as String? ?? '';
    final medCount     = item['medicine_count'] as int?    ?? 0;
    final status       = item['status']         as String? ?? 'validated';
    final rawDate      = item['created_at']     as String?;
    final createdAt    =
        rawDate != null ? DateTime.tryParse(rawDate) : null;

    final providerColor = cs.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brLg,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: AppRadius.brLg,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: providerColor.withValues(alpha: 0.12),
                    borderRadius: AppRadius.brXxl,
                    border: Border.all(
                        color:
                            providerColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified,
                          size: 13, color: providerColor),
                      const SizedBox(width: 4),
                      Text(
                        provider == 'MOCK'
                            ? 'eRx (Demo)'
                            : provider,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: providerColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                _StatusBadge(status: status, hc: hc, cs: cs),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onDelete,
                  child: Icon(Icons.delete_outline,
                      size: 20, color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              patientName,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (prescriber.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(prescriber,
                  style: TextStyle(
                      color: cs.onSurfaceVariant, fontSize: 13)),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.medication,
                    size: 15, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  '$medCount medicine${medCount == 1 ? '' : 's'}',
                  style: TextStyle(
                      color: cs.onSurfaceVariant, fontSize: 13),
                ),
                const Spacer(),
                if (createdAt != null)
                  Text(
                    _formatDate(createdAt),
                    style: TextStyle(
                        color: cs.onSurfaceVariant, fontSize: 12),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';
}

class _StatusBadge extends StatelessWidget {
  final String status;
  final HealthcareColors hc;
  final ColorScheme cs;

  const _StatusBadge({
    required this.status,
    required this.hc,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      'validated' => (hc.discharge,         'Valid'),
      'dispensed' => (hc.prescription,      'Dispensed'),
      'expired'   => (cs.error,             'Expired'),
      _           => (cs.onSurfaceVariant,  status),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: AppRadius.brMd,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color)),
    );
  }
}
