import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vitapulse_ai/core/error/error_reporter.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/core/utils/auth_storage.dart';
import 'package:vitapulse_ai/core/utils/error_handler.dart';
import 'package:vitapulse_ai/features/auth/data/auth_api.dart';
import 'package:vitapulse_ai/features/profile/data/user_api.dart';
import 'package:vitapulse_ai/shared/widgets/loading_button.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Australian location reference data
// ─────────────────────────────────────────────────────────────────────────────

class _AuLoc {
  static const List<String> states = [
    'ACT', 'NSW', 'NT', 'QLD', 'SA', 'TAS', 'VIC', 'WA',
  ];

  // Nominatim returns full state names — map to abbreviations
  static const Map<String, String> fullToAbbr = {
    'Australian Capital Territory': 'ACT',
    'New South Wales': 'NSW',
    'Northern Territory': 'NT',
    'Queensland': 'QLD',
    'South Australia': 'SA',
    'Tasmania': 'TAS',
    'Victoria': 'VIC',
    'Western Australia': 'WA',
  };

  // Major cities per state (used as search suggestions)
  static const Map<String, List<String>> cities = {
    'ACT': ['Canberra', 'Belconnen', 'Gungahlin', 'Tuggeranong', 'Woden'],
    'NSW': ['Sydney', 'Newcastle', 'Wollongong', 'Parramatta', 'Penrith',
            'Blacktown', 'Liverpool', 'Campbelltown', 'Gosford'],
    'NT':  ['Darwin', 'Alice Springs', 'Palmerston', 'Katherine'],
    'QLD': ['Brisbane', 'Gold Coast', 'Sunshine Coast', 'Townsville',
            'Cairns', 'Toowoomba', 'Rockhampton', 'Mackay', 'Ipswich'],
    'SA':  ['Adelaide', 'Mount Gambier', 'Whyalla', 'Murray Bridge', 'Gawler'],
    'TAS': ['Hobart', 'Launceston', 'Devonport', 'Burnie', 'Ulverstone'],
    'VIC': ['Melbourne', 'Geelong', 'Ballarat', 'Bendigo', 'Shepparton',
            'Ringwood', 'Frankston', 'Dandenong', 'Heidelberg', 'Box Hill',
            'Cranbourne', 'Pakenham', 'Sunbury'],
    'WA':  ['Perth', 'Fremantle', 'Mandurah', 'Bunbury', 'Geraldton',
            'Joondalup', 'Rockingham', 'Armadale'],
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// ProfileScreen
// ─────────────────────────────────────────────────────────────────────────────

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _loading = true;
  bool _loggingOut = false;
  bool _exportingData = false;
  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProfile());
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _loadProfile() async {
    setState(() => _loading = true);
    try {
      final resp = await ApiClient.get('/users/me');
      if (mounted) {
        final data = resp.data as Map<String, dynamic>;
        setState(() => _profile = data);
        // Keep AuthStorage in sync so the home screen avatar is always fresh
        await AuthStorage.saveProfileImageUrl(data['profile_image_url'] as String?);
      }
    } catch (e) {
      ErrorReporter.report(e, StackTrace.current, context: 'profile_load');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ErrorHandler.getMessage(e)),
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Profile picture helpers ────────────────────────────────────────────────

  /// Converts the stored relative path to a full URL using the active backend.
  String? _imageUrl(String? relPath) {
    if (relPath == null || relPath.isEmpty) return null;
    final serverRoot = baseUrl.replaceFirst('/api/v1', '');
    return '$serverRoot/uploads/${relPath.replaceAll(r'\', '/')}';
  }

  /// Opens a bottom sheet for the user to choose camera or gallery,
  /// then uploads the selected image to the backend.
  Future<void> _pickAndUpload() async {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Change Profile Photo',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: cs.primaryContainer,
                child: Icon(Icons.camera_alt, color: hc.prescription),
              ),
              title: const Text('Take a Photo'),
              onTap: () => Navigator.pop(sheetCtx, ImageSource.camera),
            ),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: hc.vitaGood.withValues(alpha: 0.12),
                child: Icon(Icons.photo_library, color: hc.discharge),
              ),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(sheetCtx, ImageSource.gallery),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );

    if (source == null || !mounted) return;

    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    // Show uploading indicator
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          SizedBox(
            width: 18, height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Theme.of(context).colorScheme.onInverseSurface,
            ),
          ),
          const SizedBox(width: 12),
          const Text('Uploading photo…'),
        ],
      ),
      duration: const Duration(seconds: 30),
    ));

    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          picked.path,
          filename: picked.name,
        ),
      });

      final resp = await ApiClient.uploadFile('/users/me/photo', formData);
      final relPath = (resp.data as Map<String, dynamic>)['profile_image_url'] as String?;

      if (mounted) {
        setState(() {
          _profile = {
            ...?_profile,
            'profile_image_url': relPath,
          };
        });
      }
      await AuthStorage.saveProfileImageUrl(relPath);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
            content: Text('Profile photo updated'),
          ));
      }
    } catch (e) {
      ErrorReporter.report(e, StackTrace.current, context: 'profile_photo_upload');
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(ErrorHandler.getMessage(e)),
          ));
      }
    }
  }

  Future<bool> _patchProfile(Map<String, dynamic> body) async {
    try {
      final resp = await ApiClient.put('/users/me', data: body);
      if (mounted) setState(() => _profile = resp.data as Map<String, dynamic>);
      return true;
    } catch (e) {
      ErrorReporter.report(e, StackTrace.current, context: 'profile_patch');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ErrorHandler.getMessage(e)),
        ));
      }
      return false;
    }
  }

  // ── Data export (HN-LEGAL-007) ─────────────────────────────────────────────

  Future<void> _exportMyData() async {
    if (_exportingData) return;
    setState(() => _exportingData = true);
    try {
      final payload = await UserApi.exportMyData();
      await UserApi.shareDataExport(payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your data export is ready to save or share.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ErrorHandler.getMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _exportingData = false);
    }
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  Future<void> _logout() async {
    if (_loggingOut) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Logout',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
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

  // ── Edit personal info (Name / Age / Gender / Blood Group) ────────────────

  Future<void> _showEditPersonalDialog() async {
    if (_profile == null) return;
    final nameCtrl = TextEditingController(text: _profile!['name'] as String? ?? '');
    final ageCtrl  = TextEditingController(text: _profile!['age']?.toString() ?? '');
    String? gender     = _profile!['gender'] as String?;
    String? bloodGroup = _profile!['blood_group'] as String?;
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) {
        bool saving = false;
        return StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
            title: const Text('Personal Information'),
            content: SizedBox(
              width: double.maxFinite,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _field(ctx, nameCtrl, 'Full Name',
                          validator: (v) => (v?.trim().isEmpty ?? true) ? 'Name is required' : null),
                      const SizedBox(height: 12),
                      _field(ctx, ageCtrl, 'Age', keyboard: TextInputType.number,
                          hint: 'e.g. 35'),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: gender,
                        decoration: _deco(ctx, 'Gender'),
                        items: ['Male', 'Female', 'Other', 'Prefer not to say']
                            .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                            .toList(),
                        onChanged: (v) => setS(() => gender = v),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: bloodGroup,
                        decoration: _deco(ctx, 'Blood Group'),
                        items: ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']
                            .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                            .toList(),
                        onChanged: (v) => setS(() => bloodGroup = v),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                onPressed: saving ? null : () async {
                  if (!formKey.currentState!.validate()) return;
                  setS(() => saving = true);
                  final ok = await _patchProfile({
                    'name': nameCtrl.text.trim(),
                    if (ageCtrl.text.trim().isNotEmpty)
                      'age': int.tryParse(ageCtrl.text.trim()),
                    if (gender != null) 'gender': gender,
                    if (bloodGroup != null) 'blood_group': bloodGroup,
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (ok && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Personal info updated'),
                    ));
                  }
                },
                child: saving
                    ? SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                          color: Theme.of(ctx).colorScheme.onPrimary,
                          strokeWidth: 2,
                        ))
                    : const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
    nameCtrl.dispose();
    ageCtrl.dispose();
  }

  // ── Address editor with GPS auto-fill ─────────────────────────────────────

  Future<void> _showAddressSheet() async {
    if (_profile == null) return;
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AddressSheet(profile: _profile!),
    );
    if (result != null && mounted) {
      final ok = await _patchProfile(result);
      if (ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Address updated'),
        ));
      }
    }
  }

  // ── Chip editor for Medical Conditions / Allergies ────────────────────────

  Future<void> _showChipEditor({
    required String field,
    required String title,
    required List<String> current,
    required Color chipColor,
    required String hint,
  }) async {
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ChipEditorSheet(
        title: title,
        items: List<String>.from(current),
        chipColor: chipColor,
        hint: hint,
      ),
    );
    if (result != null && mounted) {
      final ok = await _patchProfile({field: result});
      if (ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$title updated'),
        ));
      }
    }
  }

  // ── OTP-verified contact change ───────────────────────────────────────────

  Future<void> _showChangeContactDialog(String contactType) async {
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ContactChangeDialog(contactType: contactType),
    );
    if (result != null && mounted) {
      setState(() => _profile = result);
      final label = contactType == 'email' ? 'Email' : 'Phone number';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('$label updated successfully'),
        ));
    }
  }

  // ── Alt phone ─────────────────────────────────────────────────────────────

  Future<void> _showPhone2Dialog() async {
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _Phone2Dialog(current: _profile?['phone2'] as String? ?? ''),
    );
    if (result != null && mounted) {
      setState(() => _profile = result);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Alternate phone updated'),
        ));
    }
  }

  // ── Input decoration helpers ──────────────────────────────────────────────

  InputDecoration _deco(BuildContext context, String label, {String? hint}) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: cs.surfaceContainerHighest,
      border: OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: cs.outline)),
      enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: cs.outline)),
      focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: cs.primary, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Widget _field(
    BuildContext context,
    TextEditingController ctrl,
    String label, {
    String? hint,
    int maxLines = 1,
    TextInputType keyboard = TextInputType.text,
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: ctrl,
        maxLines: maxLines,
        keyboardType: keyboard,
        decoration: _deco(context, label, hint: hint),
        validator: validator,
      );

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        centerTitle: true,
        leading: BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _profile == null
              ? _buildError()
              : _buildBody(),
    );
  }

  Widget _buildError() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: cs.error),
          const SizedBox(height: 12),
          Text('Could not load profile',
              style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 16),
          FilledButton(onPressed: _loadProfile, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final p = _profile!;
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);
    final conditions = (p['health_conditions'] as List<dynamic>?)?.cast<String>() ?? [];
    final allergies  = (p['allergies'] as List<dynamic>?)?.cast<String>() ?? [];

    return RefreshIndicator(
      onRefresh: _loadProfile,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildProfileHeader(p),
          const SizedBox(height: 20),
          _buildInfoCard(p),
          const SizedBox(height: 16),
          _buildAddressCard(p),
          const SizedBox(height: 16),
          _buildContactCard(p),
          const SizedBox(height: 16),
          _buildChipsCard(
            title: 'Medical Conditions',
            icon: Icons.local_hospital_outlined,
            items: conditions,
            emptyText: 'Tap + to add medical conditions',
            chipColor: hc.prescription,
            onEdit: () => _showChipEditor(
              field: 'health_conditions',
              title: 'Medical Conditions',
              current: conditions,
              chipColor: hc.prescription,
              hint: 'e.g. Diabetes, Hypertension',
            ),
          ),
          const SizedBox(height: 16),
          _buildChipsCard(
            title: 'Allergies',
            icon: Icons.warning_amber_outlined,
            items: allergies,
            emptyText: 'Tap + to add allergies',
            chipColor: hc.vitaWarning,
            onEdit: () => _showChipEditor(
              field: 'allergies',
              title: 'Allergies',
              current: allergies,
              chipColor: hc.vitaWarning,
              hint: 'e.g. Penicillin, Peanuts, Latex',
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: _exportingData
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined),
            title: const Text('Export my data'),
            subtitle: const Text('Download a copy of your HealthNest data'),
            onTap: _exportingData ? null : _exportMyData,
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy policy'),
            onTap: () => context.push('/legal/privacy'),
          ),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: const Text('Terms of use'),
            onTap: () => context.push('/legal/terms'),
          ),
          ListTile(
            leading: Icon(Icons.delete_forever_outlined, color: cs.error),
            title: Text('Delete account', style: TextStyle(color: cs.error)),
            onTap: () => context.push('/legal/delete-account'),
          ),
          const SizedBox(height: 16),
          LoadingButton(
            text: 'Logout',
            loading: false,
            color: cs.error,
            onPressed: _logout,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Profile header ────────────────────────────────────────────────────────

  Widget _buildProfileHeader(Map<String, dynamic> p) {
    final cs = Theme.of(context).colorScheme;
    final name     = (p['name'] as String?) ?? 'User';
    final relPath  = p['profile_image_url'] as String?;
    final imageUrl = _imageUrl(relPath);
    final initials = name.trim().split(RegExp(r'\s+')).take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color.lerp(cs.primary, Colors.black, 0.30)!, cs.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppRadius.brLg,
      ),
      child: Row(
        children: [
          // ── Avatar with camera overlay ─────────────────────────────────
          Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.onPrimary, width: 2.5),
                ),
                child: CircleAvatar(
                  radius: 38,
                  backgroundColor: cs.onPrimary.withValues(alpha: 0.24),
                  child: imageUrl != null
                      ? ClipOval(
                          child: CachedNetworkImage(
                            imageUrl: imageUrl,
                            width: 76,
                            height: 76,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => _initialsWidget(initials, 38),
                            errorWidget:   (_, __, ___) => _initialsWidget(initials, 38),
                          ),
                        )
                      : _initialsWidget(initials, 38),
                ),
              ),
              // Camera badge button — min 36×36 for accessibility
              Positioned(
                right: 0,
                bottom: 0,
                child: Semantics(
                  label: 'Change profile photo',
                  button: true,
                  child: GestureDetector(
                    onTap: _pickAndUpload,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: cs.surface,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 4),
                        ],
                      ),
                      child: Icon(Icons.camera_alt,
                          size: 18, color: cs.primary),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          // ── Name + contact info ────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: TextStyle(fontSize: 20,
                        fontWeight: FontWeight.bold, color: cs.onPrimary),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1),
                const SizedBox(height: 4),
                if (p['email'] != null)
                  Text(p['email'] as String,
                      style: TextStyle(
                          color: cs.onPrimary.withValues(alpha: 0.70),
                          fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1),
                if (p['phone'] != null)
                  Text(p['phone'] as String,
                      style: TextStyle(
                          color: cs.onPrimary.withValues(alpha: 0.70),
                          fontSize: 13)),
                const SizedBox(height: 8),
                // Tap to change photo hint
                GestureDetector(
                  onTap: _pickAndUpload,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit, size: 12,
                          color: cs.onPrimary.withValues(alpha: 0.60)),
                      const SizedBox(width: 4),
                      Text('Change photo',
                          style: TextStyle(
                              color: cs.onPrimary.withValues(alpha: 0.60),
                              fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _initialsWidget(String initials, double radius) => Center(
        child: Text(
          initials,
          style: TextStyle(
            fontSize: radius * 0.63,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      );

  // ── Personal info card ────────────────────────────────────────────────────

  Widget _buildInfoCard(Map<String, dynamic> p) {
    final cs = Theme.of(context).colorScheme;
    return _card(
      title: 'Personal Information',
      icon: Icons.person_outline,
      iconColor: cs.primary,
      trailing: IconButton(
        icon: Icon(Icons.edit_outlined, size: 18, color: cs.primary),
        tooltip: 'Edit personal info',
        onPressed: _showEditPersonalDialog,
      ),
      children: [
        _infoRow(Icons.badge_outlined, 'Name',
            (p['name'] as String?) ?? 'Not set'),
        _infoRow(Icons.cake_outlined, 'Age',
            p['age'] != null ? '${p['age']} years' : 'Not set'),
        _infoRow(Icons.person_outline, 'Gender',
            (p['gender'] as String?) ?? 'Not set'),
        _infoRow(Icons.bloodtype_outlined, 'Blood Group',
            (p['blood_group'] as String?) ?? 'Not set'),
      ],
    );
  }

  // ── Address card ──────────────────────────────────────────────────────────

  Widget _buildAddressCard(Map<String, dynamic> p) {
    final cs = Theme.of(context).colorScheme;
    final parts = <String>[
      if (p['suburb'] != null && (p['suburb'] as String).isNotEmpty)
        p['suburb'] as String,
      if (p['city'] != null && (p['city'] as String).isNotEmpty)
        p['city'] as String,
      if (p['state'] != null && (p['state'] as String).isNotEmpty)
        p['state'] as String,
      if (p['postcode'] != null && (p['postcode'] as String).isNotEmpty)
        p['postcode'] as String,
    ];
    final addressText = parts.isEmpty ? 'Not set' : parts.join(', ');

    return _card(
      title: 'Address',
      icon: Icons.location_on_outlined,
      iconColor: cs.primary,
      trailing: IconButton(
        icon: Icon(Icons.edit_outlined, size: 18, color: cs.primary),
        tooltip: 'Edit address',
        onPressed: _showAddressSheet,
      ),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.home_outlined, size: 18, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(addressText,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ],
    );
  }

  // ── Contact card ──────────────────────────────────────────────────────────

  Widget _buildContactCard(Map<String, dynamic> p) {
    final cs = Theme.of(context).colorScheme;
    return _card(
      title: 'Contact Details',
      icon: Icons.contact_mail_outlined,
      iconColor: cs.primary,
      children: [
        _contactRow(Icons.email_outlined, 'Email',
            (p['email'] as String?) ?? 'Not set',
            () => _showChangeContactDialog('email')),
        _contactRow(Icons.phone_outlined, 'Phone',
            (p['phone'] as String?) ?? 'Not set',
            () => _showChangeContactDialog('phone')),
        _contactRow(Icons.phone_forwarded_outlined, 'Alt Phone',
            (p['phone2'] as String?) ?? 'Not set',
            _showPhone2Dialog),
      ],
    );
  }

  // ── Chips card (conditions / allergies) ───────────────────────────────────

  Widget _buildChipsCard({
    required String title,
    required IconData icon,
    required List<String> items,
    required String emptyText,
    required Color chipColor,
    required VoidCallback onEdit,
  }) {
    return _card(
      title: title,
      icon: icon,
      iconColor: chipColor,
      trailing: IconButton(
        icon: Icon(Icons.add_circle_outline, size: 20, color: chipColor),
        tooltip: 'Edit $title',
        onPressed: onEdit,
      ),
      children: [
        if (items.isEmpty)
          GestureDetector(
            onTap: onEdit,
            child: Text(emptyText,
                style: TextStyle(color: chipColor.withValues(alpha: 0.6),
                    fontSize: 13, fontStyle: FontStyle.italic)),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: items.map((item) {
              // ConstrainedBox prevents a single chip from exceeding the
              // available row width in the Wrap (Wrap passes unbounded
              // constraints to children, which can cause overflow for long labels).
              return ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Chip(
                  label: Text(item,
                      style: TextStyle(color: chipColor, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1),
                  backgroundColor: chipColor.withValues(alpha: 0.1),
                  side: BorderSide(color: chipColor.withValues(alpha: 0.3)),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  deleteIcon: Icon(Icons.close, size: 14, color: chipColor),
                  onDeleted: () {
                    final updated = List<String>.from(items)..remove(item);
                    final field = title == 'Medical Conditions'
                        ? 'health_conditions' : 'allergies';
                    _patchProfile({field: updated});
                  },
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  // ── Card scaffold ─────────────────────────────────────────────────────────

  Widget _card({
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<Widget> children,
    Widget? trailing,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: iconColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 12),
            ...children.expand((w) => [w, const SizedBox(height: 10)]).toList()
              ..removeLast(),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 10),
        Text('$label: ',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
        Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w500, fontSize: 14))),
      ],
    );
  }

  Widget _contactRow(IconData icon, String label, String value, VoidCallback onEdit) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 10),
        Text('$label: ',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
        Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w500, fontSize: 14),
                overflow: TextOverflow.ellipsis)),
        IconButton(
          icon: const Icon(Icons.edit_outlined, size: 16),
          color: cs.primary,
          tooltip: 'Change $label',
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: EdgeInsets.zero,
          onPressed: onEdit,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AddressSheet — GPS auto-fill + Australian state/suburb/postcode editor
// ─────────────────────────────────────────────────────────────────────────────

class _AddressSheet extends StatefulWidget {
  final Map<String, dynamic> profile;
  const _AddressSheet({required this.profile});

  @override
  State<_AddressSheet> createState() => _AddressSheetState();
}

class _AddressSheetState extends State<_AddressSheet> {
  late final TextEditingController _suburbCtrl;
  late final TextEditingController _cityCtrl;
  late final TextEditingController _postcodeCtrl;
  String? _selectedState;
  bool _gpsLoading = false;
  String? _gpsStatus;

  static const _nominatimReverse = 'https://nominatim.openstreetmap.org/reverse';

  @override
  void initState() {
    super.initState();
    _suburbCtrl  = TextEditingController(text: widget.profile['suburb']  as String? ?? '');
    _cityCtrl    = TextEditingController(text: widget.profile['city']    as String? ?? '');
    _postcodeCtrl= TextEditingController(text: widget.profile['postcode']as String? ?? '');
    final rawState = widget.profile['state'] as String? ?? '';
    // Normalise stored full name → abbr if needed
    _selectedState = _AuLoc.fullToAbbr[rawState] ??
        (_AuLoc.states.contains(rawState) ? rawState : null);
  }

  @override
  void dispose() {
    _suburbCtrl.dispose();
    _cityCtrl.dispose();
    _postcodeCtrl.dispose();
    super.dispose();
  }

  // ── GPS reverse-geocode ───────────────────────────────────────────────────

  Future<void> _autoFillFromGps() async {
    setState(() { _gpsLoading = true; _gpsStatus = 'Requesting location…'; });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() { _gpsLoading = false; _gpsStatus = 'Location services are disabled.'; });
        return;
      }

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        if (mounted) setState(() { _gpsLoading = false; _gpsStatus = 'Location permission denied.'; });
        return;
      }

      if (mounted) setState(() => _gpsStatus = 'Getting your location…');
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      ).timeout(const Duration(seconds: 12));

      if (mounted) setState(() => _gpsStatus = 'Looking up address…');

      // Reverse geocode via Nominatim
      final resp = await Dio().get(
        _nominatimReverse,
        queryParameters: {
          'lat': pos.latitude,
          'lon': pos.longitude,
          'format': 'json',
          'addressdetails': '1',
        },
        options: Options(
          headers: {'User-Agent': 'HealthNest/1.0'},
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      final addr = (resp.data as Map<String, dynamic>)['address'] as Map<String, dynamic>?;
      if (addr == null || addr['country_code'] != 'au') {
        if (mounted) {
          setState(() {
            _gpsLoading = false;
            _gpsStatus = 'Could not detect an Australian address.';
          });
        }
        return;
      }

      final suburb  = (addr['suburb'] ?? addr['neighbourhood'] ?? addr['hamlet'] ?? '') as String;
      final city    = (addr['city'] ?? addr['town'] ?? addr['city_district'] ?? '') as String;
      final stateFull = (addr['state'] ?? '') as String;
      final postcode  = (addr['postcode'] ?? '') as String;
      final stateAbbr = _AuLoc.fullToAbbr[stateFull];

      if (mounted) {
        setState(() {
          _gpsLoading = false;
          _gpsStatus = null;
          _suburbCtrl.text  = suburb;
          _cityCtrl.text    = city;
          _postcodeCtrl.text= postcode;
          if (stateAbbr != null) _selectedState = stateAbbr;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _gpsLoading = false;
          _gpsStatus = 'GPS failed. Please enter address manually.';
        });
      }
    }
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  void _save() {
    final body = <String, dynamic>{
      'suburb'  : _suburbCtrl.text.trim(),
      'city'    : _cityCtrl.text.trim(),
      'state'   : _selectedState ?? '',
      'postcode': _postcodeCtrl.text.trim(),
    };
    Navigator.pop(context, body);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(width: 40, height: 4,
                decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 16),

          // Title + GPS button
          Row(
            children: [
              Icon(Icons.location_on_outlined, color: cs.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Address',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: _gpsLoading ? null : _autoFillFromGps,
                icon: _gpsLoading
                    ? SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(
                          color: cs.onPrimary, strokeWidth: 2))
                    : const Icon(Icons.my_location, size: 16),
                label: Text(_gpsLoading ? 'Locating…' : 'Use GPS'),
              ),
            ],
          ),

          // GPS status message
          if (_gpsStatus != null) ...[
            const SizedBox(height: 6),
            Text(_gpsStatus!,
                style: TextStyle(
                    fontSize: 12,
                    color: _gpsStatus!.contains('failed') || _gpsStatus!.contains('denied')
                        ? cs.error : cs.onSurfaceVariant)),
          ],

          const SizedBox(height: 16),

          // State dropdown
          DropdownButtonFormField<String>(
            initialValue: _selectedState,
            decoration: _deco(context, 'State *'),
            items: _AuLoc.states.map((s) => DropdownMenuItem(
              value: s,
              child: Text(s),
            )).toList(),
            onChanged: (v) => setState(() { _selectedState = v; _cityCtrl.clear(); }),
          ),

          const SizedBox(height: 12),

          // City — autocomplete from selected state
          Autocomplete<String>(
            initialValue: TextEditingValue(text: _cityCtrl.text),
            optionsBuilder: (value) {
              if (value.text.isEmpty || _selectedState == null) return [];
              final cities = _AuLoc.cities[_selectedState!] ?? [];
              return cities.where((c) =>
                  c.toLowerCase().startsWith(value.text.toLowerCase()));
            },
            onSelected: (sel) => setState(() => _cityCtrl.text = sel),
            fieldViewBuilder: (ctx, ctrl, focus, onSubmit) {
              // Sync external controller
              ctrl.text = _cityCtrl.text;
              ctrl.addListener(() => _cityCtrl.text = ctrl.text);
              return TextField(
                controller: ctrl,
                focusNode: focus,
                decoration: _deco(context, 'City / Town'),
              );
            },
          ),

          const SizedBox(height: 12),

          // Suburb
          TextField(
            controller: _suburbCtrl,
            decoration: _deco(context, 'Suburb'),
            textCapitalization: TextCapitalization.words,
          ),

          const SizedBox(height: 12),

          // Postcode
          TextField(
            controller: _postcodeCtrl,
            decoration: _deco(context, 'Postcode', hint: '4-digit AU postcode'),
            keyboardType: TextInputType.number,
            maxLength: 4,
          ),

          const SizedBox(height: 4),

          // Save / Cancel
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _deco(BuildContext context, String label, {String? hint}) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: cs.surfaceContainerHighest,
      counterText: '',
      border: OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: cs.outline)),
      enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: cs.outline)),
      focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: cs.primary, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ChipEditorSheet — add/remove items (conditions or allergies)
// ─────────────────────────────────────────────────────────────────────────────

class _ChipEditorSheet extends StatefulWidget {
  final String title;
  final List<String> items;
  final Color chipColor;
  final String hint;
  const _ChipEditorSheet({
    required this.title,
    required this.items,
    required this.chipColor,
    required this.hint,
  });

  @override
  State<_ChipEditorSheet> createState() => _ChipEditorSheetState();
}

class _ChipEditorSheetState extends State<_ChipEditorSheet> {
  late List<String> _items;
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _items = List<String>.from(widget.items);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _add() {
    final val = _ctrl.text.trim();
    if (val.isEmpty) return;
    // Support comma-separated bulk entry
    final parts = val.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);
    setState(() {
      for (final p in parts) {
        if (!_items.any((i) => i.toLowerCase() == p.toLowerCase())) {
          _items.add(p);
        }
      }
      _ctrl.clear();
    });
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 16),

          // Title
          Row(
            children: [
              Icon(widget.title == 'Medical Conditions'
                  ? Icons.local_hospital_outlined
                  : Icons.warning_amber_outlined,
                  color: widget.chipColor, size: 20),
              const SizedBox(width: 8),
              Text(widget.title,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Text('Tap × on a chip to remove. Separate multiple items with commas.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          const SizedBox(height: 14),

          // Current chips
          if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text('No items added yet.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13,
                      fontStyle: FontStyle.italic)),
            )
          else
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: _items.map((item) => ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 240),
                    child: Chip(
                      label: Text(item,
                          style: TextStyle(
                              color: widget.chipColor, fontSize: 13,
                              fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1),
                      backgroundColor: widget.chipColor.withValues(alpha: 0.1),
                      side: BorderSide(color: widget.chipColor.withValues(alpha: 0.4)),
                      deleteIcon: Icon(Icons.close, size: 16, color: widget.chipColor),
                      onDeleted: () => setState(() => _items.remove(item)),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  )).toList(),
                ),
              ),
            ),

          const SizedBox(height: 12),

          // Add field
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                    filled: true,
                    fillColor: cs.surfaceContainerHighest,
                    border: OutlineInputBorder(
                        borderRadius: AppRadius.brMd,
                        borderSide: BorderSide(color: cs.outline)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: AppRadius.brMd,
                        borderSide: BorderSide(color: cs.outline)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: AppRadius.brMd,
                        borderSide: BorderSide(color: widget.chipColor, width: 2)),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: widget.chipColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: const RoundedRectangleBorder(
                      borderRadius: AppRadius.brMd),
                ),
                onPressed: _add,
                child: const Icon(Icons.add),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Cancel / Save
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: widget.chipColor,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(context, _items),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ContactChangeDialog  — OTP-verified email or phone change (unchanged)
// ─────────────────────────────────────────────────────────────────────────────

