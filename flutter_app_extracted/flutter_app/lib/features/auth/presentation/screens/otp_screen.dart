import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import 'package:vitapulse_ai/core/theme/app_theme.dart';
import 'package:vitapulse_ai/features/auth/data/auth_api.dart';
import 'package:vitapulse_ai/shared/widgets/loading_button.dart';

class OtpScreen extends StatefulWidget {
  final String identifier;
  final String purpose;
  final String? name;
  final int? age;
  final String? gender;
  final String? bloodGroup;

  const OtpScreen({
    super.key,
    required this.identifier,
    required this.purpose,
    this.name,
    this.age,
    this.gender,
    this.bloodGroup,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final List<TextEditingController> _controllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focuses = List.generate(6, (_) => FocusNode());
  bool _loading = false;
  int _secondsLeft = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft == 0) {
        t.cancel();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  String get _otp => _controllers.map((c) => c.text).join();

  Future<void> _verify() async {
    if (_otp.length < 6) {
      _showError('Please enter the 6-digit OTP');
      return;
    }
    setState(() => _loading = true);
    try {
      if (widget.purpose == 'register') {
        await AuthApi.register(
          name: widget.name!,
          identifier: widget.identifier,
          otpCode: _otp,
          age: widget.age,
          gender: widget.gender,
          bloodGroup: widget.bloodGroup,
        );
      } else {
        await AuthApi.login(identifier: widget.identifier, otpCode: _otp);
      }
      if (mounted) context.go('/home');
    } catch (e) {
      _showError('Invalid OTP. Please try again.');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    if (_secondsLeft > 0) return;
    try {
      await AuthApi.sendOtp(widget.identifier, widget.purpose);
      _startTimer();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OTP resent successfully')),
      );
    } catch (e) {
      _showError('Failed to resend OTP');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppTheme.error),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) c.dispose();
    for (final f in _focuses) f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify OTP')),
      body: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.sms_outlined, size: 48, color: AppTheme.primary),
            ),
            const SizedBox(height: 24),
            const Text('Enter Verification Code',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'We sent a 6-digit OTP to\n${widget.identifier}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 36),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(6, (i) => SizedBox(
                width: 46,
                child: TextFormField(
                  controller: _controllers[i],
                  focusNode: _focuses[i],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 1,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.primary, width: 2),
                    ),
                  ),
                  onChanged: (v) {
                    if (v.isNotEmpty && i < 5) _focuses[i + 1].requestFocus();
                    if (v.isEmpty && i > 0) _focuses[i - 1].requestFocus();
                    if (_otp.length == 6) _verify();
                  },
                ),
              )),
            ),
            const SizedBox(height: 36),
            LoadingButton(text: 'Verify OTP', loading: _loading, onPressed: _verify),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: _resend,
              child: Text(
                _secondsLeft > 0 ? 'Resend OTP in ${_secondsLeft}s' : 'Resend OTP',
                style: TextStyle(
                  color: _secondsLeft > 0 ? AppTheme.textSecondary : AppTheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
