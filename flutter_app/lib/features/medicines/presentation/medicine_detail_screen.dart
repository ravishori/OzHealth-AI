import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/core/utils/error_handler.dart';
import 'package:vitapulse_ai/features/medicines/data/medicine_api.dart';
import 'package:vitapulse_ai/shared/widgets/clinical_safety_banner.dart';
import 'package:vitapulse_ai/shared/widgets/loading_button.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';

/// Provenance labels for medicine detail honesty (HN-MED-008).
const String kDbProvenanceLabel = 'From medicine database';
const String kAiProvenanceLabel = 'AI-generated explanation';
const String kUnavailableLabel = 'Information not available';

class MedicineDetailScreen extends StatefulWidget {
  final String                 medicineId;
  final Map<String, dynamic>?  extra;

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
  Map<String, dynamic>? _explanation;
  bool   _loading          = true;
  String _error            = '';
  bool   _addingReminder   = false;
  bool   _loadingAlternatives  = false;
  bool   _loadingAllergyCheck  = false;
  Map<String, dynamic>? _alternatives;
  Map<String, dynamic>? _allergyCheck;

  @override
  void initState() {
    super.initState();
    // Search may pass a lightweight candidate — never treat it as clinical truth,
    // and never silently merge /ai-info into structured fields (HN-MED-008).
    if (widget.extra != null && widget.extra!.isNotEmpty) {
      _medicine = Map<String, dynamic>.from(widget.extra!);
    }
    final id = int.tryParse(widget.medicineId);
    if (id == null) {
      _loading = false;
      _error =
          'Medicine not found in catalogue. Select a medicine from search results.';
      return;
    }
    _loadById();
  }

