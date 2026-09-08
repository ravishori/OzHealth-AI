/// HN-PROF-006 — lifestyle preference keys and helpers.
///
/// Preferences are user-provided profile fields, not medical diagnoses or
/// clinical advice. Stored server-side as an encrypted JSON object.
class LifestylePreferences {
  LifestylePreferences._();

  static const List<String> keys = [
    'diet',
    'exercise',
    'sleep',
    'smoking',
    'alcohol',
  ];

  static const Map<String, String> labels = {
    'diet': 'Diet',
    'exercise': 'Exercise',
    'sleep': 'Sleep',
    'smoking': 'Smoking',
    'alcohol': 'Alcohol',
  };

  static const Map<String, String> hints = {
    'diet': 'e.g. Vegetarian, Balanced',
    'exercise': 'e.g. Walking 3x week',
    'sleep': 'e.g. 7–8 hours',
    'smoking': 'e.g. Non-smoker',
    'alcohol': 'e.g. None',
  };

  /// Parse API value into a string map. Never returns null entries.
  static Map<String, String> fromApi(dynamic raw) {
    if (raw == null) return {};
    if (raw is! Map) return {};
    final out = <String, String>{};
    raw.forEach((key, value) {
      if (key == null) return;
      final k = key.toString().trim();
      if (k.isEmpty) return;
      if (value == null) return;
      final v = value.toString().trim();
      if (v.isEmpty) return;
      // Avoid leaking framework noise into UI.
      if (v == 'null' || v == 'undefined' || v.startsWith('[object')) return;
      out[k] = v;
    });
    return out;
  }

  /// Build PUT payload object (empty object clears stored preferences).
  static Map<String, String> toApi(Map<String, String> draft) {
    final out = <String, String>{};
    for (final entry in draft.entries) {
      final k = entry.key.trim();
      final v = entry.value.trim();
      if (k.isEmpty || v.isEmpty) continue;
      if (v.length > 200) {
        throw const FormatException('Preference text is too long');
      }
      out[k] = v;
    }
    return out;
  }

  static String summary(Map<String, String> prefs) {
    if (prefs.isEmpty) return '';
    final parts = <String>[];
    for (final key in keys) {
      final v = prefs[key];
      if (v != null && v.isNotEmpty) {
        parts.add('${labels[key] ?? key}: $v');
      }
    }
    for (final entry in prefs.entries) {
      if (keys.contains(entry.key)) continue;
      parts.add('${entry.key}: ${entry.value}');
    }
    return parts.join(' · ');
  }
}
