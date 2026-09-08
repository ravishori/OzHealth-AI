import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vitapulse_ai/core/utils/error_handler.dart';
import 'package:vitapulse_ai/features/legal/legal_copy.dart';
import 'package:vitapulse_ai/features/symptoms/data/symptoms_api.dart';
import 'package:vitapulse_ai/shared/widgets/clinical_safety_banner.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';

/// HN-FUTURE-001 — informational symptom guidance (not a diagnosis).
class SymptomCheckerScreen extends StatefulWidget {
  final Future<Map<String, dynamic>> Function(
    List<String> symptoms, {
    String? duration,
  })? checkSymptoms;
  final Future<bool> Function(Uri uri)? launchUri;
  final void Function(String path)? openRoute;

  const SymptomCheckerScreen({
    super.key,
    this.checkSymptoms,
    this.launchUri,
    this.openRoute,
  });

  @override
  State<SymptomCheckerScreen> createState() => _SymptomCheckerScreenState();
}

class _SymptomCheckerScreenState extends State<SymptomCheckerScreen> {
  final _controller = TextEditingController();
  final _durationController = TextEditingController();
  final List<String> _symptoms = [];
  Map<String, dynamic>? _result;
  bool _loading = false;
  String? _error;

  static const _quickSymptoms = [
    'Headache',
    'Fever',
    'Cough',
    'Fatigue',
    'Nausea',
    'Chest pain',
    'Shortness of breath',
    'Dizziness',
    'Rash',
    'Back pain',
  ];

  void _addSymptom(String name) {
    final s = name.trim();
    if (s.isEmpty || _symptoms.contains(s)) return;
    setState(() {
      _symptoms.add(s);
      _error = null;
    });
  }

