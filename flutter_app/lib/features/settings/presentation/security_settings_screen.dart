import 'package:flutter/material.dart';
import 'package:vitapulse_ai/features/settings/domain/app_lock_service.dart';
import 'package:vitapulse_ai/features/settings/domain/device_authenticator.dart';
import 'package:vitapulse_ai/l10n/app_localizations.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_spacing.dart';

/// HN-SET-004 — Security settings (optional biometrics).
///
/// Toggle has a real enforcement effect: when enabled, the authenticated
/// `/home` shell requires device biometric unlock for this process.
class SecuritySettingsScreen extends StatefulWidget {
  final DeviceAuthenticator? authenticator;

  const SecuritySettingsScreen({super.key, this.authenticator});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  bool _enabled = false;
  bool _available = false;
  bool _busy = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    if (widget.authenticator != null) {
      AppLockService.debugReplaceAuthenticator(widget.authenticator!);
    }
    _refresh();
  }

  Future<void> _refresh() async {
    final enabled = AppLockService.isBiometricLockEnabled();
    final available = await AppLockService.authenticator.canAuthenticate();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _available = available;
    });
  }

  Future<void> _onToggle(bool wantEnabled) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _statusMessage = null;
    });

    try {
      if (wantEnabled) {
        if (!_available) {
          setState(() {
            _statusMessage = l10n.securityBiometricsUnavailable;
          });
          return;
        }
        final result = await AppLockService.enableBiometricLock(
          localizedReason: l10n.securityEnableReason,
        );
        if (!mounted) return;
        if (result != DeviceAuthResult.success) {
          setState(() {
            _statusMessage = _messageFor(result, l10n);
            _enabled = AppLockService.isBiometricLockEnabled();
          });
          return;
        }
        setState(() {
          _enabled = true;
          _statusMessage = l10n.securityEnabled;
        });
      } else {
        final result = await AppLockService.disableBiometricLock(
          localizedReason: l10n.securityDisableReason,
        );
        if (!mounted) return;
        if (result != DeviceAuthResult.success) {
          setState(() {
            _statusMessage = _messageFor(result, l10n);
            _enabled = AppLockService.isBiometricLockEnabled();
          });
          return;
        }
        setState(() {
          _enabled = false;
          _statusMessage = l10n.securityDisabled;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _messageFor(DeviceAuthResult result, AppLocalizations l10n) {
    switch (result) {
      case DeviceAuthResult.cancelled:
        return l10n.securityAuthCancelled;
      case DeviceAuthResult.unavailable:
        return l10n.securityBiometricsUnavailable;
      case DeviceAuthResult.failed:
      case DeviceAuthResult.error:
        return l10n.securityAuthFailed;
      case DeviceAuthResult.success:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.security),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.x4),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x4),
            child: Text(
              l10n.securitySubtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ),
          const SizedBox(height: AppSpacing.x4),
          Semantics(
            label: l10n.securityBiometricLock,
            toggled: _enabled,
            enabled: !_busy,
            child: SwitchListTile(
              key: const Key('security_biometric_toggle'),
              secondary: Icon(
                Icons.fingerprint,
                color: cs.primary,
                semanticLabel: l10n.securityBiometricLock,
              ),
              title: Text(l10n.securityBiometricLock),
              subtitle: Text(
                _available
                    ? l10n.securityBiometricLockHelp
                    : l10n.securityBiometricsUnavailable,
              ),
              value: _enabled,
              onChanged: _busy ? null : _onToggle,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x4),
            child: Text(
              l10n.securityBoundaryHelp,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ),
          if (_statusMessage != null) ...[
            const SizedBox(height: AppSpacing.x4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x4),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _statusMessage!,
                  key: const Key('security_status_message'),
                  style: TextStyle(color: cs.primary),
                ),
              ),
            ),
          ],
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.x4),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
