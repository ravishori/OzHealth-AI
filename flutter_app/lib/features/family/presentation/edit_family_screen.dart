import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/core/utils/error_handler.dart';
import 'package:vitapulse_ai/shared/widgets/loading_button.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';

/// HN-FAMILY-002 — edit an existing family member via `PUT /family/{id}`.
class EditFamilyMemberScreen extends StatefulWidget {
  const EditFamilyMemberScreen({
    super.key,
    required this.memberId,
    this.initialMember,
  });

  final int memberId;
  final Map<String, dynamic>? initialMember;

  @override
  State<EditFamilyMemberScreen> createState() => _EditFamilyMemberScreenState();
}

class _EditFamilyMemberScreenState extends State<EditFamilyMemberScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _conditionsCtrl = TextEditingController();
  final _allergiesCtrl = TextEditingController();

  String? _relationship;
  String? _gender;
  String? _bloodGroup;
  bool _loadingMember = true;
  bool _saving = false;
  String? _loadError;

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
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final seed = widget.initialMember;
    if (seed != null && seed['id'] == widget.memberId) {
      _applyMember(seed);
      setState(() {
        _loadingMember = false;
        _loadError = null;
      });
      return;
    }
    await _fetchMember();
  }

  Future<void> _fetchMember() async {
    setState(() {
      _loadingMember = true;
      _loadError = null;
    });
    try {
      final resp = await ApiClient.get('/family/${widget.memberId}');
      if (!mounted) return;
      _applyMember(resp.data as Map<String, dynamic>);
      setState(() => _loadingMember = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMember = false;
        _loadError = ErrorHandler.getMessage(e);
      });
    }
  }

  void _applyMember(Map<String, dynamic> m) {
    _nameCtrl.text = (m['name'] as String?) ?? '';
    final age = m['age'];
    _ageCtrl.text = age == null ? '' : '$age';
    final conditions =
        (m['medical_conditions'] as List<dynamic>?)?.cast<String>() ?? [];
    final allergies =
        (m['allergies'] as List<dynamic>?)?.cast<String>() ?? [];
    _conditionsCtrl.text = conditions.join(', ');
    _allergiesCtrl.text = allergies.join(', ');

    final rel = m['relationship'] as String?;
    _relationship = _relationships.contains(rel) ? rel : rel;
    final gender = m['gender'] as String?;
    _gender = _genders.contains(gender) ? gender : gender;
    final bg = m['blood_group'] as String?;
    _bloodGroup = _bloodGroups.contains(bg) ? bg : bg;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _conditionsCtrl.dispose();
    _allergiesCtrl.dispose();
    super.dispose();
  }

  void _leave({required bool saved}) {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      if (router.canPop()) {
        router.pop(saved);
      }
      return;
    }
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop(saved);
    }
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
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

      final body = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'relationship': _relationship,
        'age': _ageCtrl.text.trim().isEmpty
            ? null
            : int.tryParse(_ageCtrl.text.trim()),
        'gender': _gender,
        'blood_group': _bloodGroup,
        'medical_conditions': conditions,
        'allergies': allergies,
      };

      await ApiClient.put('/family/${widget.memberId}', data: body);

      if (!mounted) return;
      final hc = HealthcareColors.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Family member updated'),
          backgroundColor: hc.vitaGood,
        ),
      );
      _leave(saved: true);
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ErrorHandler.getMessage(e)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to update family member'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Family Member'),
        leading: BackButton(
          onPressed: _saving ? null : () => _leave(saved: false),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => _leave(saved: false),
            child: const Text('Cancel'),
          ),
        ],
      ),
      body: _loadingMember
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? _buildLoadError(cs)
              : Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionHeader('Basic Information'),
                              const SizedBox(height: 12),
                              _label('Full Name *'),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _nameCtrl,
                                enabled: !_saving,
                                textCapitalization: TextCapitalization.words,
                                decoration: const InputDecoration(
                                  hintText: 'Enter full name',
                                  prefixIcon: Icon(Icons.person_outline),
                                ),
                                validator: (v) => (v?.trim().isEmpty ?? true)
                                    ? 'Name is required'
                                    : null,
                              ),
                              const SizedBox(height: 16),
                              _label('Relationship *'),
                              const SizedBox(height: 6),
                              FormField<String>(
                                initialValue: _relationship,
                                validator: (v) =>
                                    v == null || v.trim().isEmpty
                                        ? 'Please select a relationship'
                                        : null,
                                builder: (field) => InputDecorator(
                                  decoration: InputDecoration(
                                    hintText: 'Select relationship',
                                    prefixIcon:
                                        const Icon(Icons.family_restroom),
                                    errorText: field.errorText,
                                  ),
                                  isEmpty: _relationship == null,
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _relationships
                                              .contains(_relationship)
                                          ? _relationship
                                          : null,
                                      isDense: true,
                                      isExpanded: true,
                                      hint: Text(_relationship ??
                                          'Select relationship'),
                                      items: _relationships
                                          .map((r) => DropdownMenuItem(
                                              value: r, child: Text(r)))
                                          .toList(),
                                      onChanged: _saving
                                          ? null
                                          : (v) {
                                              setState(
                                                  () => _relationship = v);
                                              field.didChange(v);
                                            },
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              _label('Age'),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _ageCtrl,
                                enabled: !_saving,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  hintText: 'Enter age',
                                  prefixIcon: Icon(Icons.cake_outlined),
                                ),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return null;
                                  }
                                  final n = int.tryParse(v.trim());
                                  if (n == null || n <= 0 || n > 150) {
                                    return 'Enter a valid age';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              _label('Gender'),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 4),
                                decoration: BoxDecoration(
                                  border: Border.all(color: cs.outline),
                                  borderRadius: AppRadius.brMd,
                                ),
                                child: DropdownButton<String>(
                                  value: _genders.contains(_gender)
                                      ? _gender
                                      : null,
                                  isExpanded: true,
                                  underline: const SizedBox(),
                                  hint: Text(_gender ?? 'Select gender'),
                                  items: _genders
                                      .map((g) => DropdownMenuItem(
                                          value: g, child: Text(g)))
                                      .toList(),
                                  onChanged: _saving
                                      ? null
                                      : (v) => setState(() => _gender = v),
                                ),
                              ),
                              const SizedBox(height: 16),
                              _label('Blood Group'),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 4),
                                decoration: BoxDecoration(
                                  border: Border.all(color: cs.outline),
                                  borderRadius: AppRadius.brMd,
                                ),
                                child: DropdownButton<String>(
                                  value: _bloodGroups.contains(_bloodGroup)
                                      ? _bloodGroup
                                      : null,
                                  isExpanded: true,
                                  underline: const SizedBox(),
                                  hint: Text(
                                      _bloodGroup ?? 'Select blood group'),
                                  items: _bloodGroups
                                      .map((bg) => DropdownMenuItem(
                                          value: bg, child: Text(bg)))
                                      .toList(),
                                  onChanged: _saving
                                      ? null
                                      : (v) =>
                                          setState(() => _bloodGroup = v),
                                ),
                              ),
                              const SizedBox(height: 24),
                              _sectionHeader('Health Information'),
                              const SizedBox(height: 12),
                              _label('Medical Conditions'),
                              const SizedBox(height: 4),
                              Text(
                                'Enter comma-separated values',
                                style: TextStyle(
                                    color: cs.onSurfaceVariant, fontSize: 12),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _conditionsCtrl,
                                enabled: !_saving,
                                maxLines: 3,
                                decoration: const InputDecoration(
                                  hintText:
                                      'e.g. Diabetes, Asthma, Hypertension',
                                  alignLabelWithHint: true,
                                ),
                              ),
                              const SizedBox(height: 16),
                              _label('Allergies'),
                              const SizedBox(height: 4),
                              Text(
                                'Enter comma-separated values',
                                style: TextStyle(
                                    color: cs.onSurfaceVariant, fontSize: 12),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _allergiesCtrl,
                                enabled: !_saving,
                                maxLines: 3,
                                decoration: const InputDecoration(
                                  hintText: 'e.g. Penicillin, Peanuts, Latex',
                                  alignLabelWithHint: true,
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      ),
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              LoadingButton(
                                text: 'Save Changes',
                                loading: _saving,
                                onPressed: _submit,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildLoadError(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: cs.error),
            const SizedBox(height: 12),
            Text(
              _loadError ?? 'Could not load family member',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurface),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _fetchMember,
              child: const Text('Retry'),
            ),
            TextButton(
              onPressed: () => _leave(saved: false),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String text) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      text,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: cs.onSurface,
      ),
    );
  }

  Widget _label(String text) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      text,
      style: TextStyle(
          fontWeight: FontWeight.w500, fontSize: 13, color: cs.onSurface),
    );
  }
}