  Future<void> _loadById() async {
    setState(() {
      _loading = true;
      _error   = '';
    });
    final id = int.tryParse(widget.medicineId);
    if (id == null) {
      setState(() {
        _medicine = null;
        _explanation = null;
        _error =
            'Medicine not found in catalogue. Select a medicine from search results.';
        _loading = false;
      });
      return;
    }
    try {
      final data = await MedicineApi.getMedicine(id);
      Map<String, dynamic>? explanation;
      try {
        explanation = await MedicineApi.getExplanation(id);
      } catch (_) {
        // Optional AI rephrase — structured DB fields remain authoritative.
        explanation = null;
      }
      if (!mounted) return;
      setState(() {
        _medicine = data;
        _explanation = explanation;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorHandler.getMessage(e);
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

  String _getSchedule()    => _medicine?['au_schedule']?.toString() ?? '';
  bool   _isTgaRegistered() => _medicine?['tga_registered'] == true;

  String _dbField(String key) {
    final v = _medicine?[key]?.toString() ?? '';
    return v.trim();
  }

  String _fieldSource(String key) {
    final sources = _medicine?['field_sources'];
    if (sources is Map && sources[key] != null) {
      return sources[key].toString();
    }
    return _dbField(key).isEmpty ? 'unavailable' : 'database';
  }

  String _provenanceLabelFor(String key) {
    final src = _fieldSource(key);
    if (src == 'database') return kDbProvenanceLabel;
    return kUnavailableLabel;
  }

  String _dosageText() {
    final std = _dbField('standard_dosage');
    if (std.isNotEmpty) return std;
    // Do not fall back to an AI-invented 'dosage' key.
    return '';
  }

  Color _scheduleColor(String schedule, ColorScheme cs, HealthcareColors hc) {
    switch (schedule.toUpperCase()) {
      case 'S2':  return hc.vitaGood;
      case 'S3':  return hc.prescription;
      case 'S4':  return hc.vitaWarning;
      case 'S8':  return hc.vitaCritical;
      default:    return cs.onSurfaceVariant;
    }
  }

  Future<void> _addToReminders() async {
    setState(() => _addingReminder = true);
    await Future.delayed(const Duration(milliseconds: 300));
    setState(() => _addingReminder = false);
    if (!mounted) return;
    context.go('/home/reminders/add');
  }

  Future<void> _loadAlternatives() async {
    final id = int.tryParse(widget.medicineId);
    if (id == null) return;
    setState(() => _loadingAlternatives = true);
    try {
      final resp = await ApiClient.get('/medicines/$id/alternatives');
      setState(() => _alternatives =
          Map<String, dynamic>.from(resp.data as Map));
    } catch (e) {
      if (mounted) ErrorHandler.show(context, e);
    } finally {
      if (mounted) setState(() => _loadingAlternatives = false);
    }
  }

  Future<void> _checkAllergy() async {
    final id = int.tryParse(widget.medicineId);
    if (id == null) return;
    setState(() => _loadingAllergyCheck = true);
    try {
      final resp = await ApiClient.get('/medicines/$id/allergy-check');
      setState(() => _allergyCheck =
          Map<String, dynamic>.from(resp.data as Map));
    } catch (e) {
      if (mounted) ErrorHandler.show(context, e);
    } finally {
      if (mounted) setState(() => _loadingAllergyCheck = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_medicineName()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home/medicines');
            }
          },
        ),
        actions: [
          if (!_loading && _medicine != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: _loadById,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? _buildError()
              : _buildContent(),
      bottomNavigationBar: (!_loading && _medicine != null)
          ? _buildBottomBar()
          : null,
    );
  }

  Widget _buildError() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: cs.error, size: 56),
            const SizedBox(height: 16),
            Text(
              _error,
              style: TextStyle(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _loadById,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final cs       = Theme.of(context).colorScheme;
    final hc       = HealthcareColors.of(context);
    final medicine = _medicine!;
    final schedule = _getSchedule();
    final tga      = _isTgaRegistered();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        const ClinicalSafetyBanner(
          kind: ClinicalDisclaimerKind.medicine,
          rounded: true,
          padding: EdgeInsets.all(12),
        ),
        const SizedBox(height: 12),
        // ── Header card ────────────────────────────────────────────────────────
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
                        color: cs.primaryContainer.withValues(alpha: 0.50),
                        borderRadius: AppRadius.brMd,
                      ),
                      child: Icon(Icons.medication, color: cs.primary, size: 32),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            medicine['name']?.toString() ?? widget.medicineId,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: cs.onSurface,
                            ),
                          ),
                          if (medicine['generic_name']
                                  ?.toString()
                                  .isNotEmpty ==
                              true) ...[
                            const SizedBox(height: 4),
                            Text(
                              medicine['generic_name'].toString(),
                              style: TextStyle(
                                  color: cs.onSurfaceVariant, fontSize: 14),
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
                                  color: hc.vitaGood,
                                  icon: Icons.verified,
                                ),
                              if (schedule.isNotEmpty)
                                _Badge(
                                  label: schedule,
                                  color: _scheduleColor(schedule, cs, hc),
                                  icon: Icons.label,
                                ),
                              if (medicine['drug_class']
                                      ?.toString()
                                      .isNotEmpty ==
                                  true)
                                _Badge(
                                  label: medicine['drug_class'].toString(),
                                  color: cs.secondary,
                                  icon: Icons.category,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (medicine['manufacturer']
                        ?.toString()
                        .isNotEmpty ==
                    true) ...[
                  const Divider(height: 24),
                  Row(
                    children: [
                      Icon(Icons.business, size: 14, color: cs.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          medicine['manufacturer'].toString(),
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        _UsesTile(
          medicine: medicine,
          provenanceLabel: _provenanceLabelFor(
            _dbField('uses').isNotEmpty
                ? 'uses'
                : (_dbField('consumer_information').isNotEmpty
                    ? 'consumer_information'
                    : 'uses'),
          ),
        ),
        _SectionTile(
          title: 'Composition',
          icon: Icons.science,
          content: _dbField('composition'),
          provenanceLabel: _provenanceLabelFor('composition'),
          initiallyExpanded: true,
        ),
        _SectionTile(
          title: 'Dosage',
          icon: Icons.schedule,
          content: _dosageText(),
          provenanceLabel: _provenanceLabelFor('standard_dosage'),
          initiallyExpanded: true,
        ),
        _SectionTile(
          title: 'Side Effects',
          icon: Icons.warning_amber,
          iconColor: hc.vitaWarning,
          content: _dbField('side_effects'),
          provenanceLabel: _provenanceLabelFor('side_effects'),
        ),
        _SectionTile(
          title: 'Drug Interactions',
          icon: Icons.compare_arrows,
          iconColor: cs.secondary,
          content: _dbField('interactions'),
          provenanceLabel: _provenanceLabelFor('interactions'),
        ),
        _SectionTile(
          title: 'Contraindications',
          icon: Icons.block,
          iconColor: cs.error,
          content: _dbField('contraindications'),
          provenanceLabel: _provenanceLabelFor('contraindications'),
        ),
        _SectionTile(
          title: 'Warnings & Precautions',
          icon: Icons.info_outline,
          iconColor: hc.aiAccent,
          content: _dbField('warnings'),
          provenanceLabel: _provenanceLabelFor('warnings'),
        ),

        if (_dbField('storage').isNotEmpty) ...[
          const SizedBox(height: 4),
          _SectionTile(
            title: 'Storage Instructions',
            icon: Icons.inventory_2,
            content: _dbField('storage'),
            provenanceLabel: _provenanceLabelFor('storage'),
          ),
        ],

        // AI explanation is separate — never merged into structured DB fields.
        if (_explanation != null) ...[
          const SizedBox(height: 8),
          _AiExplanationCard(explanation: _explanation!),
        ],

        if (_dbField('pregnancy_category').isNotEmpty) ...[
          const SizedBox(height: 4),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.child_care, color: cs.primary, size: 22),
                  const SizedBox(width: 10),
                  const Text(
                    'Pregnancy Category:',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _dbField('pregnancy_category'),
                    style: TextStyle(
                      color: cs.secondary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              kDbProvenanceLabel,
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],

        // ── Action buttons ─────────────────────────────────────────────────────
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _loadingAllergyCheck ? null : _checkAllergy,
                icon: _loadingAllergyCheck
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child:
                            CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.health_and_safety, size: 18),
                label: const Text('Check My Allergy',
                    style: TextStyle(fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: const RoundedRectangleBorder(
                      borderRadius: AppRadius.brSm),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _loadingAlternatives ? null : _loadAlternatives,
                icon: _loadingAlternatives
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child:
                            CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.swap_horiz, size: 18),
                label: const Text('Alternatives',
                    style: TextStyle(fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: const RoundedRectangleBorder(
                      borderRadius: AppRadius.brSm),
                ),
              ),
            ),
          ],
        ),

        // ── Allergy check result ───────────────────────────────────────────────
        if (_allergyCheck != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _allergyCheck!['safe'] == true
                  ? hc.vitaGood.withValues(alpha: 0.12)
                  : cs.errorContainer,
              borderRadius: AppRadius.brMd,
              border: Border.all(
                color: _allergyCheck!['safe'] == true
                    ? hc.vitaGood.withValues(alpha: 0.4)
                    : cs.error.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _allergyCheck!['safe'] == true
                          ? Icons.check_circle
                          : Icons.warning,
                      color: _allergyCheck!['safe'] == true
                          ? hc.vitaGood
                          : cs.error,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _allergyCheck!['safe'] == true
                          ? 'No allergy conflicts found'
                          : 'Allergy Alert!',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _allergyCheck!['safe'] == true
                            ? hc.vitaGood
                            : hc.vitaCritical,
                      ),
                    ),
                  ],
                ),
                if (_allergyCheck!['summary'] != null) ...[
                  const SizedBox(height: 6),
                  Text(_allergyCheck!['summary'],
                      style: const TextStyle(fontSize: 12)),
                ],
              ],
            ),
          ),
        ],