  Future<void> _check() async {
    if (_loading) return;
    if (_symptoms.isEmpty) {
      setState(() => _error = 'Add at least one symptom to continue');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one symptom to continue')),
      );
      return;
    }
    // Reject whitespace-only duration is fine (optional); symptoms already trimmed.
    setState(() {
      _loading = true;
      _result = null;
      _error = null;
    });
    try {
      final checker = widget.checkSymptoms ??
          (List<String> symptoms, {String? duration}) =>
              SymptomsApi.checkSymptoms(symptoms, duration: duration);
      final result = await checker(
        List<String>.from(_symptoms),
        duration: _durationController.text.trim().isEmpty
            ? null
            : _durationController.text.trim(),
      );
      if (!mounted) return;
      setState(() => _result = result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load guidance. Please try again.';
        _result = null;
      });
      ErrorHandler.show(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _dial000() async {
    final uri = Uri(scheme: 'tel', path: '000');
    final launcher = widget.launchUri ??
        (Uri u) async {
          if (await canLaunchUrl(u)) {
            return launchUrl(u);
          }
          return false;
        };
    final ok = await launcher(uri);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot open the phone dialler')),
      );
    }
  }

  void _openEmergency() {
    final open = widget.openRoute ??
        (String path) {
          context.push(path);
        };
    open('/home/emergency');
  }

  Color _urgencyColor(String? urgency, ColorScheme cs, HealthcareColors hc) {
    switch (urgency?.toLowerCase()) {
      case 'emergency':
        return hc.vitaCritical;
      case 'urgent':
        return hc.vitaWarning;
      case 'soon':
        return cs.secondary;
      case 'routine':
        return cs.secondary;
      case 'not_needed':
        return hc.vitaGood;
      default:
        return cs.onSurfaceVariant;
    }
  }

  IconData _urgencyIcon(String? urgency) {
    switch (urgency?.toLowerCase()) {
      case 'emergency':
        return Icons.emergency;
      case 'urgent':
        return Icons.warning;
      case 'soon':
        return Icons.schedule;
      case 'routine':
        return Icons.calendar_today;
      case 'not_needed':
        return Icons.check_circle;
      default:
        return Icons.help_outline;
    }
  }

  List<Map<String, dynamic>> _asMapList(dynamic raw) {
    if (raw is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is Map) {
        out.add(Map<String, dynamic>.from(item));
      }
    }
    return out;
  }

  List<String> _asStringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).toList();
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
      key: const Key('symptom_checker_screen'),
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Symptom Information'),
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ClinicalSafetyBanner(
              key: Key('symptom_safety_banner'),
              kind: ClinicalDisclaimerKind.symptom,
              rounded: true,
              padding: EdgeInsets.all(12),
            ),
            const SizedBox(height: 12),
            Text(
              'Describe how you feel to get general health information and '
              'when-to-seek-care guidance. This is not a diagnosis.',
              key: const Key('symptom_purpose_copy'),
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
            const Text('Quick Select',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _quickSymptoms
                  .map(
                    (s) => ActionChip(
                      label: Text(s, style: const TextStyle(fontSize: 12)),
                      onPressed: _loading ? null : () => _addSymptom(s),
                      backgroundColor: _symptoms.contains(s)
                          ? cs.primary.withValues(alpha: 0.15)
                          : Colors.white,
                      side: BorderSide(
                        color:
                            _symptoms.contains(s) ? cs.primary : cs.outline,
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('symptom_input_field'),
                    controller: _controller,
                    enabled: !_loading,
                    decoration: InputDecoration(
                      hintText: 'Type another symptom...',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: AppRadius.brMd,
                        borderSide: BorderSide(color: cs.outline),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: AppRadius.brMd,
                        borderSide: BorderSide(color: cs.outline),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (v) {
                      _addSymptom(v);
                      _controller.clear();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  key: const Key('symptom_add_button'),
                  onPressed: _loading
                      ? null
                      : () {
                          _addSymptom(_controller.text);
                          _controller.clear();
                        },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                  ),
                  child: const Icon(Icons.add, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('symptom_duration_field'),
              controller: _durationController,
              enabled: !_loading,
              decoration: InputDecoration(
                hintText:
                    'How long? (e.g. "2 days", "1 week") — optional',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: AppRadius.brMd,
                  borderSide: BorderSide(color: cs.outline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: AppRadius.brMd,
                  borderSide: BorderSide(color: cs.outline),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
            ),
            if (_symptoms.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: _symptoms
                    .map(
                      (s) => Chip(
                        label: Text(s),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: _loading
                            ? null
                            : () => setState(() => _symptoms.remove(s)),
                        backgroundColor:
                            cs.primary.withValues(alpha: 0.1),
                        labelStyle: TextStyle(
                          color: cs.primary,
                          fontSize: 13,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                key: const Key('symptom_submit_button'),
                onPressed: _loading ? null : _check,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.health_and_safety_outlined),
                label: Text(
                  _loading ? 'Getting guidance...' : 'Get guidance',
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            if (_loading) ...[
              const SizedBox(height: 16),
              const Center(
                key: Key('symptom_loading_state'),
                child: Text('Preparing general health information…'),
              ),
            ],
            if (_error != null && _result == null) ...[
              const SizedBox(height: 16),
              Container(
                key: const Key('symptom_error_state'),
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.errorContainer.withValues(alpha: 0.35),
                  borderRadius: AppRadius.brMd,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_error!, style: TextStyle(color: cs.error)),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      key: const Key('symptom_retry_button'),
                      onPressed: _loading ? null : _check,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            ],
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
    final triage = (_result!['triage'] is Map)
        ? Map<String, dynamic>.from(_result!['triage'] as Map)
        : <String, dynamic>{};
    final consultation = (_result!['consultation_advice'] is Map)
        ? Map<String, dynamic>.from(_result!['consultation_advice'] as Map)
        : null;
    final urgency = triage['urgency']?.toString();
    final conditions = _asMapList(triage['possible_conditions']);
    final recommendations = _asStringList(triage['recommendations']);
    final redFlags = _asStringList(triage['red_flags']);
    final selfCare = _asStringList(triage['self_care']);
    final call000 = triage['call_000'] == true;

    final uColor = _urgencyColor(urgency, cs, hc);

    return Column(
      key: const Key('symptom_result_panel'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (call000)
          Container(
            key: const Key('symptom_emergency_banner'),
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: hc.vitaCritical,
              borderRadius: AppRadius.brLg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.emergency, color: Colors.white, size: 28),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CALL 000 NOW',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          Text(
                            'This may be a medical emergency. '
                            'HealthNest does not contact emergency services for you.',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('symptom_call_000_button'),
                        onPressed: _dial000,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: hc.vitaCritical,
                        ),
                        icon: const Icon(Icons.phone),
                        label: const Text('Call 000'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        key: const Key('symptom_open_emergency_button'),
                        onPressed: _openEmergency,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white70),
                        ),
                        child: const Text('Emergency screen'),
                      ),
                    ),
                  ],
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
              border: Border.all(color: uColor.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(_urgencyIcon(urgency), color: uColor, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    triage['urgency_label']?.toString() ??
                        (urgency ?? 'Guidance').toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: uColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),

        if (redFlags.isNotEmpty) ...[
          Container(
            key: const Key('symptom_red_flags'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.error.withValues(alpha: 0.07),
              borderRadius: AppRadius.brMd,
              border: Border.all(color: cs.error.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.flag, color: cs.error, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      'When to seek urgent care',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: cs.error,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ...redFlags.map(
                  (f) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• $f', style: const TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        if (conditions.isNotEmpty) ...[
          const Text(
            'Possible considerations',
            key: Key('symptom_considerations_heading'),
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            'These are general topics for discussion with a clinician — '
            'not ranked diagnoses.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          ...conditions.map(
            (c) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: AppRadius.brMd,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          c['name']?.toString() ?? '',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      _ConsiderationTag(
                        likelihood: c['likelihood']?.toString(),
                      ),
                    ],
                  ),
                  if (c['description'] != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      c['description'].toString(),
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],

        if (recommendations.isNotEmpty) ...[
          const Text(
            'Suggested next steps',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 6),
          ...recommendations.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.arrow_right, color: cs.primary, size: 20),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(r, style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],

        if (selfCare.isNotEmpty) ...[
          const Text(
            'General self-care tips',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 6),
          ...selfCare.map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.spa, color: hc.vitaGood, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(t, style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],

        if (consultation != null &&
            consultation['consult_needed'] == true) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.08),
              borderRadius: AppRadius.brMd,
              border: Border.all(
                color: cs.secondary.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.local_hospital,
                        color: cs.secondary, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      'Consider seeing a clinician',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: cs.secondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  consultation['urgency_label']?.toString() ?? '',
                  style: const TextStyle(fontSize: 13),
                ),
                if (consultation['suggested_specialist'] != null)
                  Text(
                    'Suggested: ${consultation['suggested_specialist']}',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 12),
        Text(
          key: const Key('symptom_result_disclaimer'),
          (triage['disclaimer']?.toString().trim().isNotEmpty == true)
              ? triage['disclaimer'].toString()
              : LegalCopy.symptomProfessionalNote,
          style: TextStyle(
            fontSize: 11,
            color: cs.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

/// Soft relative tag — not a diagnostic certainty badge.
class _ConsiderationTag extends StatelessWidget {
  final String? likelihood;
  const _ConsiderationTag({this.likelihood});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = switch (likelihood?.toLowerCase()) {
      'high' => 'Often discussed',
      'medium' => 'Sometimes discussed',
      _ => 'Less often discussed',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: AppRadius.brFull,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}
