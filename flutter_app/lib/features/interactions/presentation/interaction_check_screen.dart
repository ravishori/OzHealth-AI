import 'package:flutter/material.dart';
import 'package:vitapulse_ai/core/utils/error_handler.dart';
import 'package:vitapulse_ai/features/interactions/data/interactions_api.dart';
import 'package:vitapulse_ai/features/legal/legal_copy.dart';
import 'package:vitapulse_ai/features/medicines/data/medicine_api.dart';
import 'package:vitapulse_ai/shared/widgets/clinical_safety_banner.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';

typedef InteractionCheckFn = Future<Map<String, dynamic>> Function({
  List<int>? medicineIds,
  List<String>? medicines,
  bool includeDuplicateCheck,
});

typedef MedicineSearchFn = Future<Map<String, dynamic>> Function(String query);

class _SelectedMedicine {
  final int? id;
  final String name;
  const _SelectedMedicine({required this.name, this.id});
}

/// HN-FUTURE-004 — source-grounded interaction checker screen.
class InteractionCheckScreen extends StatefulWidget {
  const InteractionCheckScreen({
    super.key,
    this.checkInteractions,
    this.searchMedicines,
  });

  final InteractionCheckFn? checkInteractions;
  final MedicineSearchFn? searchMedicines;

  @override
  State<InteractionCheckScreen> createState() => _InteractionCheckScreenState();
}

class _InteractionCheckScreenState extends State<InteractionCheckScreen> {
  final _controller = TextEditingController();
  final List<_SelectedMedicine> _medicines = [];
  List<Map<String, dynamic>> _suggestions = [];
  Map<String, dynamic>? _result;
  bool _loading = false;
  bool _searching = false;
  String? _error;