class _ContactChangeDialog extends StatefulWidget {
  final String contactType;
  const _ContactChangeDialog({required this.contactType});

  @override
  State<_ContactChangeDialog> createState() => _ContactChangeDialogState();
}

class _ContactChangeDialogState extends State<_ContactChangeDialog> {
  final _newValueCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  int _step = 0;
  bool _saving = false;
  String? _errorMsg;

  @override
  void dispose() {
    _newValueCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  String get _label => widget.contactType == 'email' ? 'Email' : 'Phone Number';
  String get _hint  => widget.contactType == 'email' ? 'new@example.com' : '+61412345678';
  TextInputType get _keyboardType => widget.contactType == 'email'
      ? TextInputType.emailAddress : TextInputType.phone;
  String _mask(String v) => v.length <= 4 ? '****' : '${v.substring(0, 4)}****';

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _saving = true; _errorMsg = null; });
    try {
      if (_step == 0) {
        await ApiClient.post('/users/me/request-contact-change', data: {
          'contact_type': widget.contactType,
          'new_value': _newValueCtrl.text.trim(),
        });
        if (mounted) setState(() { _step = 1; _saving = false; });
      } else {
        final resp = await ApiClient.post('/users/me/confirm-contact-change', data: {
          'contact_type': widget.contactType,
          'new_value': _newValueCtrl.text.trim(),
          'otp_code': _otpCtrl.text.trim(),
        });
        if (mounted) Navigator.pop(context, resp.data as Map<String, dynamic>);
      }
    } catch (e) {
      ErrorReporter.report(e, StackTrace.current, context: 'contact_change');
      if (mounted) setState(() { _saving = false; _errorMsg = ErrorHandler.getMessage(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(_step == 0 ? 'Change $_label' : 'Verify New $_label'),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_step == 0) ...[
                Text('Enter your new $_label. We\'ll send a verification code.',
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.5)),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _newValueCtrl,
                  keyboardType: _keyboardType,
                  autofocus: true,
                  decoration: _inputDeco(context, 'New $_label', hint: _hint),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Please enter a $_label' : null,
                ),
              ] else ...[
                Text('Enter the 6-digit code sent to ${_mask(_newValueCtrl.text.trim())}.',
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.5)),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _otpCtrl,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  maxLength: 6,
                  decoration: _inputDeco(context, 'Verification Code', hint: '6-digit code'),
                  validator: (v) => (v == null || v.trim().length != 6)
                      ? 'Enter the 6-digit code' : null,
                ),
              ],
              if (_errorMsg != null) ...[
                const SizedBox(height: 8),
                Text(_errorMsg!,
                    style: TextStyle(color: cs.error, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (_step == 1)
          TextButton(
            onPressed: _saving ? null : () => setState(() {
              _step = 0; _otpCtrl.clear(); _errorMsg = null;
            }),
            child: const Text('Back'),
          ),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          onPressed: _saving ? null : _submit,
          child: _saving
              ? SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(color: cs.onPrimary, strokeWidth: 2))
              : Text(_step == 0 ? 'Send Code' : 'Verify & Update'),
        ),
      ],
    );
  }

  InputDecoration _inputDeco(BuildContext context, String label, {String? hint}) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label, hintText: hint,
      filled: true, fillColor: cs.surfaceContainerHighest,
      border: OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: cs.outline)),
      enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: cs.outline)),
      focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: cs.primary, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _Phone2Dialog  — edit secondary phone (no OTP required, unchanged)
