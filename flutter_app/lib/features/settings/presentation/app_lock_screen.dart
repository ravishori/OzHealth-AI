import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vitapulse_ai/features/auth/data/auth_api.dart';
import 'package:vitapulse_ai/features/settings/domain/app_lock_service.dart';
import 'package:vitapulse_ai/features/settings/domain/device_authenticator.dart';
import 'package:vitapulse_ai/l10n/app_localizations.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_spacing.dart';

/// HN-SET-004 — biometric unlock gate before authenticated `/home` shell.
class AppLockScreen extends StatefulWidget {
  const AppLockScreen({super.key});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await AppLockService.unlockWithBiometrics(
        localizedReason: l10n.securityUnlockReason,
      );
      if (!mounted) return;
      if (result == DeviceAuthResult.success) {
        context.go('/home');
        return;
      }
      setState(() {
        _error = switch (result) {
          DeviceAuthResult.cancelled => l10n.securityAuthCancelled,
          DeviceAuthResult.unavailable => l10n.securityBiometricsUnavailable,
          _ => l10n.securityAuthFailed,
        };
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    AppLockService.lockSession();
    await AuthApi.logout();
    if (!mounted) return;
    context.go('/auth/welcome');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.x6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 64, color: cs.primary),
              const SizedBox(height: AppSpacing.x6),
              Text(
                l10n.securityUnlockTitle,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.x2),
              Text(
                l10n.securityUnlockBody,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.x4),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    key: const Key('app_lock_error'),
                    style: TextStyle(color: cs.error),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.x8),
              SizedBox(
                height: AppSpacing.touchTarget,
                child: FilledButton.icon(
                  key: const Key('app_lock_unlock_button'),
                  onPressed: _busy ? null : _unlock,
                  icon: const Icon(Icons.fingerprint),
                  label: Text(l10n.securityUnlockAction),
                ),
              ),
              const SizedBox(height: AppSpacing.x4),
              TextButton(
                key: const Key('app_lock_sign_out_button'),
                onPressed: _busy ? null : _signOut,
                child: Text(l10n.signOut),
              ),
              if (_busy) ...[
                const SizedBox(height: AppSpacing.x6),
                const CircularProgressIndicator(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