        // ── Alternatives result ────────────────────────────────────────────────
        if (_alternatives != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.25),
              borderRadius: AppRadius.brMd,
              border: Border.all(color: hc.aiAccent.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.swap_horiz, color: hc.aiAccent, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Generic & Alternatives',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: hc.aiAccent,
                      ),
                    ),
                  ],
                ),
                if (_alternatives!['generic_equivalent'] != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Generic: ${_alternatives!['generic_equivalent']}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ],
                if (_alternatives!['cost_saving_tip'] != null) ...[
                  const SizedBox(height: 4),
                  Builder(builder: (context) {
                    return Text(
                      _alternatives!['cost_saving_tip'],
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant,
                      ),
                    );
                  }),
                ],
                if ((_alternatives!['alternatives'] as List? ?? [])
                    .isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...(_alternatives!['alternatives'] as List).map((a) =>
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Builder(builder: (context) {
                          final innerCs = Theme.of(context).colorScheme;
                          final innerHc = HealthcareColors.of(context);
                          return Row(
                            children: [
                              Icon(
                                a['pbs_listed'] == true
                                    ? Icons.verified
                                    : Icons.circle,
                                color: innerCs.primary,
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${a['name']} (${a['type']})',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              if (a['pbs_listed'] == true)
                                Text(
                                  'PBS',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: innerHc.vitaGood,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                            ],
                          );
                        }),
                      )),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBottomBar() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: cs.surface,
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
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

// ── Uses tile ─────────────────────────────────────────────────────────────────

class _UsesTile extends StatelessWidget {
  final Map<String, dynamic> medicine;
  final String provenanceLabel;
  const _UsesTile({
    required this.medicine,
    required this.provenanceLabel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final rawUses      = medicine['uses']?.toString().trim() ?? '';
    final consumerInfo = medicine['consumer_information']?.toString().trim() ?? '';
    final drugClass    = medicine['drug_class']?.toString().trim() ?? '';
    final hasContent   = rawUses.isNotEmpty || consumerInfo.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding:     const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.1),
              borderRadius: AppRadius.brSm,
            ),
            child: Icon(Icons.healing, color: cs.primary, size: 18),
          ),
          title: Text(
            'Uses',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: cs.onSurface,
            ),
          ),
          subtitle: Text(
            provenanceLabel,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
          ),
          children: [
            if (!hasContent)
              Text(
                kUnavailableLabel,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 14,
                  height: 1.6,
                ),
              )
            else
              _UsesContent(
                uses: rawUses,
                consumerInfo: consumerInfo,
                drugClass: drugClass,
              ),
          ],
        ),
      ),
    );
  }
}

