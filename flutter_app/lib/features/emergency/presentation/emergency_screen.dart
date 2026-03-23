import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/core/theme/app_theme.dart';

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
    _AuNumber(label: '000', description: 'Emergency Services', icon: Icons.emergency),
    _AuNumber(label: '13 11 26', description: 'Poisons Information', icon: Icons.science_outlined),
    _AuNumber(label: '1800 022 222', description: 'Health Direct', icon: Icons.local_hospital_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadContacts());
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
        _contacts = list.map((e) => _EmergencyContact.fromJson(e as Map<String, dynamic>)).toList();
      });
    } catch (_) {
      // Silently handle - contacts list will be empty
    } finally {
      if (mounted) setState(() => _contactsLoading = false);
    }
  }

  Future<void> _triggerSOS() async {
    setState(() => _sosLoading = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showError('Location services are disabled. Please enable them.');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showError('Location permission denied. Cannot send SOS.');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _showError('Location permission permanently denied. Please enable it in settings.');
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
      final notified = data['contacts_notified'] as int? ?? _contacts.length;

      if (mounted) {
        _showSOSSuccess(notified);
      }
    } on DioException catch (e) {
      final msg = e.response?.data?['detail']?.toString() ?? 'SOS failed. Please call 000.';
      _showError(msg);
    } catch (e) {
      _showError('Could not send SOS. Please call 000 immediately.');
    } finally {
      if (mounted) setState(() => _sosLoading = false);
    }
  }

  void _showSOSSuccess(int notified) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: AppTheme.success, size: 28),
            SizedBox(width: 10),
            Text('SOS Sent!', style: TextStyle(color: AppTheme.success)),
          ],
        ),
        content: Text(
          '$notified emergency contact${notified == 1 ? '' : 's'} notified with your location.',
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.emergencyRed,
        behavior: SnackBarBehavior.floating,
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

  void _showAddContactDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final relCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
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
                    (v == null || v.trim().isEmpty) ? 'Phone is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: relCtrl,
                decoration: const InputDecoration(
                  labelText: 'Relationship',
                  prefixIcon: Icon(Icons.family_restroom_outlined),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Relationship is required' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
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

  Future<void> _addContact(String name, String phone, String relationship) async {
    try {
      final response = await ApiClient.post('/emergency/contacts', data: {
        'name': name,
        'phone': phone,
        'relationship': relationship,
      });
      final newContact = _EmergencyContact.fromJson(
          response.data as Map<String, dynamic>);
      setState(() => _contacts.add(newContact));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Contact added successfully'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } on DioException catch (e) {
      final msg = e.response?.data?['detail']?.toString() ?? 'Failed to add contact.';
      _showError(msg);
    } catch (_) {
      _showError('Failed to add contact. Please try again.');
    }
  }

  Widget _buildSOSButton() {
    return Column(
      children: [
        const SizedBox(height: 8),
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (_, child) => Transform.scale(
            scale: _sosLoading ? 1.0 : _pulseAnimation.value,
            child: child,
          ),
          child: GestureDetector(
            onLongPress: _sosLoading ? null : _triggerSOS,
            child: Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.emergencyRed,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x73E53935), // emergencyRed @ 45% opacity
                    blurRadius: 30,
                    spreadRadius: 8,
                  ),
                ],
              ),
              child: _sosLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white))
                  : const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.sos, color: Colors.white, size: 56),
                        SizedBox(height: 4),
                        Text(
                          'HOLD 3s',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Hold for 3 seconds to send SOS',
          style: TextStyle(
              color: AppTheme.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 4),
        const Text(
          'Your GPS location will be shared with contacts',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildAuNumbers() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Australian Emergency Numbers',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ),
        ..._auNumbers.map((n) => _AuNumberTile(
              number: n,
              onCall: () => _callNumber(n.label),
            )),
      ],
    );
  }

  Widget _buildContacts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Emergency Contacts',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                onPressed: _showAddContactDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
        ),
        if (_contactsLoading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_contacts.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              'No emergency contacts added yet.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          )
        else
          ..._contacts.map((c) => _ContactTile(
                contact: c,
                onCall: () => _callNumber(c.phone),
              )),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.emergencyRed,
        title: const Text('Emergency',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        leading: BackButton(color: Colors.white, onPressed: () => Navigator.of(context).maybePop()),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: _loadContacts,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                color: const Color(0x0AE53935), // emergencyRed @ 4% opacity
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: _buildSOSButton(),
              ),
              _buildAuNumbers(),
              _buildContacts(),
              const SizedBox(height: 24),
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
  final IconData icon;

  const _AuNumber({
    required this.label,
    required this.description,
    required this.icon,
  });
}

// ─────────────────────────── Widgets ───────────────────────────

class _AuNumberTile extends StatelessWidget {
  final _AuNumber number;
  final VoidCallback onCall;

  const _AuNumberTile({required this.number, required this.onCall});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0x1AE53935), // emergencyRed @ 10% opacity
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(number.icon, color: AppTheme.emergencyRed, size: 22),
        ),
        title: Text(number.label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Text(number.description,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        trailing: ElevatedButton.icon(
          onPressed: onCall,
          icon: const Icon(Icons.phone, size: 16),
          label: const Text('Call'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.emergencyRed,
            foregroundColor: Colors.white,
            minimumSize: const Size(80, 36),
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
        ),
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  final _EmergencyContact contact;
  final VoidCallback onCall;

  const _ContactTile({required this.contact, required this.onCall});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0x2600897B), // primary @ 15% opacity
          child: Text(
            contact.name.isNotEmpty ? contact.name[0].toUpperCase() : '?',
            style: const TextStyle(
                color: AppTheme.primary, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(contact.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(contact.phone,
                style: const TextStyle(fontSize: 13)),
            Text(contact.relationship,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12)),
          ],
        ),
        isThreeLine: true,
        trailing: IconButton(
          icon: const Icon(Icons.phone, color: AppTheme.primary),
          onPressed: onCall,
          tooltip: 'Call ${contact.name}',
        ),
      ),
    );
  }
}
