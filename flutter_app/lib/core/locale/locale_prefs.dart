import 'package:hive_flutter/hive_flutter.dart';

/// Device-local UI locale preference only (HN-FUTURE-006).
///
/// Stores a language code (`en`, `hi`, `mr`) or clears the key for system
/// default. Never stores account, health, or PHI data.
const kAppLocaleKey = 'app_locale';

/// Supported app UI locales for HealthNest multi-language (matches existing
/// AI/insights Hindi & Marathi product languages; English is the default).
const kSupportedLanguageCodes = <String>['en', 'hi', 'mr'];

String? readStoredLocaleCode({Box? box}) {
  final prefs = box ?? Hive.box('app_preferences');
  final raw = prefs.get(kAppLocaleKey);
  if (raw is! String) return null;
  final code = raw.trim().toLowerCase();
  if (code.isEmpty) return null;
  if (!kSupportedLanguageCodes.contains(code)) return null;
  return code;
}

Future<void> persistLocaleCode(String? languageCode, {Box? box}) async {
  final prefs = box ?? Hive.box('app_preferences');
  if (languageCode == null || languageCode.trim().isEmpty) {
    await prefs.delete(kAppLocaleKey);
    return;
  }
  final code = languageCode.trim().toLowerCase();
  if (!kSupportedLanguageCodes.contains(code)) {
    await prefs.delete(kAppLocaleKey);
    return;
  }
  await prefs.put(kAppLocaleKey, code);
}