class _UsesContent extends StatelessWidget {
  final String uses;
  final String consumerInfo;
  final String drugClass;
  const _UsesContent({
    required this.uses,
    required this.consumerInfo,
    required this.drugClass,
  });

  static List<String> _parseBullets(String text) {
    final byNewline = text
        .split('\n')
        .map((e) => e.replaceAll(RegExp(r'^[\s•\-*]+'), '').trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (byNewline.length > 1) return byNewline;
    final bySemicolon = text
        .split(';')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (bySemicolon.length > 1) return bySemicolon;
    return [text];
  }

  @override
  Widget build(BuildContext context) {
    final cs      = Theme.of(context).colorScheme;
    final bullets = uses.isEmpty ? <String>[] : _parseBullets(uses);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Primary Uses ──────────────────────────────────────────────────────
        if (bullets.isNotEmpty) ...[
          _UsesSubhead(label: 'Primary Uses', color: cs.primary),
          const SizedBox(height: 8),
          ...bullets.map(
            (b) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7, right: 10),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      b,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

        // ── How this medicine helps ───────────────────────────────────────────
        if (consumerInfo.isNotEmpty) ...[
          if (bullets.isNotEmpty) const SizedBox(height: 10),
          _UsesSubhead(label: 'How this medicine helps', color: cs.primary),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.25),
              borderRadius: AppRadius.brSm,
            ),
            child: Text(
              consumerInfo,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 13,
                height: 1.55,
              ),
            ),
          ),
        ],

        // ── Medical Specialty ─────────────────────────────────────────────────
        if (drugClass.isNotEmpty) ...[
          const SizedBox(height: 12),
          _UsesSubhead(label: 'Medical Specialty', color: cs.primary),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: cs.secondaryContainer,
              borderRadius: AppRadius.brFull,
            ),
            child: Text(
              drugClass,
              style: TextStyle(
                color: cs.onSecondaryContainer,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _UsesSubhead extends StatelessWidget {
  final String label;
  final Color  color;
  const _UsesSubhead({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.3,
        ),
      );
}

// ── Section tile ──────────────────────────────────────────────────────────────

class _SectionTile extends StatelessWidget {
  final String   title;
  final IconData icon;
  final Color?   iconColor;
  final String   content;
  final String   provenanceLabel;
  final bool     initiallyExpanded;

  const _SectionTile({
    required this.title,
    required this.icon,
    this.iconColor,
    required this.content,
    required this.provenanceLabel,
    this.initiallyExpanded = false,
  });

  static String _clean(String text) {
    String s = text
        .replaceAll(RegExp(r'\(\s*\d[\d\s,./]*\)'), '')
        .replaceAll(RegExp(r'\[\s*\d[\d\s,]*\]'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
    if (s.isNotEmpty) s = s[0].toUpperCase() + s.substring(1);
    return s;
  }

  static List<String> _toBullets(String text) {
    final byNewline = text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (byNewline.length > 1) return byNewline;

    final bySentence = text
        .split(RegExp(r'(?<=[.!?])\s+(?=[A-Z])'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (bySentence.length >= 3) return bySentence;

    final bySemicolon = text
        .split(';')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (bySemicolon.length > 1) return bySemicolon;

    return [text];
  }

  @override
  Widget build(BuildContext context) {
    final cs             = Theme.of(context).colorScheme;
    final raw            = content.trim();
    final effectiveColor = iconColor ?? cs.primary;

    final cleaned = raw.isEmpty ? '' : _clean(raw);
    final bullets = cleaned.isEmpty ? <String>[] : _toBullets(cleaned);
    final isNA    = cleaned.isEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding:
              const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: effectiveColor.withValues(alpha: 0.1),
              borderRadius: AppRadius.brSm,
            ),
            child: Icon(icon, color: effectiveColor, size: 18),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: cs.onSurface,
            ),
          ),
          subtitle: Text(
            isNA ? kUnavailableLabel : provenanceLabel,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
          ),
          children: [
            if (isNA)
              Text(
                kUnavailableLabel,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 14,
                  height: 1.6,
                ),
              )
            else if (bullets.length > 1)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: bullets
                    .map((item) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                    top: 7, right: 10),
                                child: Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: effectiveColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  item,
                                  style: TextStyle(
                                    color: cs.onSurfaceVariant,
                                    fontSize: 14,
                                    height: 1.55,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
              )
            else
              Text(
                cleaned,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
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

/// Separate AI explanation block — never presented as structured DB clinical fields.
class _AiExplanationCard extends StatelessWidget {
  final Map<String, dynamic> explanation;
  const _AiExplanationCard({required this.explanation});

  static const _sectionKeys = <String, String>{
    'what_it_is': 'What it is',
    'what_it_is_used_for': 'What it is used for',
    'how_it_works': 'How it works',
    'important_information': 'Important information',
    'common_side_effects': 'Side effects (explained)',
    'warnings': 'Warnings (explained)',
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = <Widget>[];

    for (final entry in _sectionKeys.entries) {
      final sec = explanation[entry.key];
      if (sec is! Map) continue;
      final available = sec['available'] == true;
      final text = sec['text']?.toString().trim() ?? '';
      final source = sec['source']?.toString() ?? 'unavailable';
      if (!available || text.isEmpty) continue;
      // Only show AI-rephrased sections here; DB-only identity stays in structured tiles.
      if (source != 'ai_rephrased_from_database' &&
          source != 'ai_explanation') {
        continue;
      }
      items.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.value,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                text,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: cs.secondaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 18, color: cs.secondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    kAiProvenanceLabel,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Explains catalogue facts only — not a substitute for product information or professional advice.',
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            ...items,
          ],
        ),
      ),
    );
  }
}

// ── Badge pill ────────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final String   label;
  final Color    color;
  final IconData icon;

  const _Badge(
      {required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: AppRadius.brFull,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
