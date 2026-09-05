import 'package:flutter/material.dart';
import 'package:vitapulse_ai/core/utils/error_handler.dart';
import 'package:vitapulse_ai/features/legal/legal_copy.dart';
import 'package:vitapulse_ai/features/symptoms/data/symptoms_api.dart';
import 'package:vitapulse_ai/shared/widgets/clinical_safety_banner.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';

class SymptomCheckerScreen extends StatefulWidget {
  const SymptomCheckerScreen({super.key});

  @override
  State<SymptomCheckerScreen> createState() => _SymptomCheckerScreenState();
}

class _SymptomCheckerScreenState extends State<SymptomCheckerScreen> {
  final _controller = TextEditingController();
  final _durationController = TextEditingController();
  final List<String> _symptoms = [];
  Map<String, dynamic>? _result;
  bool _loading = false;

  static const _quickSymptoms = [
    'Headache', 'Fever', 'Cough', 'Fatigue', 'Nausea',
    'Chest pain', 'Shortness of breath', 'Dizziness', 'Rash', 'Back pain',
  ];

  void _addSymptom(String name) {
    final s = name.trim();
    if (s.isEmpty || _symptoms.contains(s)) return;
    setState(() => _symptoms.add(s));
  }

  Future<void> _check() async {
    if (_symptoms.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one symptom to check')),
      );
      return;
    }
    setState(() { _loading = true; _result = null; });
    try {
      final result = await SymptomsApi.checkSymptoms(
        _symptoms,
        duration: _durationController.text.trim().isEmpty
            ? null
            : _durationController.text.trim(),
      );
      setState(() => _result = result);
    } catch (e) {
      if (mounted) ErrorHandler.show(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _urgencyColor(String? urgency, ColorScheme cs, HealthcareColors hc) {
    switch (urgency?.toLowerCase()) {
      case 'emergency': return hc.vitaCritical;
      case 'urgent':    return hc.vitaWarning;
      case 'soon':      return cs.secondary;
      case 'routine':   return cs.secondary;
      case 'not_needed': return hc.vitaGood;
      default:          return cs.onSurfaceVariant;
    }
  }

  IconData _urgencyIcon(String? urgency) {
    switch (urgency?.toLowerCase()) {
      case 'emergency': return Icons.emergency;
      case 'urgent':    return Icons.warning;
      case 'soon':      return Icons.schedule;
      case 'routine':   return Icons.calendar_today;
      case 'not_needed': return Icons.check_circle;
      default:          return Icons.help_outline;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _durationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('AI Symptom Checker'),
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ClinicalSafetyBanner(
              kind: ClinicalDisclaimerKind.symptom,
              rounded: true,
              padding: EdgeInsets.all(12),
            ),
            const SizedBox(height: 16),
            const Text('Quick Select',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8, runSpacing: 6,
              children: _quickSymptoms.map((s) => ActionChip(
                label: Text(s, style: const TextStyle(fontSize: 12)),
                onPressed: () => _addSymptom(s),
                backgroundColor: _symptoms.contains(s)
                    ? cs.primary.withValues(alpha: 0.15)
                    : Colors.white,
                side: BorderSide(
                    color: _symptoms.contains(s) ? cs.primary : cs.outline),
              )).toList(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'Type another symptom...',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                          borderRadius: AppRadius.brMd,
                          borderSide: BorderSide(color: cs.outline)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: AppRadius.brMd,
                          borderSide: BorderSide(color: cs.outline)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                    onSubmitted: (v) {
                      _addSymptom(v);
                      _controller.clear();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    _addSymptom(_controller.text);
                    _controller.clear();
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                  ),
                  child: const Icon(Icons.add, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _durationController,
              decoration: InputDecoration(
                hintText:
                    'How long? (e.g. "2 days", "1 week") — optional',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                    borderRadius: AppRadius.brMd,
                    borderSide: BorderSide(color: cs.outline)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: AppRadius.brMd,
                    borderSide: BorderSide(color: cs.outline)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
              ),
            ),
            if (_symptoms.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8, runSpacing: 6,
                children: _symptoms.map((s) => Chip(
                  label: Text(s),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () => setState(() => _symptoms.remove(s)),
                  backgroundColor: cs.primary.withValues(alpha: 0.1),
                  labelStyle: TextStyle(color: cs.primary, fontSize: 13),
                )).toList(),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _check,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.medical_services),
                label: Text(_loading ? 'Analysing...' : 'Check Symptoms'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            if (_result != null) ...[
              const SizedBox(height: 20),
              _buildResults(cs, hc),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResults(ColorScheme cs, HealthcareColors hc) {
    final triage = _result!['triage'] as Map<String, dynamic>? ?? {};
    final consultation =
        _result!['consultation_advice'] as Map<String, dynamic>?;
    final urgency = triage['urgency'] as String?;
    final conditions =
        (triage['possible_conditions'] as List?)
            ?.cast<Map<String, dynamic>>() ??
            [];
    final recommendations =
        (triage['recommendations'] as List?)?.cast<String>() ?? [];
    final redFlags =
        (triage['red_flags'] as List?)?.cast<String>() ?? [];
    final selfCare =
        (triage['self_care'] as List?)?.cast<String>() ?? [];

    final uColor = _urgencyColor(urgency, cs, hc);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Urgency card
        if (triage['call_000'] == true)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: hc.vitaCritical,
              borderRadius: AppRadius.brLg,
            ),
            child: const Row(
              children: [
                Icon(Icons.emergency, color: Colors.white, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('CALL 000 NOW',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18)),
                      Text('This may be a medical emergency',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: uColor.withValues(alpha: 0.1),
              borderRadius: AppRadius.brLg,
              border:
                  Border.all(color: uColor.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(_urgencyIcon(urgency), color: uColor, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        triage['urgency_label'] ??
                            (urgency ?? 'Unknown').toUpperCase(),
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: uColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),

        // Red flags
        if (redFlags.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.error.withValues(alpha: 0.07),
              borderRadius: AppRadius.brMd,
              border: Border.all(color: cs.error.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.flag, color: cs.error, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Warning Signs — Seek Immediate Help If:',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: cs.error,
                        fontSize: 13),
                  ),
                ]),
                const SizedBox(height: 6),
                ...redFlags.map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• $f',
                          style: const TextStyle(fontSize: 12)),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Possible conditions
        if (conditions.isNotEmpty) ...[
          const Text('Possible Conditions',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          ...conditions.map((c) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: AppRadius.brMd,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 4)
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Text(c['name'] ?? '',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14))),
                      _LikelihoodBadge(likelihood: c['likelihood']),
                    ]),
                    if (c['description'] != null) ...[
                      const SizedBox(height: 4),
                      Text(c['description'],
                          style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant)),
                    ],
                  ],
                ),
              )),
          const SizedBox(height: 8),
        ],

        // Recommendations
        if (recommendations.isNotEmpty) ...[
          const Text('Recommendations',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 6),
          ...recommendations.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.arrow_right, color: cs.primary, size: 20),
                      const SizedBox(width: 4),
                      Expanded(
                          child: Text(r,
                              style: const TextStyle(fontSize: 13))),
                    ]),
              )),
          const SizedBox(height: 8),
        ],

        // Self-care tips
        if (selfCare.isNotEmpty) ...[
          const Text('Self-Care Tips',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 6),
          ...selfCare.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.spa, color: hc.vitaGood, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(t,
                              style: const TextStyle(fontSize: 13))),
                    ]),
              )),
          const SizedBox(height: 8),
        ],

        // Doctor consultation advice
        if (consultation != null &&
            consultation['consult_needed'] == true) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.08),
              borderRadius: AppRadius.brMd,
              border: Border.all(
                  color: cs.secondary.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.local_hospital,
                      color: cs.secondary, size: 18),
                  const SizedBox(width: 6),
                  Text('See a Doctor',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: cs.secondary)),
                ]),
                const SizedBox(height: 6),
                Text(consultation['urgency_label'] ?? '',
                    style: const TextStyle(fontSize: 13)),
                if (consultation['suggested_specialist'] != null)
                  Text(
                    'Suggested: ${consultation['suggested_specialist']}',
                    style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 12),
        // Prefer API note when present; otherwise shared non-diagnostic copy.
        // Do not re-render the top ClinicalSafetyBanner here (no stacking).
        Text(
          (triage['disclaimer']?.toString().trim().isNotEmpty == true)
              ? triage['disclaimer'].toString()
              : LegalCopy.symptomProfessionalNote,
          style: TextStyle(
              fontSize: 11,
              color: cs.onSurfaceVariant,
              fontStyle: FontStyle.italic),
        ),
      ],
    );
  }
}

class _LikelihoodBadge extends StatelessWidget {
  final String? likelihood;
  const _LikelihoodBadge({this.likelihood});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);
    final Color c;
    switch (likelihood?.toLowerCase()) {
      case 'high':   c = hc.vitaWarning; break;
      case 'medium': c = cs.secondary;   break;
      default:       c = hc.vitaGood;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.15),
          borderRadius: AppRadius.brFull),
      child: Text(
        (likelihood ?? 'low').toUpperCase(),
        style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: c),
      ),
    );
  }
}
