/// HN-PROF-006 — codec for the existing `lifestyle_preferences` JSON object.
///
/// The backend stores an encrypted JSON object (not a list). Keys are
/// preference labels; values are user-supplied strings. This is a profile
/// data-management helper, not medical advice.
class LifestylePreferencesCodec {
  LifestylePreferencesCodec._();

  static const List<String> knownKeys = [
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
    'diet': 'e.g. Vegetarian, Halal, Gluten-free',
    'exercise': 'e.g. Walking 3x week',
    'sleep': 'e.g. 7-8 hours',
    'smoking': 'e.g. Non-smoker',
    'alcohol': 'e.g. None, Occasional',
  };

  static String labelFor(String key) {
    final known = labels[key];
    if (known != null) return known;
    return key.replaceAll('_', ' ');
  }

  static String hintFor(String key) => hints[key] ?? 'Optional preference';

  /// Parse GET `/users/me` `lifestyle_preferences` into display strings.
  static Map<String, String> parse(dynamic raw) {
    final out = <String, String>{};
    if (raw is! Map) return out;
    raw.forEach((key, value) {
      if (key == null) return;
      final k = key.toString().trim();
      if (k.isEmpty) return;
      if (value == null) return;
      if (value is String) {
        final t = value.trim();
        if (t.isNotEmpty) out[k] = t;
      } else if (value is num || value is bool) {
        out[k] = value.toString();
      }
    });
    return out;
  }

  /// PUT body object: omit empty strings so clearing a field removes the key.
  static Map<String, dynamic> toPayload(Map<String, String> edited) {
    final out = <String, dynamic>{};
    for (final entry in edited.entries) {
      final k = entry.key.trim();
      final v = entry.value.trim();
      if (k.isEmpty || v.isEmpty) continue;
      out[k] = v;
    }
    return out;
  }
}
