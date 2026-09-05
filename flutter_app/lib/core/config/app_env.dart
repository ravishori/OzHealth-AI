import 'package:flutter/foundation.dart';

/// Compile-time / runtime flags for Play release vs local debug.
///
/// Release store builds MUST pass:
///   --dart-define=API_BASE_URL=https://your-api.example/api/v1
/// Optional:
///   --dart-define=PRIVACY_POLICY_URL=https://...
///   --dart-define=ACCOUNT_DELETION_URL=https://...
///   --dart-define=ENABLE_EPRESCRIPTION=true
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

  /// LAN auto-discovery is debug-only. Store builds never probe the subnet.
  static bool get allowLanDiscovery => kDebugMode;

  static bool get hasProductionApi => apiBaseUrl.trim().isNotEmpty;

  static bool get showEprescriptions => kDebugMode || enableEprescription;

  static String? get publicPrivacyUrl {
    final u = privacyPolicyUrl.trim();
    return u.isEmpty ? null : u;
  }

  static String? get publicDeletionUrl {
    final u = accountDeletionUrl.trim();
    return u.isEmpty ? null : u;
  }
}
