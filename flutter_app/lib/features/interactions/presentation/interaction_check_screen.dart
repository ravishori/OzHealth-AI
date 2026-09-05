import 'package:flutter/material.dart';
import 'package:vitapulse_ai/core/utils/error_handler.dart';
import 'package:vitapulse_ai/features/interactions/data/interactions_api.dart';
import 'package:vitapulse_ai/shared/widgets/clinical_safety_banner.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';

class InteractionCheckScreen extends StatefulWidget {
  const InteractionCheckScreen({super.key});

  @override
  State<InteractionCheckScreen> createState() => _InteractionCheckScreenState();
}

class _InteractionCheckScreenState extends State<InteractionCheckScreen> {
  final _controller = TextEditingController();
  final List<String> _medicines = [];
  Map<String, dynamic>? _result;
  bool _loading = false;

  void _addMedicine() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _medicines.add(name);
      _controller.clear();
    });
  }

  void _removeMedicine(int index) {
    setState(() => _medicines.removeAt(index));
  }

  Future<void> _check() async {
    if (_medicines.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Add at least 2 medicines to check interactions')),
      );
      return;
    }
    setState(() {
      _loading = true;
      _result = null;
    });
    try {
      final result = await InteractionsApi.checkInteractions(_medicines);
      setState(() => _result = result);
    } catch (e) {
      if (mounted) ErrorHandler.show(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _riskColor(String? level) {
    final hc = HealthcareColors.of(context);
    final cs = Theme.of(context).colorScheme;
    switch (level?.toLowerCase()) {
      case 'critical':
        return hc.vitaCritical;
      case 'high':
        return hc.vitaWarning;
      case 'medium':
        return hc.vitaWarning;
      case 'low':
        return hc.vitaGood;
      default:
        return cs.onSurfaceVariant;
    }
  }

  IconData _riskIcon(String? level) {
    switch (level?.toLowerCase()) {
      case 'critical':
        return Icons.dangerous;
      case 'high':
        return Icons.warning;
      case 'medium':
        return Icons.warning_amber;
      case 'low':
        return Icons.check_circle;
      default:
        return Icons.help_outline;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Drug Interaction Check'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ClinicalSafetyBanner(
              kind: ClinicalDisclaimerKind.interaction,
              rounded: true,
              padding: EdgeInsets.all(12),
            ),
            const SizedBox(height: 12),
            _buildInfoBanner(),
            const SizedBox(height: 16),
            _buildMedicineInput(),
            const SizedBox(height: 12),
            _buildMedicineChips(),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loading ? null : _check,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.biotech),
                label: Text(_loading ? 'Analysing...' : 'Check Interactions'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            if (_result != null) ...[
              const SizedBox(height: 20),
              _buildResults(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoBanner() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.25),
        borderRadius: AppRadius.brMd,
        border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.biotech, color: cs.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Add all your medicines below to check for dangerous interactions and duplicate prescriptions.',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedicineInput() {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: 'Enter medicine name',
              filled: true,
              fillColor: cs.surface,
              border: OutlineInputBorder(
                borderRadius: AppRadius.brMd,
                borderSide: BorderSide(color: cs.outline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: AppRadius.brMd,
                borderSide: BorderSide(color: cs.outline),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            onSubmitted: (_) => _addMedicine(),
          ),
        ),
        const SizedBox(width: 10),
        FilledButton(
          onPressed: _addMedicine,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          child: const Icon(Icons.add),
        ),
      ],
    );
  }

  Widget _buildMedicineChips() {
    final cs = Theme.of(context).colorScheme;
    if (_medicines.isEmpty) {
      return Text(
        'No medicines added yet.',
        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: _medicines.asMap().entries.map((e) {
        return Chip(
          label: Text(e.value),
          deleteIcon: const Icon(Icons.close, size: 16),
          onDeleted: () => _removeMedicine(e.key),
          backgroundColor: cs.primaryContainer,
          labelStyle: TextStyle(color: cs.onPrimaryContainer, fontSize: 13),
          deleteIconColor: cs.onPrimaryContainer,
        );
      }).toList(),
    );
  }

  Widget _buildResults() {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);

    final analysis =
        _result!['interaction_analysis'] as Map<String, dynamic>? ?? {};
    final duplicates = _result!['duplicate_check'] as Map<String, dynamic>?;
    final riskLevel = analysis['risk_level'] as String?;
    final interactions =
        (analysis['interactions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final recommendations =
        (analysis['recommendations'] as List?)?.cast<String>() ?? [];

    final riskColor = _riskColor(riskLevel);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Risk level card ────────────────────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: riskColor.withValues(alpha: 0.1),
            borderRadius: AppRadius.brLg,
            border: Border.all(color: riskColor.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Icon(_riskIcon(riskLevel), color: riskColor, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Risk Level: ${(riskLevel ?? 'Unknown').toUpperCase()}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: riskColor),
                    ),
                    if (analysis['overall_summary'] != null)
                      Text(analysis['overall_summary'],
                          style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Interactions list ──────────────────────────────────────────────────
        if (interactions.isNotEmpty) ...[
          const Text('Interactions Found',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          ...interactions
              .map((i) => _InteractionCard(interaction: i)),
          const SizedBox(height: 12),
        ],

        // ── Recommendations ────────────────────────────────────────────────────
        if (recommendations.isNotEmpty) ...[
          const Text('Recommendations',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          ...recommendations.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.arrow_right, color: cs.primary, size: 20),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(r, style: const TextStyle(fontSize: 13))),
                  ],
                ),
              )),
          const SizedBox(height: 12),
        ],

        // ── Duplicate warnings ─────────────────────────────────────────────────
        if (duplicates != null &&
            (duplicates['duplicates'] as List? ?? []).isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: hc.vitaWarning.withValues(alpha: 0.12),
              borderRadius: AppRadius.brMd,
              border:
                  Border.all(color: hc.vitaWarning.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.content_copy, color: hc.vitaWarning, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Duplicate Medicines Detected',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: hc.vitaWarning),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...(duplicates['duplicates'] as List).map((d) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '• ${d['medicine_a']} ↔ ${d['medicine_b']}: ${d['risk']}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    )),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ── Interaction card ──────────────────────────────────────────────────────────

class _InteractionCard extends StatelessWidget {
  final Map<String, dynamic> interaction;
  const _InteractionCard({required this.interaction});

  Color _severityColor(BuildContext context, String? s) {
    final hc = HealthcareColors.of(context);
    final cs = Theme.of(context).colorScheme;
    switch (s?.toLowerCase()) {
      case 'contraindicated':
        return hc.vitaCritical;
      case 'major':
        return hc.vitaWarning;
      case 'moderate':
        return hc.vitaWarning;
      case 'minor':
        return hc.vitaGood;
      default:
        return cs.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final severity = interaction['severity'] as String?;
    final sevColor = _severityColor(context, severity);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: AppRadius.brMd,
        border: Border(
          left: BorderSide(color: sevColor, width: 4),
        ),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.06),
            blurRadius: 4,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${interaction['drug_a']} + ${interaction['drug_b']}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: sevColor.withValues(alpha: 0.15),
                  borderRadius: AppRadius.brFull,
                ),
                child: Text(
                  (severity ?? 'unknown').toUpperCase(),
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: sevColor),
                ),
              ),
            ],
          ),
          if (interaction['description'] != null) ...[
            const SizedBox(height: 4),
            Text(
              interaction['description'],
              style:
                  TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
          if (interaction['recommendation'] != null) ...[
            const SizedBox(height: 4),
            Text(
              '→ ${interaction['recommendation']}',
              style: TextStyle(
                  fontSize: 12,
                  color: cs.primary,
                  fontWeight: FontWeight.w500),
            ),
          ],
        ],
      ),
    );
  }
}
