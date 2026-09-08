import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vitapulse_ai/core/utils/error_handler.dart';
import 'package:vitapulse_ai/features/legal/legal_screens.dart';
import 'package:vitapulse_ai/features/profile/data/user_api.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_spacing.dart';

/// HN-SET-003 — Privacy settings hub.
///
/// Surfaces only real privacy-related actions already supported by the app:
/// legal consent status (read-only), legal documents, data export, account
/// deletion, and OS notification permission settings.
///
/// Does **not** invent analytics / AI / data-sharing toggles that have no
/// corresponding product behavior.
class PrivacySettingsScreen extends StatefulWidget {
  final bool Function()? readConsentCompleted;
  final Future<PermissionStatus> Function()? readNotificationStatus;
  final Future<bool> Function()? openSystemSettings;
  final Future<Map<String, dynamic>> Function()? exportMyData;
  final Future<void> Function(Map<String, dynamic> payload)? shareExport;

  const PrivacySettingsScreen({
    super.key,
    this.readConsentCompleted,
    this.readNotificationStatus,
    this.openSystemSettings,
    this.exportMyData,
    this.shareExport,
  });

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  bool _consentCompleted = false;
  PermissionStatus? _notificationStatus;
  bool _loadingNotif = true;
  bool _exporting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  bool _loadConsent() {
    final reader = widget.readConsentCompleted;
    if (reader != null) return reader();
    return Hive.box('app_preferences').get(kLegalConsentKey, defaultValue: false) ==
        true;
  }

  Future<void> _refresh() async {
    setState(() {
      _consentCompleted = _loadConsent();
      _loadingNotif = true;
      _error = null;
    });
    try {
      final statusReader = widget.readNotificationStatus;
      final status = statusReader != null
          ? await statusReader()
          : await Permission.notification.status;
      if (!mounted) return;
      setState(() {
        _notificationStatus = status;
        _loadingNotif = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _notificationStatus = null;
        _loadingNotif = false;
        _error = 'Could not read notification permission status.';
      });
    }
  }

  Future<void> _openNotificationSettings() async {
    final opener = widget.openSystemSettings ?? openAppSettings;
    await opener();
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _exportMyData() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final exporter = widget.exportMyData ?? UserApi.exportMyData;
      final sharer = widget.shareExport ?? UserApi.shareDataExport;
      final payload = await exporter();
      await sharer(payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your data export is ready to save or share.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ErrorHandler.getMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String get _notificationLabel {
    final s = _notificationStatus;
    if (s == null) return 'Unknown';
    switch (s) {
      case PermissionStatus.granted:
      case PermissionStatus.limited:
      case PermissionStatus.provisional:
        return 'Allowed';
      case PermissionStatus.denied:
        return 'Not allowed';
      case PermissionStatus.permanentlyDenied:
        return 'Blocked in system settings';
      case PermissionStatus.restricted:
        return 'Restricted';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      key: const Key('privacy_settings_screen'),
      appBar: AppBar(
        title: const Text('Privacy'),
        centerTitle: false,
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: AppSpacing.screenPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            Text(
              'Privacy actions',
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'These controls link to privacy actions HealthNest already '
              'supports. This screen does not claim regulatory certification.',
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: cs.error)),
              TextButton(
                key: const Key('privacy_retry'),
                onPressed: _refresh,
                child: const Text('Retry'),
              ),
            ],
            const SizedBox(height: 20),

            // ── Legal consent (status only; gate remains authoritative) ──
            Text(
              'Legal consent',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Required before using the app. Changing optional product '
              'preferences does not replace this consent.',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            ListTile(
              key: const Key('privacy_consent_status'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                _consentCompleted
                    ? Icons.verified_user_outlined
                    : Icons.gpp_maybe_outlined,
                color: _consentCompleted ? cs.primary : cs.error,
              ),
              title: const Text('App disclaimer consent'),
              subtitle: Text(
                _consentCompleted
                    ? 'Recorded on this device'
                    : 'Not recorded — you will be asked at next launch',
              ),
            ),
            ListTile(
              key: const Key('privacy_view_disclaimer'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined),
              title: const Text('View medical disclaimer'),
              subtitle: const Text('Read the consent text again'),
              onTap: () => context.push('/legal/consent'),
            ),

            const Divider(height: 32),

            // ── Documents ──
            Text(
              'Documents',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            ListTile(
              key: const Key('privacy_policy_link'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacy policy'),
              onTap: () => context.push('/legal/privacy'),
            ),
            ListTile(
              key: const Key('privacy_terms_link'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.gavel_outlined),
              title: const Text('Terms of use'),
              onTap: () => context.push('/legal/terms'),
            ),

            const Divider(height: 32),

            // ── Your data ──
            Text(
              'Your data',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            ListTile(
              key: const Key('privacy_export_data'),
              contentPadding: EdgeInsets.zero,
              leading: _exporting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined),
              title: const Text('Export my data'),
              subtitle: const Text(
                'Download a copy of your HealthNest account data',
              ),
              onTap: _exporting ? null : _exportMyData,
            ),
            ListTile(
              key: const Key('privacy_delete_account'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.delete_forever_outlined, color: cs.error),
              title: Text(
                'Delete account',
                style: TextStyle(color: cs.error),
              ),
              subtitle: const Text('Permanently remove your account and data'),
              onTap: () => context.push('/legal/delete-account'),
            ),

            const Divider(height: 32),

            // ── Notifications (OS permission — real behavior) ──
            Text(
              'On-device notifications',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Medication and appointment reminders use on-device '
              'notifications. Permission is controlled by the operating system.',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            ListTile(
              key: const Key('privacy_notification_status'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('Notification permission'),
              subtitle: Text(
                _loadingNotif ? 'Checking…' : _notificationLabel,
              ),
              trailing: TextButton(
                key: const Key('privacy_open_notification_settings'),
                onPressed: _openNotificationSettings,
                child: const Text('System settings'),
              ),
            ),
            const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
