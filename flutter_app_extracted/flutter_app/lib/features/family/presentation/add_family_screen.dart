import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/core/theme/app_theme.dart';
import 'package:vitapulse_ai/shared/widgets/loading_button.dart';

class AddFamilyMemberScreen extends StatefulWidget {
  const AddFamilyMemberScreen({super.key});

  @override
  State<AddFamilyMemberScreen> createState() => _AddFamilyMemberScreenState();
}

class _AddFamilyMemberScreenState extends State<AddFamilyMemberScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _conditionsCtrl = TextEditingController();
  final _allergiesCtrl = TextEditingController();

  String? _relationship;
  String? _gender;
  String? _bloodGroup;
  bool _loading = false;

  static const _relationships = [
    'Spouse',
    'Parent',
    'Child',
    'Sibling',
    'Other',
  ];

  static const _genders = ['Male', 'Female', 'Other'];

  static const _bloodGroups = [
    'A+',
    'A-',
    'B+',
    'B-',
    'AB+',
    'AB-',
    'O+',
    'O-',
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _conditionsCtrl.dispose();
    _allergiesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final conditions = _conditionsCtrl.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final allergies = _allergiesCtrl.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final body = {
        'name': _nameCtrl.text.trim(),
        'relationship': _relationship,
        if (_ageCtrl.text.trim().isNotEmpty)
          'age': int.tryParse(_ageCtrl.text.trim()),
        if (_gender != null) 'gender': _gender,
        if (_bloodGroup != null) 'blood_group': _bloodGroup,
        'medical_conditions': conditions,
        'allergies': allergies,
      };

      await ApiClient.post('/family/', data: body);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Family member added successfully'),
            backgroundColor: AppTheme.success,
          ),
        );
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to add family member'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Family Member')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader('Basic Information'),
              const SizedBox(height: 12),

              // Name
              _label('Full Name *'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'Enter full name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) =>
                    (v?.trim().isEmpty ?? true) ? 'Name is required' : null,
              ),
              const SizedBox(height: 16),

              // Relationship
              _label('Relationship *'),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _relationship,
                decoration: const InputDecoration(
                  hintText: 'Select relationship',
                  prefixIcon: Icon(Icons.family_restroom),
                ),
                items: _relationships
                    .map((r) =>
                        DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) => setState(() => _relationship = v),
                validator: (v) =>
                    v == null ? 'Please select a relationship' : null,
              ),
              const SizedBox(height: 16),

              // Age
              _label('Age'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _ageCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: 'Enter age',
                  prefixIcon: Icon(Icons.cake_outlined),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final n = int.tryParse(v.trim());
                  if (n == null || n <= 0 || n > 150) {
                    return 'Enter a valid age';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Gender
              _label('Gender'),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _gender,
                decoration: const InputDecoration(
                  hintText: 'Select gender',
                  prefixIcon: Icon(Icons.wc_outlined),
                ),
                items: _genders
                    .map((g) =>
                        DropdownMenuItem(value: g, child: Text(g)))
                    .toList(),
                onChanged: (v) => setState(() => _gender = v),
              ),
              const SizedBox(height: 16),

              // Blood Group
              _label('Blood Group'),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _bloodGroup,
                decoration: const InputDecoration(
                  hintText: 'Select blood group',
                  prefixIcon: Icon(Icons.bloodtype_outlined),
                ),
                items: _bloodGroups
                    .map((bg) =>
                        DropdownMenuItem(value: bg, child: Text(bg)))
                    .toList(),
                onChanged: (v) => setState(() => _bloodGroup = v),
              ),
              const SizedBox(height: 24),

              _sectionHeader('Health Information'),
              const SizedBox(height: 12),

              // Medical Conditions
              _label('Medical Conditions'),
              const SizedBox(height: 4),
              const Text(
                'Enter comma-separated values',
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _conditionsCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'e.g. Diabetes, Asthma, Hypertension',
                  alignLabelWithHint: true,
                  prefixIcon: Padding(
                    padding: EdgeInsets.only(bottom: 48),
                    child:
                        Icon(Icons.local_hospital_outlined),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Allergies
              _label('Allergies'),
              const SizedBox(height: 4),
              const Text(
                'Enter comma-separated values',
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _allergiesCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'e.g. Penicillin, Peanuts, Latex',
                  alignLabelWithHint: true,
                  prefixIcon: Padding(
                    padding: EdgeInsets.only(bottom: 48),
                    child: Icon(Icons.warning_amber_outlined),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              LoadingButton(
                text: 'Add Family Member',
                loading: _loading,
                onPressed: _submit,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: AppTheme.textPrimary,
      ),
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 13,
          color: AppTheme.textPrimary),
    );
  }
}
