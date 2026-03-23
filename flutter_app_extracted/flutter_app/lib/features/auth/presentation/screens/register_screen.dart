import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vitapulse_ai/core/theme/app_theme.dart';
import 'package:vitapulse_ai/features/auth/data/auth_api.dart';
import 'package:vitapulse_ai/shared/widgets/loading_button.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _identifierCtrl = TextEditingController();
  String _gender = 'Male';
  String _bloodGroup = '';
  int? _age;
  bool _loading = false;

  static const _bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _identifierCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await AuthApi.sendOtp(_identifierCtrl.text.trim(), 'register');
      if (mounted) {
        context.push('/auth/otp', extra: {
          'identifier': _identifierCtrl.text.trim(),
          'purpose': 'register',
          'name': _nameCtrl.text.trim(),
          'age': _age,
          'gender': _gender,
          'blood_group': _bloodGroup,
        });
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppTheme.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Welcome to VitaPulse AI',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('Create your health profile',
                  style: TextStyle(color: AppTheme.textSecondary)),
              const SizedBox(height: 28),
              _label('Full Name *'),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  hintText: 'Enter your full name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) => (v?.trim().isEmpty ?? true) ? 'Name is required' : null,
              ),
              const SizedBox(height: 16),
              _label('Email or Phone *'),
              TextFormField(
                controller: _identifierCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  hintText: 'email@example.com or +61 4XX XXX XXX',
                  prefixIcon: Icon(Icons.contact_mail_outlined),
                ),
                validator: (v) {
                  if (v?.trim().isEmpty ?? true) return 'Email or phone is required';
                  if (!v!.contains('@') && !RegExp(r'^\+?[\d\s\-]{8,}$').hasMatch(v)) {
                    return 'Enter a valid email or phone number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Age'),
                    TextFormField(
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: 'Age'),
                      onChanged: (v) => _age = int.tryParse(v),
                    ),
                  ],
                )),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Gender'),
                    DropdownButtonFormField<String>(
                      value: _gender,
                      items: ['Male', 'Female', 'Other']
                          .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                          .toList(),
                      onChanged: (v) => setState(() => _gender = v!),
                      decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14)),
                    ),
                  ],
                )),
              ]),
              const SizedBox(height: 16),
              _label('Blood Group'),
              DropdownButtonFormField<String>(
                value: _bloodGroup.isEmpty ? null : _bloodGroup,
                hint: const Text('Select blood group'),
                items: _bloodGroups
                    .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                    .toList(),
                onChanged: (v) => setState(() => _bloodGroup = v ?? ''),
              ),
              const SizedBox(height: 32),
              LoadingButton(
                text: 'Send OTP & Continue',
                loading: _loading,
                onPressed: _sendOtp,
              ),
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text('Already have an account? ', style: TextStyle(color: AppTheme.textSecondary)),
                GestureDetector(
                  onTap: () => context.go('/auth/login'),
                  child: const Text('Login', style: TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w600,
                  )),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
  );
}
