import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vitapulse_ai/core/utils/auth_storage.dart';
import 'package:vitapulse_ai/features/auth/data/auth_api.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';
import 'package:vitapulse_ai/core/config/app_env.dart';

/// Side navigation drawer — lists every feature in the app,
/// organised by category, with icons and subtitles.
class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  String _name  = 'User';
  String? _imageUrl;
  bool _loggingOut = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final name = await AuthStorage.getUserName();
    final rel  = await AuthStorage.getProfileImageUrl();
    if (mounted) {
      setState(() {
        if (name != null) _name = name;
        _imageUrl = rel;
      });
    }
  }

  Future<void> _logout() async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);
    try {
      final outcome = await AuthApi.logout();
      if (!mounted) return;
      if (outcome == LogoutOutcome.localOnly) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Signed out on this device. Server session could not be confirmed.',
            ),
          ),
        );
      }
      context.go('/auth/welcome');
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  void _nav(String path) {
    Navigator.pop(context);    // close drawer
    context.push(path);        // push so Back still works from any drawer destination
  }

  void _navReplace(String path) {
    Navigator.pop(context);
    context.go(path);          // go() for top-level reset (Home Dashboard, Sign Out)
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);
    return Drawer(
      backgroundColor: cs.surface,
      child: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(cs.primary, Colors.black, 0.30)!,
                    cs.primary,
                  ],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _DrawerAvatar(imageUrl: _imageUrl, name: _name),
                      const Spacer(),
                      InkWell(
                        onTap: () => _nav('/home/profile'),
                        child: const Icon(Icons.edit, color: Colors.white60, size: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    'HealthNest',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),

            // ── Feature list ─────────────────────────────────────────────────
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [

                  // ─── Home ───────────────────────────────────────────────
                  _DrawerItem(
                    icon: Icons.home_outlined,
                    label: 'Home Dashboard',
                    onTap: () => _navReplace('/home'),
                  ),

                  const _SectionHeader('📋  Prescriptions & Records'),
                  _DrawerItem(
                    icon: Icons.document_scanner_outlined,
                    label: 'Scan Prescription (OCR)',
                    subtitle: 'AI-powered text extraction',
                    onTap: () => _nav('/home/prescriptions/scan'),
                  ),
                  if (AppEnv.showEprescriptions)
                    _DrawerItem(
                      icon: Icons.qr_code_2,
                      label: 'ePrescription',
                      subtitle: 'Scan QR / validate eRx token',
                      onTap: () => _nav('/home/eprescriptions'),
                    ),
                  _DrawerItem(
                    icon: Icons.folder_copy_outlined,
                    label: 'My Medical Records',
                    subtitle: 'Lab reports, prescriptions',
                    onTap: () => _nav('/home/records'),
                  ),

                  const _SectionHeader('💊  Medicines & Reminders'),
                  _DrawerItem(
                    icon: Icons.medication_outlined,
                    label: 'Medicine Search',
                    subtitle: 'TGA database — 450K+ medicines',
                    onTap: () => _nav('/home/medicines'),
                  ),
                  _DrawerItem(
                    icon: Icons.alarm_outlined,
                    label: 'Medication Reminders',
                    subtitle: 'Scheduled dose alerts',
                    onTap: () => _nav('/home/reminders'),
                  ),
                  _DrawerItem(
                    icon: Icons.biotech_outlined,
                    label: 'Drug Interactions',
                    subtitle: 'AI safety analysis',
                    onTap: () => _nav('/home/interactions'),
                    badgeColor: hc.vitaCritical,
                    badge: 'AI',
                  ),

                  const _SectionHeader('❤️  Health Monitoring'),
                  _DrawerItem(
                    icon: Icons.monitor_heart_outlined,
                    label: 'Health Monitor',
                    subtitle: 'Vitals — BP, glucose, weight…',
                    onTap: () => _nav('/home/health'),
                  ),
                  _DrawerItem(
                    icon: Icons.insights_outlined,
                    label: 'Health Insights',
                    subtitle: 'AI predictive alerts',
                    onTap: () => _nav('/home/insights'),
                    badgeColor: cs.tertiary,
                    badge: 'AI',
                  ),

                  const _SectionHeader('🤖  AI Diagnostic Tools'),
                  _DrawerItem(
                    icon: Icons.psychology_outlined,
                    label: 'AI Health Assistant',
                    subtitle: 'Ask any health question',
                    onTap: () => _nav('/home/ai-chat'),
                    badgeColor: cs.primary,
                    badge: 'AI',
                  ),
                  _DrawerItem(
                    icon: Icons.medical_services_outlined,
                    label: 'Symptom Checker',
                    subtitle: 'AI triage & guidance',
                    onTap: () => _nav('/home/symptoms'),
                    badgeColor: cs.secondary,
                    badge: 'AI',
                  ),
                  _DrawerItem(
                    icon: Icons.science_outlined,
                    label: 'Lab Report Analysis',
                    subtitle: 'Explain test results in plain English',
                    onTap: () => _nav('/home/lab-analysis'),
                    badgeColor: hc.labReport,
                    badge: 'AI',
                  ),

                  const _SectionHeader('👨‍👩‍👦  Family & Safety'),
                  _DrawerItem(
                    icon: Icons.family_restroom_outlined,
                    label: 'Family Health Profiles',
                    subtitle: 'Manage family members',
                    onTap: () => _nav('/home/family'),
                  ),
                  _DrawerItem(
                    icon: Icons.location_on_outlined,
                    label: 'Nearby Services',
                    subtitle: 'Hospitals, pharmacies, clinics',
                    onTap: () => _nav('/home/nearby'),
                  ),
                  _DrawerItem(
                    icon: Icons.emergency_outlined,
                    label: 'Emergency SOS',
                    subtitle: 'Alert emergency contacts',
                    onTap: () => _nav('/home/emergency'),
                    badgeColor: hc.emergency,
                    badge: 'SOS',
                  ),

                  const _SectionHeader('⚙️  Account'),
                  _DrawerItem(
                    icon: Icons.person_outline,
                    label: 'My Profile',
                    subtitle: 'Health info & preferences',
                    onTap: () => _nav('/home/profile'),
                  ),
                  _DrawerItem(
                    icon: Icons.palette_outlined,
                    label: 'Appearance',
                    subtitle: 'Themes, text size & display',
                    onTap: () => _nav('/home/settings/appearance'),
                  ),
                  _DrawerItem(
                    icon: Icons.privacy_tip_outlined,
                    label: 'Privacy policy',
                    subtitle: 'How we handle health information',
                    onTap: () => _nav('/legal/privacy'),
                  ),
                  _DrawerItem(
                    icon: Icons.delete_forever_outlined,
                    label: 'Delete account',
                    subtitle: 'Permanently remove your data',
                    onTap: () => _nav('/legal/delete-account'),
                  ),

                  const Divider(height: 24),
                  _DrawerItem(
                    icon: Icons.logout,
                    label: 'Sign Out',
                    iconColor: cs.error,
                    labelColor: cs.error,
                    onTap: _logout,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),

            // ── Footer version ───────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'HealthNest  •  v1.0.0',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Reusable drawer sub-widgets ─────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: cs.onSurfaceVariant,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? labelColor;
  final String? badge;
  final Color? badgeColor;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.iconColor,
    this.labelColor,
    this.badge,
    this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ic = iconColor ?? cs.primary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: ic.withValues(alpha: 0.1),
                borderRadius: AppRadius.brSm,
              ),
              child: Icon(icon, size: 19, color: ic),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: labelColor ?? cs.onSurface),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: TextStyle(
                          fontSize: 11, color: cs.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (badge != null && badgeColor != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor!.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: badgeColor!.withValues(alpha: 0.3)),
                ),
                child: Text(
                  badge!,
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: badgeColor),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DrawerAvatar extends StatelessWidget {
  final String? imageUrl;
  final String name;
  const _DrawerAvatar({required this.imageUrl, required this.name});

  String get _initials {
    final words = name.trim().split(RegExp(r'\s+'));
    return words.take(2).map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();
  }

  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: 28,
        backgroundColor: Colors.white24,
        child: imageUrl != null
            ? ClipOval(
                child: CachedNetworkImage(
                  imageUrl: imageUrl!,
                  width: 56, height: 56,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => _fallback,
                ),
              )
            : _fallback,
      );

  Widget get _fallback => Center(
        child: Text(
          _initials,
          style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      );
}