// ─────────────────────────────────────────────────────────────────────────────

class _Phone2Dialog extends StatefulWidget {
  final String current;
  const _Phone2Dialog({required this.current});

  @override
  State<_Phone2Dialog> createState() => _Phone2DialogState();
}

class _Phone2DialogState extends State<_Phone2Dialog> {
  late final TextEditingController _ctrl;
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.current);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _saving = true; _errorMsg = null; });
    try {
      final phone2 = _ctrl.text.trim().isEmpty ? '' : _ctrl.text.trim();
      final resp = await ApiClient.put('/users/me', data: {'phone2': phone2});
      if (mounted) Navigator.pop(context, resp.data as Map<String, dynamic>);
    } catch (e) {
      ErrorReporter.report(e, StackTrace.current, context: 'phone2_update');
      if (mounted) setState(() { _saving = false; _errorMsg = ErrorHandler.getMessage(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Alternate Phone Number'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter a secondary phone number (optional). Leave blank to remove.',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.5),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _ctrl,
              keyboardType: TextInputType.phone,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Alt Phone', hintText: '+61412345678 or leave blank',
                filled: true, fillColor: cs.surfaceContainerHighest,
                border: OutlineInputBorder(
                    borderRadius: AppRadius.brMd,
                    borderSide: BorderSide(color: cs.outline)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: AppRadius.brMd,
                    borderSide: BorderSide(color: cs.outline)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: AppRadius.brMd,
                    borderSide: BorderSide(color: cs.primary, width: 2)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              validator: (v) {
                if (v != null && v.trim().isNotEmpty) {
                  if (v.trim().replaceAll(RegExp(r'\D'), '').length < 8) {
                    return 'Phone must be at least 8 digits';
                  }
                }
                return null;
              },
            ),
            if (_errorMsg != null) ...[
              const SizedBox(height: 8),
              Text(_errorMsg!, style: TextStyle(color: cs.error, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          onPressed: _saving ? null : _save,
          child: _saving
              ? SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(color: cs.onPrimary, strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}
