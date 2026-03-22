import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/core/theme/app_theme.dart';
import 'package:vitapulse_ai/core/utils/auth_storage.dart';
import 'package:vitapulse_ai/features/auth/data/auth_api.dart';
import 'package:vitapulse_ai/shared/widgets/loading_button.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _loading = true;
  bool _saving = false;
  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _loading = true);
    try {
      final resp = await ApiClient.get('/users/me');
      setState(() => _profile = resp.data as Map<String, dynamic>);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load profile'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Logout', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await AuthApi.logout();
      if (mounted) context.go('/auth/welcome');
    }
  }

  Future<void> _showEditDialog() async {
    if (_profile == null) return;

    final nameCtrl = TextEditingController(text: _profile!['full_name'] ?? '');
    final ageCtrl = TextEditingController(
        text: _profile!['age']?.toString() ?? '');
    final bloodGroupCtrl =
        TextEditingController(text: _profile!['blood_group'] ?? '');
    final conditionsCtrl = TextEditingController(
        text: (_profile!['medical_conditions'] as List<dynamic>?)?.join(', ') ??
            '');
    final allergiesCtrl = TextEditingController(
        text: (_profile!['allergies'] as List<dynamic>?)?.join(', ') ?? '');
    String? selectedGender = _profile!['gender'] as String?;

    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Edit Profile'),
          content: SizedBox(
            width: double.maxFinite,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _dialogField(
                      controller: nameCtrl,
                      label: 'Full Name',
                      validator: (v) => (v?.trim().isEmpty ?? true)
                          ? 'Name is required'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    _dialogField(
                      controller: ageCtrl,
                      label: 'Age',
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedGender,
                      decoration: _inputDecoration('Gender'),
                      items: const [
                        DropdownMenuItem(value: 'Male', child: Text('Male')),
                        DropdownMenuItem(
                            value: 'Female', child: Text('Female')),
                        DropdownMenuItem(
                            value: 'Other', child: Text('Other')),
                      ],
                      onChanged: (v) => setDlgState(() => selectedGender = v),
                    ),
                    const SizedBox(height: 12),
                    _dialogField(
                      controller: bloodGroupCtrl,
                      label: 'Blood Group',
                      hint: 'e.g. A+',
                    ),
                    const SizedBox(height: 12),
                    _dialogField(
                      controller: conditionsCtrl,
                      label: 'Medical Conditions',
                      hint: 'Comma-separated, e.g. Diabetes, Hypertension',
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    _dialogField(
                      controller: allergiesCtrl,
                      label: 'Allergies',
                      hint: 'Comma-separated, e.g. Penicillin, Peanuts',
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                minimumSize: Size.zero,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              onPressed: _saving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDlgState(() => _saving = true);
                      try {
                        final conditions = conditionsCtrl.text
                            .split(',')
                            .map((e) => e.trim())
                            .where((e) => e.isNotEmpty)
                            .toList();
                        final allergies = allergiesCtrl.text
                            .split(',')
                            .map((e) => e.trim())
                            .where((e) => e.isNotEmpty)
                            .toList();

                        final body = {
                          'full_name': nameCtrl.text.trim(),
                          if (ageCtrl.text.trim().isNotEmpty)
                            'age': int.tryParse(ageCtrl.text.trim()),
                          if (selectedGender != null) 'gender': selectedGender,
                          if (bloodGroupCtrl.text.trim().isNotEmpty)
                            'blood_group': bloodGroupCtrl.text.trim(),
                          'medical_conditions': conditions,
                          'allergies': allergies,
                        };

                        final resp =
                            await ApiClient.put('/users/me', data: body);
                        if (mounted) {
                          setState(
                              () => _profile = resp.data as Map<String, dynamic>);
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Profile updated successfully'),
                              backgroundColor: AppTheme.success,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Failed to update profile'),
                              backgroundColor: AppTheme.error,
                            ),
                          );
                        }
                      } finally {
                        setDlgState(() => _saving = false);
                      }
                    },
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Save',
                      style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, {String? hint}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primary, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );

  Widget _dialogField({
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: _inputDecoration(label, hint: hint),
        validator: validator,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit Profile',
            onPressed: _profile != null ? _showEditDialog : null,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _profile == null
              ? _buildError()
              : _buildBody(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppTheme.error),
          const SizedBox(height: 12),
          const Text('Could not load profile',
              style: TextStyle(color: AppTheme.textSecondary)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadProfile,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final p = _profile!;
    final conditions =
        (p['medical_conditions'] as List<dynamic>?)?.cast<String>() ?? [];
    final allergies =
        (p['allergies'] as List<dynamic>?)?.cast<String>() ?? [];

    return RefreshIndicator(
      onRefresh: _loadProfile,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Avatar + name header
          _buildProfileHeader(p),
          const SizedBox(height: 20),

          // Info card
          _buildInfoCard(p),
          const SizedBox(height: 16),

          // Health Conditions
          _buildChipsSection(
            title: 'Medical Conditions',
            icon: Icons.local_hospital_outlined,
            items: conditions,
            emptyText: 'No conditions recorded',
            chipColor: const Color(0xFF1565C0),
          ),
          const SizedBox(height: 16),

          // Allergies
          _buildChipsSection(
            title: 'Allergies',
            icon: Icons.warning_amber_outlined,
            items: allergies,
            emptyText: 'No allergies recorded',
            chipColor: AppTheme.accent,
          ),
          const SizedBox(height: 32),

          // Logout
          LoadingButton(
            text: 'Logout',
            loading: false,
            color: AppTheme.error,
            onPressed: _logout,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(Map<String, dynamic> p) {
    final name = (p['full_name'] as String?) ?? 'User';
    final initials = name
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primaryDark, AppTheme.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: Colors.white24,
            child: Text(
              initials,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                if (p['email'] != null)
                  Text(
                    p['email'] as String,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                if (p['phone'] != null)
                  Text(
                    p['phone'] as String,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(Map<String, dynamic> p) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Personal Information',
                style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            _infoRow(Icons.cake_outlined, 'Age',
                p['age'] != null ? '${p['age']} years' : 'Not set'),
            const SizedBox(height: 10),
            _infoRow(Icons.person_outline, 'Gender',
                (p['gender'] as String?) ?? 'Not set'),
            const SizedBox(height: 10),
            _infoRow(Icons.bloodtype_outlined, 'Blood Group',
                (p['blood_group'] as String?) ?? 'Not set'),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.primary),
        const SizedBox(width: 10),
        Text('$label: ',
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 14)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildChipsSection({
    required String title,
    required IconData icon,
    required List<String> items,
    required String emptyText,
    required Color chipColor,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: chipColor),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 12),
            if (items.isEmpty)
              Text(emptyText,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 13))
            else
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: items
                    .map(
                      (item) => Chip(
                        label: Text(item,
                            style: TextStyle(
                                color: chipColor, fontSize: 12)),
                        backgroundColor: chipColor.withOpacity(0.1),
                        side: BorderSide(
                            color: chipColor.withOpacity(0.3)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 0),
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }
}
