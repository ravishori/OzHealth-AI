/// HN-SET-004 — optional biometric app-lock preference + session gate.
///
/// Authoritative checklist remaining AC: "Optional biometrics".
/// PIN is **not** implemented (not in Remaining AC).
///
/// Protected boundary:
///   When enabled and the user has a valid local account session, the `/home`
///   shell requires a successful device biometric unlock for this process.
///   This does **not** replace server JWT / token_version authorization.
///
/// Persistence:
///   Enabled flag is a non-secret boolean in Hive `app_preferences`.
///   Session unlock is in-memory only (locked again after process restart).
///   No biometric templates or PIN secrets are stored.
library;

import 'package:hive_flutter/hive_flutter.dart';
import 'package:vitapulse_ai/core/utils/auth_storage.dart';
import 'package:vitapulse_ai/features/settings/domain/device_authenticator.dart';

const String kAppLockBiometricsEnabledKey = 'app_lock_biometrics_enabled';

class AppLockService {
  AppLockService._();

  static DeviceAuthenticator authenticator = LocalAuthDeviceAuthenticator();

  /// In-memory session unlock for the current process only.
  static bool _sessionUnlocked = false;

  /// When non-null, preference is read/written only in memory (test seam).
  /// Unavailable to ordinary production users.
  static bool? _testEnabledOverride;

  /// Test / DI seam — not exposed to ordinary users.
  static void debugReplaceAuthenticator(DeviceAuthenticator next) {
    authenticator = next;
  }

  static void debugResetSession({bool unlocked = false}) {
    _sessionUnlocked = unlocked;
  }

  /// Enables in-memory preference mode for widget/unit tests.
  static void debugUseInMemoryPreference({required bool enabled}) {
    _testEnabledOverride = enabled;
  }

  static void debugClearInMemoryPreference() {
    _testEnabledOverride = null;
  }

  static bool get isSessionUnlocked => _sessionUnlocked;

  static void lockSession() {
    _sessionUnlocked = false;
  }

  static void unlockSession() {
    _sessionUnlocked = true;
  }

  static bool isBiometricLockEnabled() {
    if (_testEnabledOverride != null) {
      return _testEnabledOverride!;
    }
    try {
      final box = Hive.box('app_preferences');
      return box.get(kAppLockBiometricsEnabledKey, defaultValue: false) == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _persistEnabled(bool enabled) async {
    if (_testEnabledOverride != null) {
      _testEnabledOverride = enabled;
      return;
    }
    final box = Hive.box('app_preferences');
    await box.put(kAppLockBiometricsEnabledKey, enabled);
  }

  /// True when an authenticated user must pass biometrics before `/home`.
  static Future<bool> requiresUnlock() async {
    if (!isBiometricLockEnabled()) return false;
    if (!await AuthStorage.isLoggedIn()) return false;
    return !_sessionUnlocked;
  }

  /// Enable lock only after a successful platform authentication.
  static Future<DeviceAuthResult> enableBiometricLock({
    required String localizedReason,
  }) async {
    final result =
        await authenticator.authenticate(localizedReason: localizedReason);
    if (result != DeviceAuthResult.success) {
      return result;
    }
    await _persistEnabled(true);
    unlockSession();
    return DeviceAuthResult.success;
  }

  /// Disable lock only after a successful platform authentication.
  static Future<DeviceAuthResult> disableBiometricLock({
    required String localizedReason,
  }) async {
    final result =
        await authenticator.authenticate(localizedReason: localizedReason);
    if (result != DeviceAuthResult.success) {
      return result;
    }
    await _persistEnabled(false);
    unlockSession();
    return DeviceAuthResult.success;
  }

  static Future<DeviceAuthResult> unlockWithBiometrics({
    required String localizedReason,
  }) async {
    if (!isBiometricLockEnabled()) {
      unlockSession();
      return DeviceAuthResult.success;
    }
    final result =
        await authenticator.authenticate(localizedReason: localizedReason);
    if (result == DeviceAuthResult.success) {
      unlockSession();
    }
    return result;
  }
}
