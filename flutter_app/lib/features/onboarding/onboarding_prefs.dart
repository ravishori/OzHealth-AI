import 'package:hive_flutter/hive_flutter.dart';

/// Device-level UX flag only (HN-UX-002).
///
/// Stores a boolean completion flag only — never account or health data.
/// Survives logout/login on the same device so the tour is not forced again.
const kOnboardingCompletedKey = 'onboarding_completed';

bool isOnboardingCompleted({Box? box}) {
  final prefs = box ?? Hive.box('app_preferences');
  return prefs.get(kOnboardingCompletedKey, defaultValue: false) == true;
}

Future<void> markOnboardingCompleted({Box? box}) async {
  final prefs = box ?? Hive.box('app_preferences');
  await prefs.put(kOnboardingCompletedKey, true);
}