  Future<void> _onQueryChanged(String value) async {
    final q = value.trim();
    if (q.length < 2) {
      setState(() => _suggestions = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final search = widget.searchMedicines ?? MedicineApi.search;
      final resp = await search(q);
      final raw = resp['results'] ?? resp['medicines'] ?? resp['items'];
      final list = (raw is List)
          ? raw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() => _suggestions = list.take(8).toList());
    } catch (_) {
      if (!mounted) return;
      setState(() => _suggestions = []);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _addFromSuggestion(Map<String, dynamic> med) {
    final id = med['id'] is int
        ? med['id'] as int
        : int.tryParse('${med['id']}');
    final name = (med['name'] ?? med['generic_name'] ?? '').toString().trim();
    if (name.isEmpty) return;
    if (_medicines.any((m) =>
        (id != null && m.id == id) ||
        m.name.toLowerCase() == name.toLowerCase())) {
      return;
    }
    setState(() {
      _medicines.add(_SelectedMedicine(id: id, name: name));
      _controller.clear();
      _suggestions = [];
      _result = null;
      _error = null;
    });
  }

  void _addFreeText() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    if (_medicines.any((m) => m.name.toLowerCase() == name.toLowerCase())) {
      return;
    }
    setState(() {
      _medicines.add(_SelectedMedicine(name: name));
      _controller.clear();
      _suggestions = [];
      _result = null;
      _error = null;
    });
  }

  void _removeMedicine(int index) {
    setState(() {
      _medicines.removeAt(index);
      _result = null;
      _error = null;
    });
  }

  Future<void> _check() async {
    if (_loading) return;
    if (_medicines.length < 2) {
      setState(() =>
          _error = 'Add at least 2 medicines to check interactions');
      return;
    }
    setState(() {
      _loading = true;
      _result = null;
      _error = null;
    });
    try {
      final ids = _medicines
          .where((m) => m.id != null)
          .map((m) => m.id!)
          .toList();
      final names = _medicines
          .where((m) => m.id == null)
          .map((m) => m.name)
          .toList();
      final check = widget.checkInteractions ??
          ({
            List<int>? medicineIds,
            List<String>? medicines,
            bool includeDuplicateCheck = true,
          }) =>
              InteractionsApi.checkInteractions(
                medicineIds: medicineIds,
                medicines: medicines,
                includeDuplicateCheck: includeDuplicateCheck,
              );
      final result = await check(
        medicineIds: ids.isEmpty ? null : ids,
        medicines: names.isEmpty ? null : names,
        includeDuplicateCheck: true,
      );
      if (!mounted) return;
      setState(() => _result = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorHandler.getMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
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
      key: const Key('interaction_check_screen'),
      appBar: AppBar(
        title: const Text('Drug Interaction Check'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ClinicalSafetyBanner(
              key: Key('interaction_safety_banner'),
              kind: ClinicalDisclaimerKind.interaction,
              rounded: true,
              padding: EdgeInsets.all(12),
            ),
            const SizedBox(height: 12),
            _buildInfoBanner(),
            const SizedBox(height: 16),
            _buildMedicineInput(),
            if (_suggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildSuggestions(),
            ],
            const SizedBox(height: 12),
            _buildMedicineChips(),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('interaction_check_button'),
                onPressed: _loading ? null : _check,
                icon: _loading
                    ? const SizedBox(
                        key: Key('interaction_loading'),
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.biotech),
                label: Text(
                    _loading ? 'Checking records...' : 'Check Interactions'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                key: const Key('interaction_error_banner'),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .error
                      .withValues(alpha: 0.08),
                  borderRadius: AppRadius.brMd,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                    TextButton(
                      key: const Key('interaction_retry_button'),
                      onPressed: _loading ? null : _check,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ],
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
      key: const Key('interaction_purpose_banner'),
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
              'Select medicines from the catalogue. Results use database '
              'records when available. Unavailable information does not mean '
              'medicines are safe together.',
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
            key: const Key('interaction_medicine_input'),
            controller: _controller,
            decoration: InputDecoration(
              hintText: 'Search catalogue medicine',
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
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
            onChanged: _onQueryChanged,
            onSubmitted: (_) => _addFreeText(),
          ),
        ),
        const SizedBox(width: 10),
        FilledButton(
          key: const Key('interaction_add_button'),
          onPressed: _addFreeText,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          child: const Icon(Icons.add),
        ),
      ],
    );
  }

  Widget _buildSuggestions() {
    final cs = Theme.of(context).colorScheme;
    return Material(
      key: const Key('interaction_suggestions'),
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.brMd,
        side: BorderSide(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: _suggestions.map((m) {
          final name = m['name']?.toString() ?? '';
          final generic = m['generic_name']?.toString();
          return ListTile(
            dense: true,
            title: Text(name, style: const TextStyle(fontSize: 13)),
            subtitle: generic != null && generic.isNotEmpty
                ? Text(generic, style: const TextStyle(fontSize: 11))
                : null,
            onTap: () => _addFromSuggestion(m),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMedicineChips() {
    final cs = Theme.of(context).colorScheme;
    if (_medicines.isEmpty) {
      return Text(
        'No medicines added yet.',
        key: const Key('interaction_empty_selection'),
        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
      );
    }
    return Wrap(
      key: const Key('interaction_selected_list'),
      spacing: 8,
      runSpacing: 6,
      children: _medicines.asMap().entries.map((e) {
        final label = e.value.id != null
            ? '${e.value.name} (#${e.value.id})'
            : '${e.value.name} (unresolved)';
        return Chip(
          label: Text(label),
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
    final unresolved = (_result!['unresolved'] as List?) ?? [];
    final riskLevel = analysis['risk_level'] as String?;
    final interactions =
        (analysis['interactions'] as List?)?.cast<Map<String, dynamic>>() ??
            [];
    final recommendations =
        (analysis['recommendations'] as List?)?.cast<String>() ?? [];
    final unavailable = analysis['unavailable'] == true ||
        riskLevel == 'unavailable' ||
        riskLevel == 'unknown';
    final disclaimer =
        _result!['disclaimer']?.toString() ?? LegalCopy.interactionBanner;

    // Never treat unavailable as green/safe.
    final statusColor = unavailable
        ? hc.vitaWarning
        : (riskLevel == 'known' ? cs.primary : cs.onSurfaceVariant);

    final known = interactions
        .where((i) =>
            i['status'] == 'KNOWN' || i['status'] == 'KNOWN_FROM_TEXT')
        .toList();
    final unknown = interactions
        .where((i) => i['status'] == 'UNKNOWN' || i['unavailable'] == true)
        .toList();

    return Column(
      key: const Key('interaction_results'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          key: const Key('interaction_status_card'),
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: AppRadius.brLg,
            border: Border.all(color: statusColor.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Icon(
                unavailable ? Icons.help_outline : Icons.fact_check,
                color: statusColor,
                size: 32,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      unavailable
                          ? 'Interaction information unavailable'
                          : 'Source-backed interaction records',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: statusColor),
                    ),
                    if (analysis['overall_summary'] != null)
                      Text(analysis['overall_summary'],
                          style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(
                      unavailable
                          ? 'This does not mean the medicines are confirmed safe together.'
                          : 'Structured database result — not clinician confirmation.',
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (unresolved.isNotEmpty) ...[
          Container(
            key: const Key('interaction_unresolved_banner'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: hc.vitaWarning.withValues(alpha: 0.1),
              borderRadius: AppRadius.brMd,
              border:
                  Border.all(color: hc.vitaWarning.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Unresolved / unsupported medicines',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: hc.vitaWarning)),
                const SizedBox(height: 6),
                ...unresolved.map((u) => Text(
                      '• ${u is Map ? (u['input'] ?? u) : u}',
                      style: const TextStyle(fontSize: 13),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        if (known.isNotEmpty) ...[
          const Text('Source-backed interactions',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          ...known.map((i) => _InteractionCard(interaction: i)),
          const SizedBox(height: 12),
        ],

        if (unknown.isNotEmpty) ...[
          const Text('No authoritative record for these pairs',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          ...unknown.map((i) => _UnavailablePairCard(interaction: i)),
          const SizedBox(height: 12),
        ],

        if (recommendations.isNotEmpty) ...[
          const Text('Guidance',
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

        if (duplicates != null &&
            (duplicates['duplicates'] as List? ?? []).isNotEmpty) ...[
          Container(
            key: const Key('interaction_duplicate_warning'),
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
                      'Duplicate medicine warning (not a drug interaction)',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: hc.vitaWarning),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...(duplicates['duplicates'] as List).map((d) {
                  final map = d is Map
                      ? Map<String, dynamic>.from(d)
                      : <String, dynamic>{};
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '• ${map['medicine_a']} ↔ ${map['medicine_b']}: '
                      '${map['reason'] ?? map['risk'] ?? 'catalogue duplicate'}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        Text(
          disclaimer,
          key: const Key('interaction_disclaimer'),
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _UnavailablePairCard extends StatelessWidget {
  final Map<String, dynamic> interaction;
  const _UnavailablePairCard({required this.interaction});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);
    final a = interaction['drug_a'] ??
        (interaction['medicine_a'] is Map
            ? interaction['medicine_a']['name']
            : null) ??
        '?';
    final b = interaction['drug_b'] ??
        (interaction['medicine_b'] is Map
            ? interaction['medicine_b']['name']
            : null) ??
        '?';
    return Container(
      key: const Key('interaction_unavailable_card'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: AppRadius.brMd,
        border: Border(left: BorderSide(color: hc.vitaWarning, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$a + $b',
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            interaction['description']?.toString() ??
                'Interaction information is unavailable for this medicine pair.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            'Status: UNAVAILABLE — not verified as safe',
            style: TextStyle(
                fontSize: 11,
                color: hc.vitaWarning,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _InteractionCard extends StatelessWidget {
  final Map<String, dynamic> interaction;
  const _InteractionCard({required this.interaction});

  Color _severityColor(BuildContext context, String? s) {
    final hc = HealthcareColors.of(context);
    final cs = Theme.of(context).colorScheme;
    switch (s?.toLowerCase()) {
      case 'contraindicated':
      case 'major':
      case 'high':
        return hc.vitaCritical;
      case 'moderate':
      case 'medium':
        return hc.vitaWarning;
      case 'minor':
      case 'low':
        return cs.secondary;
      default:
        return cs.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final severity = interaction['severity'] as String?;
    final sevColor = _severityColor(context, severity);
    final sourceType = interaction['source_type']?.toString() ?? 'source_backed';
    final sourceName = interaction['source_name']?.toString();
    final a = interaction['drug_a'] ??
        (interaction['medicine_a'] is Map
            ? interaction['medicine_a']['name']
            : null) ??
        '?';
    final b = interaction['drug_b'] ??
        (interaction['medicine_b'] is Map
            ? interaction['medicine_b']['name']
            : null) ??
        '?';

    return Container(
      key: const Key('interaction_source_card'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: AppRadius.brMd,
        border: Border(left: BorderSide(color: sevColor, width: 4)),
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
                  '$a + $b',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              if (severity != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: sevColor.withValues(alpha: 0.15),
                    borderRadius: AppRadius.brFull,
                  ),
                  child: Text(
                    severity.toUpperCase(),
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
          if (interaction['recommendation'] != null ||
              interaction['recommended_action'] != null) ...[
            const SizedBox(height: 4),
            Text(
              '→ ${interaction['recommended_action'] ?? interaction['recommendation']}',
              style: TextStyle(
                  fontSize: 12,
                  color: cs.primary,
                  fontWeight: FontWeight.w500),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            [
              'Source: $sourceType',
              if (sourceName != null && sourceName.isNotEmpty)
                'Provenance: $sourceName',
              if (interaction['verified'] == true) 'Verified: database record',
            ].join(' · '),
            key: const Key('interaction_provenance'),
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
