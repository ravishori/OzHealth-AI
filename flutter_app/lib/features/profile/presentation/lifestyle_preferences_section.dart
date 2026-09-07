import 'package:flutter/material.dart';
import 'package:vitapulse_ai/features/profile/data/lifestyle_preferences.dart';
import 'package:vitapulse_ai/shared/widgets/loading_button.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';

/// HN-PROF-006 — Profile card + editor for existing lifestyle preferences.
class LifestylePreferencesSection extends StatelessWidget {
  final Map<String, String> values;
  final bool saving;
  final Future<bool> Function(Map<String, String> next) onSave;

  const LifestylePreferencesSection({
    super.key,
    required this.values,
    required this.saving,
    required this.onSave,
  });

  Future<void> _openEditor(BuildContext context) async {
    if (saving) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => LifestylePreferencesEditorSheet(
        initial: values,
        onSave: onSave,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);
    final color = hc.discharge;
    final rows = _displayRows();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.self_improvement_outlined, size: 18, color: color),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Lifestyle preferences',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                if (saving)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    key: const Key('lifestyle-edit'),
                    icon: Icon(Icons.edit_outlined, size: 20, color: color),
                    tooltip: 'Edit Lifestyle preferences',
                    onPressed: () => _openEditor(context),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              GestureDetector(
                onTap: saving ? null : () => _openEditor(context),
                child: Text(
                  'Tap edit to add lifestyle preferences',
                  style: TextStyle(
                    color: color.withValues(alpha: 0.6),
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else
              ...rows.expand((w) => [w, const SizedBox(height: 10)]).toList()
                ..removeLast(),
            if (rows.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'These are personal preferences, not medical advice.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _displayRows() {
    final keys = <String>[
      ...LifestylePreferencesCodec.knownKeys
          .where((k) => values[k]?.trim().isNotEmpty == true),
      ...values.keys
          .where((k) => !LifestylePreferencesCodec.knownKeys.contains(k))
          .toList()
        ..sort(),
    ];
    return [
      for (final key in keys)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 88,
              child: Text(
                '${LifestylePreferencesCodec.labelFor(key)}:',
                style: const TextStyle(fontSize: 14),
              ),
            ),
            Expanded(
              child: Text(
                values[key] ?? '',
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
    ];
  }
}

class LifestylePreferencesEditorSheet extends StatefulWidget {
  final Map<String, String> initial;
  final Future<bool> Function(Map<String, String> next) onSave;

  const LifestylePreferencesEditorSheet({
    super.key,
    required this.initial,
    required this.onSave,
  });

  @override
  State<LifestylePreferencesEditorSheet> createState() =>
      _LifestylePreferencesEditorSheetState();
}

class _LifestylePreferencesEditorSheetState
    extends State<LifestylePreferencesEditorSheet> {
  late final Map<String, TextEditingController> _controllers;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _controllers = {};
    for (final key in LifestylePreferencesCodec.knownKeys) {
      _controllers[key] = TextEditingController(text: widget.initial[key] ?? '');
    }
    final extras = widget.initial.keys
        .where((k) => !LifestylePreferencesCodec.knownKeys.contains(k))
        .toList()
      ..sort();
    for (final key in extras) {
      _controllers[key] = TextEditingController(text: widget.initial[key] ?? '');
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String> _collect() {
    return {
      for (final e in _controllers.entries) e.key: e.value.text,
    };
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final ok = await widget.onSave(_collect());
      if (ok && mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.self_improvement_outlined, color: hc.discharge),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Lifestyle preferences',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Optional personal preferences stored on your profile.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 16),
            for (final key in _controllers.keys) ...[
              TextField(
                key: Key('lifestyle-field-$key'),
                controller: _controllers[key],
                enabled: !_submitting,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: LifestylePreferencesCodec.labelFor(key),
                  hintText: LifestylePreferencesCodec.hintFor(key),
                  hintStyle:
                      TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
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
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _submitting ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LoadingButton(
                    key: const Key('lifestyle-save'),
                    text: 'Save',
                    loading: _submitting,
                    onPressed: _submit,
                    height: 48,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
