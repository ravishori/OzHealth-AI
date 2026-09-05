import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/features/emergency/data/emergency_api.dart';
import 'package:vitapulse_ai/features/emergency/presentation/sos_hold_button.dart';
import 'package:vitapulse_ai/shared/widgets/clinical_safety_banner.dart';
import 'package:vitapulse_ai/shared/widgets/shimmer_box.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_spacing.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  bool _sosLoading = false;
  bool _contactsLoading = true;
  List<_EmergencyContact> _contacts = [];

  static const List<_AuNumber> _auNumbers = [
    _AuNumber(
        label: '000',
        description: 'Emergency Services',
        subtitle: 'Police · Fire · Ambulance',
        icon: Icons.emergency_rounded),
    _AuNumber(
        label: '13 11 26',
        description: 'Poisons Information',
        subtitle: '24/7 toxicology advice',
        icon: Icons.science_outlined),
    _AuNumber(
        label: '1800 022 222',
        description: 'Health Direct',
        subtitle: 'Free health advice line',
        icon: Icons.local_hospital_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(
          parent: _pulseController, curve: Curves.easeInOut),
    );
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _loadContacts());
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    setState(() => _contactsLoading = true);
    try {
      final response = await ApiClient.get('/emergency/contacts');
      final list = (response.data as List<dynamic>? ?? []);
      setState(() {
        _contacts = list
            .map((e) =>
                _EmergencyContact.fromJson(e as Map<String, dynamic>))
            .toList();
      });
    } catch (_) {
      // Silently handle - contacts list will be empty
    } finally {
      if (mounted) setState(() => _contactsLoading = false);
    }
  }

  Future<void> _triggerSOS() async {
    HapticFeedback.heavyImpact();
    setState(() => _sosLoading = true);
    try {
      bool serviceEnabled =
          await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showError('Location services are disabled. Please enable them.');
        return;
      }

      LocationPermission permission =
          await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showError('Location permission denied. Cannot send SOS.');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _showError(
            'Location permission permanently denied. Please enable it in settings.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final response = await ApiClient.post('/emergency/sos', data: {
        'latitude': position.latitude,
        'longitude': position.longitude,
      });

      final data = response.data as Map<String, dynamic>;
      final notified = data['contacts_notified'] as int? ?? 0;
      final serverMsg = data['message']?.toString();

      if (mounted) {
        _showSOSSuccess(notified, serverMessage: serverMsg);
      }
    } on DioException catch (e) {
      final msg = e.response?.data?['detail']?.toString() ??
          'SOS failed. Please call 000.';
      _showError(msg);
    } catch (e) {
      _showError('Could not send SOS. Please call 000 immediately.');
    } finally {
      if (mounted) setState(() => _sosLoading = false);
    }
  }

  void _showSOSSuccess(int notified, {String? serverMessage}) {
    final hc = HealthcareColors.of(context);
    final body = (serverMessage != null && serverMessage.trim().isNotEmpty)
        ? serverMessage
        : (notified > 0
            ? '$notified emergency contact${notified == 1 ? '' : 's'} notified with your location.'
            : 'SOS recorded. Contacts were NOT automatically notified. '
                'Call them manually or dial 000 for emergencies.');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.brLg),
        title: Row(
          children: [
            Icon(Icons.info_outline_rounded,
                color: hc.vitaWarning, size: 28),
            const SizedBox(width: 10),
            Text('SOS recorded',
                style: TextStyle(color: hc.vitaWarning)),
          ],
        ),
        content: Text(body),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: hc.vitaWarning),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    final hc = HealthcareColors.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: hc.emergency,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _callNumber(String number) async {
    final cleaned = number.replaceAll(' ', '');
    final uri = Uri.parse('tel:$cleaned');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _showError('Cannot launch phone dialler.');
    }
  }

  Future<void> _confirmDeleteContact(_EmergencyContact contact) async {
    final id = contact.id;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove contact?'),
        content: Text(
          'Remove ${contact.name} from your emergency contacts? '
          'You can still dial them from your phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await EmergencyApi.deleteContact(id);
      if (!mounted) return;
      setState(() {
        _contacts = _contacts.where((c) => c.id != id).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Emergency contact removed'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      _showError('Could not remove contact. Please try again.');
    }
  }

  void _showAddContactDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final relCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.brLg),
        title: const Text('Add Emergency Contact'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty)
                        ? 'Name is required'
                        : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty)
                        ? 'Phone is required'
                        : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: relCtrl,
                decoration: const InputDecoration(
                  labelText: 'Relationship',
                  prefixIcon:
                      Icon(Icons.family_restroom_outlined),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty)
                        ? 'Relationship is required'
                        : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              Navigator.of(ctx).pop();
              await _addContact(
                nameCtrl.text.trim(),
                phoneCtrl.text.trim(),
                relCtrl.text.trim(),
              );
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _addContact(
      String name, String phone, String relationship) async {
    try {
      final response =
          await ApiClient.post('/emergency/contacts', data: {
        'name': name,
        'phone': phone,
        'relationship': relationship,
      });
      final newContact = _EmergencyContact.fromJson(
          response.data as Map<String, dynamic>);
      setState(() => _contacts.add(newContact));
      if (mounted) {
        final hc = HealthcareColors.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Contact added successfully'),
            backgroundColor: hc.vitaGood,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on DioException catch (e) {
      final msg = e.response?.data?['detail']?.toString() ??
          'Failed to add contact.';
      _showError(msg);
    } catch (_) {
      _showError('Failed to add contact. Please try again.');
    }
  }

  // ── Build helpers ──────────────────────────────────────────────

  Widget _buildSOSHeader() {
    final hc = HealthcareColors.of(context);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            hc.emergency,
            hc.emergency.withValues(alpha: 0.85),
            hc.emergencyContainer,
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.x8),
          // Concentric rings + SOS button
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (_, child) => Stack(
              alignment: Alignment.center,
              children: [
                // Outer glow ring
                Transform.scale(
                  scale: _sosLoading ? 1.0 : _pulseAnimation.value * 1.08,
                  child: Container(
                    width: 210,
                    height: 210,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                        width: 2,
                      ),
                    ),
                  ),
                ),
                // Middle ring
                Transform.scale(
                  scale: _sosLoading ? 1.0 : _pulseAnimation.value,
                  child: Container(
                    width: 188,
                    height: 188,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.20),
                        width: 2,
                      ),
                    ),
                  ),
                ),
                // SOS button — explicit 3s hold (not default onLongPress)
                child!,
              ],
            ),
            child: SosHoldButton(
              key: const Key('sos_hold_button'),
              enabled: !_sosLoading,
              emergencyColor: hc.emergency,
              onActivated: _triggerSOS,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Hold for 3 seconds to record SOS — release to cancel',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Records your GPS for dial-back. Contacts are NOT auto-notified.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: AppSpacing.x8),
        ],
      ),
    );
  }

  Widget _buildEmergencyDisclaimer() {
    return const ClinicalSafetyBanner(
      kind: ClinicalDisclaimerKind.emergency,
      margin: EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: EdgeInsets.all(12),
      rounded: true,
    );
  }

  Widget _buildAuNumbers() {
    final hc = HealthcareColors.of(context);
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: hc.emergency.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.phone_in_talk_rounded,
                    size: 18, color: hc.emergency),
              ),
              const SizedBox(width: 10),
              Text(
                'Australian Emergency Numbers',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
        ),
        ..._auNumbers.map((n) => _AuNumberCard(
              number: n,
              onCall: () => _callNumber(n.label),
            )),
      ],
    );
  }

  Widget _buildContacts() {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 16, 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.contacts_rounded,
                    size: 18, color: cs.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Emergency Contacts',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _showAddContactDialog,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
        if (_contactsLoading)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                ShimmerCard(height: 76),
                ShimmerCard(height: 76),
              ],
            ),
          )
        else if (_contacts.isEmpty)
          _buildEmptyContacts(cs)
        else
          ..._contacts.map((c) => _ContactCard(
                contact: c,
                onCall: () => _callNumber(c.phone),
                onDelete: c.id == null ? null : () => _confirmDeleteContact(c),
              )),
      ],
    );
  }

  Widget _buildEmptyContacts(ColorScheme cs) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.5),
          style: BorderStyle.solid,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.person_add_alt_1_outlined,
              color: cs.onSurfaceVariant, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No emergency contacts',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Add contacts you can dial manually in an emergency',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: HealthcareColors.of(context).emergency,
        elevation: 0,
        title: const Text(
          'Emergency',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        leading: BackButton(
          color: Colors.white,
          onPressed: () {
            final router = GoRouter.maybeOf(context);
            if (router != null) {
              if (router.canPop()) {
                router.pop();
              } else {
                router.go('/home');
              }
              return;
            }
            final nav = Navigator.of(context);
            if (nav.canPop()) {
              nav.pop();
            }
          },
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: _loadContacts,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSOSHeader(),
              _buildEmergencyDisclaimer(),
              _buildAuNumbers(),
              const SizedBox(height: 8),
              Divider(
                height: 1,
                indent: 20,
                endIndent: 20,
                color: cs.outlineVariant.withValues(alpha: 0.5),
              ),
              _buildContacts(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── Data models ───────────────────────────

class _EmergencyContact {
  final int? id;
  final String name;
  final String phone;
  final String relationship;

  const _EmergencyContact({
    this.id,
    required this.name,
    required this.phone,
    required this.relationship,
  });

  factory _EmergencyContact.fromJson(Map<String, dynamic> json) {
    return _EmergencyContact(
      id: json['id'] as int?,
      name: json['name']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      relationship: json['relationship']?.toString() ?? '',
    );
  }
}

class _AuNumber {
  final String label;
  final String description;
  final String subtitle;
  final IconData icon;

  const _AuNumber({
    required this.label,
    required this.description,
    required this.subtitle,
    required this.icon,
  });
}

// ─────────────────────────── Widgets ───────────────────────────

class _AuNumberCard extends StatelessWidget {
  final _AuNumber number;
  final VoidCallback onCall;

  const _AuNumberCard({required this.number, required this.onCall});

  @override
  Widget build(BuildContext context) {
    final hc = HealthcareColors.of(context);
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hc.emergency.withValues(alpha: 0.15),
        ),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: hc.emergency.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(number.icon, color: hc.emergency, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    number.label,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: hc.emergency,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    number.description,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: cs.onSurface,
                    ),
                  ),
                  Text(
                    number.subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: onCall,
              icon: const Icon(Icons.phone_rounded, size: 16),
              label: const Text('Call'),
              style: FilledButton.styleFrom(
                backgroundColor: hc.emergency,
                foregroundColor: Colors.white,
                minimumSize: const Size(76, 38),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  final _EmergencyContact contact;
  final VoidCallback onCall;
  final VoidCallback? onDelete;

  const _ContactCard({
    required this.contact,
    required this.onCall,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final initials = contact.name.isNotEmpty
        ? contact.name.trim().split(' ').map((w) => w[0]).take(2).join()
        : '?';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    cs.primary.withValues(alpha: 0.25),
                    cs.primaryContainer.withValues(alpha: 0.5),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  initials.toUpperCase(),
                  style: TextStyle(
                    color: cs.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contact.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    contact.phone,
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    contact.relationship,
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            if (onDelete != null) ...[
              IconButton(
                onPressed: onDelete,
                tooltip: 'Remove contact',
                icon: Icon(Icons.delete_outline_rounded,
                    color: cs.error, size: 22),
              ),
            ],
            const SizedBox(width: 4),
            IconButton.filled(
              onPressed: onCall,
              icon: const Icon(Icons.phone_rounded, size: 20),
              style: IconButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                minimumSize: const Size(42, 42),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
