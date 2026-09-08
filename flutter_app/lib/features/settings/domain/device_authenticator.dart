/// HN-SET-004 — injectable device authenticator (platform biometrics).
///
/// HealthNest never collects or stores biometric templates. The OS authenticator
/// is the only biometric authority. Production uses [LocalAuthDeviceAuthenticator];
/// tests inject a fake implementation.
library;

import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

enum DeviceAuthResult {
  success,
  failed,
  cancelled,
  unavailable,
  error,
}

abstract class DeviceAuthenticator {
  Future<bool> canAuthenticate();

  /// Prompt the platform authenticator. Never returns biometric template data.
  Future<DeviceAuthResult> authenticate({required String localizedReason});
}

/// Default production implementation using `local_auth`.
class LocalAuthDeviceAuthenticator implements DeviceAuthenticator {
  LocalAuthDeviceAuthenticator({LocalAuthentication? plugin})
      : _auth = plugin ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> canAuthenticate() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final supported = await _auth.isDeviceSupported();
      return canCheck || supported;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<DeviceAuthResult> authenticate({required String localizedReason}) async {
    try {
      final available = await canAuthenticate();
      if (!available) return DeviceAuthResult.unavailable;

      final ok = await _auth.authenticate(
        localizedReason: localizedReason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      return ok ? DeviceAuthResult.success : DeviceAuthResult.failed;
    } on PlatformException catch (e) {
      final code = (e.code).toLowerCase();
      if (code.contains('cancel')) return DeviceAuthResult.cancelled;
      if (code.contains('notavailable') ||
          code.contains('notenrolled') ||
          code.contains('passcodenotset') ||
          code.contains('lockedout')) {
        return DeviceAuthResult.unavailable;
      }
      return DeviceAuthResult.error;
    } catch (_) {
      return DeviceAuthResult.error;
    }
  }
}
