import 'package:flutter/material.dart';
import 'package:vitapulse_ai/features/profile/data/lifestyle_preferences.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';

/// HN-PROF-006 — display + edit lifestyle preferences (profile preferences only).
class LifestylePreferencesSection extends StatelessWidget {
  final Map<String, String> preferences;
  final VoidCallback onEdit;

  const LifestylePreferencesSection({
    super.key,
    required this.preferences,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final empty = preferences.isEmpty;

    return Card(
      key: const Key('lifestyle_preferences_section'),
      elevation: 0,
      color: cs.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.brLg,
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.self_improvement_outlined, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Lifestyle preferences',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('lifestyle_preferences_edit'),
                  tooltip: 'Edit lifestyle preferences',
                  icon: Icon(Icons.edit_outlined, size: 20, color: cs.primary),
                  onPressed: onEdit,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Your personal preferences — not a medical assessment.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            if (empty)
              GestureDetector(
                onTap: onEdit,
                child: Text(
                  'Tap edit to add lifestyle preferences',
                  key: const Key('lifestyle_preferences_empty'),
                  style: TextStyle(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else
              ...LifestylePreferences.keys
                  .where((k) => (preferences[k] ?? '').isNotEmpty)
                  .map(
                    (k) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 88,
                            child: Text(
                              LifestylePreferences.labels[k] ?? k,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              preferences[k]!,
                              key: Key('lifestyle_pref_value_$k'),
                              style: TextStyle(
                                fontSize: 13,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet editor — Cancel returns null; Save returns the map to PUT.
class LifestylePreferencesEditorSheet extends StatefulWidget {
  final Map<String, String> initial;

  const LifestylePreferencesEditorSheet({
    super.key,
    required this.initial,
  });

  @override
  State<LifestylePreferencesEditorSheet> createState() =>
      _LifestylePreferencesEditorSheetState();
}

class _LifestylePreferencesEditorSheetState
    extends State<LifestylePreferencesEditorSheet> {
  late final Map<String, TextEditingController> _controllers;
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final key in LifestylePreferences.keys)
        key: TextEditingController(text: widget.initial[key] ?? ''),
    };
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _onSave() {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final draft = <String, String>{
        for (final e in _controllers.entries) e.key: e.value.text,
      };
      final payload = LifestylePreferences.toApi(draft);
      if (!mounted) return;
      Navigator.of(context).pop(payload);
    } on FormatException catch (e) {
      setState(() {
        _saving = false;
        _error = e.message;
      });
    } catch (_) {
      setState(() {
        _saving = false;
        _error = 'Could not prepare preferences. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Text(
                  'Lifestyle preferences',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Optional profile preferences. Not medical advice or a diagnosis.',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                ...LifestylePreferences.keys.map((key) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextFormField(
                      key: Key('lifestyle_field_$key'),
                      controller: _controllers[key],
                      maxLength: 200,
                      decoration: InputDecoration(
                        labelText: LifestylePreferences.labels[key],
                        hintText: LifestylePreferences.hints[key],
                        counterText: '',
                      ),
                      validator: (v) {
                        if (v != null && v.trim().length > 200) {
                          return 'Keep under 200 characters';
                        }
                        return null;
                      },
                    ),
                  );
                }),
                if (_error != null) ...[
                  Text(_error!, style: TextStyle(color: cs.error, fontSize: 13)),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    TextButton(
                      key: const Key('lifestyle_cancel'),
                      onPressed: _saving ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const Spacer(),
                    FilledButton(
                      key: const Key('lifestyle_save'),
                      onPressed: _saving ? null : _onSave,
                      child: _saving
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cs.onPrimary,
                              ),
                            )
                          : const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
