import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vitapulse_ai/core/theme/app_theme.dart';
import 'package:vitapulse_ai/features/auth/data/auth_api.dart';
import 'package:vitapulse_ai/shared/widgets/loading_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _identifierCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await AuthApi.sendOtp(_identifierCtrl.text.trim(), 'auth');
      if (mounted) {
        context.push('/auth/otp', extra: {
          'identifier': _identifierCtrl.text.trim(),
          'purpose': 'auth',
          'name': null,
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send OTP. Please check your details.'), backgroundColor: AppTheme.error),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              const Text('Welcome back!',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('Login with your email or phone',
                  style: TextStyle(color: AppTheme.textSecondary)),
              const SizedBox(height: 36),
              const Text('Email or Phone',
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _identifierCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  hintText: 'email@example.com or +61 4XX XXX XXX',
                  prefixIcon: Icon(Icons.contact_mail_outlined),
                ),
                validator: (v) => (v?.trim().isEmpty ?? true) ? 'Please enter your email or phone' : null,
              ),
              const Spacer(),
              LoadingButton(
                text: 'Send OTP',
                loading: _loading,
                onPressed: _sendOtp,
              ),
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text("Don't have an account? ", style: TextStyle(color: AppTheme.textSecondary)),
                GestureDetector(
                  onTap: () => context.go('/auth/register'),
                  child: const Text('Register', style: TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w600,
                  )),
                ),
              ]),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
