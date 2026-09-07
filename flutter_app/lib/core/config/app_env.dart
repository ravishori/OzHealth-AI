import 'package:flutter/foundation.dart';

/// Compile-time / runtime flags for Play release, staging, and local debug.
///
/// Staging / release builds MUST inject the API origin (no hardcoded secrets):
///   flutter build apk --dart-define=API_BASE_URL=https://aihealthcompanion-api-staging.azurewebsites.net
///   # or with /api/v1 suffix — both forms are accepted
/// Optional:
///   --dart-define=PRIVACY_POLICY_URL=https://...
///   --dart-define=ACCOUNT_DELETION_URL=https://...
///   --dart-define=ENABLE_EPRESCRIPTION=true
///
/// Never commit production/staging credentials into this file.
class AppEnv {
  AppEnv._();

  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const privacyPolicyUrl = String.fromEnvironment('PRIVACY_POLICY_URL');
  static const accountDeletionUrl =
      String.fromEnvironment('ACCOUNT_DELETION_URL');
  static const enableEprescription = bool.fromEnvironment(
    'ENABLE_EPRESCRIPTION',
    defaultValue: false,
  );

  /// LAN auto-discovery is debug-only. Store/staging release builds never probe.
  static bool get allowLanDiscovery => kDebugMode;

  static bool get hasProductionApi => apiBaseUrl.trim().isNotEmpty;

  /// True when a non-empty compile-time API base was provided (staging or prod).
  static bool get hasInjectedApiBase => hasProductionApi;

  static bool get showEprescriptions => kDebugMode || enableEprescription;

  /// Normalize a dart-define API base to include `/api/v1` exactly once.
  static String normalizeApiBaseUrl(String configured) {
    var url = configured.trim();
    if (url.isEmpty) return url;
    if (!url.contains('/api/v1')) {
      if (url.endsWith('/')) {
        url = url.substring(0, url.length - 1);
      }
      url = '$url/api/v1';
    }
    return url;
  }

  static String? get publicPrivacyUrl {
    final u = privacyPolicyUrl.trim();
    return u.isEmpty ? null : u;
  }

  static String? get publicDeletionUrl {
    final u = accountDeletionUrl.trim();
    return u.isEmpty ? null : u;
  }
}
