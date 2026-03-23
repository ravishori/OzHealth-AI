import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:vitapulse_ai/core/theme/app_theme.dart';
import 'package:vitapulse_ai/core/utils/error_handler.dart';
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

class _OtpScreenState extends State<OtpScreen> with TickerProviderStateMixin {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focuses = List.generate(6, (_) => FocusNode());

  bool _loading = false;
  int _secondsLeft = 60;
  Timer? _timer;

  // ── Shake animation ──────────────────────────────────────────────────────────
  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnim;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _startTimer();

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticOut),
    );
  }

  // ── Timer ────────────────────────────────────────────────────────────────────

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

  // ── OTP helpers ──────────────────────────────────────────────────────────────

  String get _otp => _controllers.map((c) => c.text).join();

  /// Fills all boxes from a pasted string (e.g. from SMS autofill or clipboard).
  void _fillFromPaste(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    for (int j = 0; j < 6 && j < digits.length; j++) {
      _controllers[j].text = digits[j];
    }
    final lastFilled = math.min(digits.length - 1, 5);
    if (lastFilled >= 0) _focuses[lastFilled].requestFocus();
    if (digits.length >= 6) {
      // Defer until after the field has updated its value
      WidgetsBinding.instance.addPostFrameCallback((_) => _verify());
    }
  }

  // ── Shake ────────────────────────────────────────────────────────────────────

  void _triggerShake() {
    setState(() => _hasError = true);
    _shakeController.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _hasError = false);
    });
  }

  // ── Verify ───────────────────────────────────────────────────────────────────

  Future<void> _verify() async {
    if (_loading) return;
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
        await AuthApi.login(
          identifier: widget.identifier,
          otpCode: _otp,
        );
      }
      if (mounted) context.go('/home');
    } catch (e) {
      _triggerShake();
      _showError(ErrorHandler.getMessage(e));
      // Clear boxes so the user can re-enter
      for (final c in _controllers) {
        c.clear();
      }
      _focuses[0].requestFocus();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Resend ───────────────────────────────────────────────────────────────────

  Future<void> _resend() async {
    if (_secondsLeft > 0) return;
    try {
      await AuthApi.sendOtp(widget.identifier, widget.purpose);
      _startTimer();
      // Clear boxes for fresh entry
      for (final c in _controllers) {
        c.clear();
      }
      _focuses[0].requestFocus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('OTP resent successfully')),
        );
      }
    } catch (e) {
      _showError(ErrorHandler.getMessage(e));
    }
  }

  // ── Error snackbar ───────────────────────────────────────────────────────────

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppTheme.error),
      );
  }

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _timer?.cancel();
    _shakeController.dispose();
    for (final c in _controllers) c.dispose();
    for (final f in _focuses) f.dispose();
    super.dispose();
  }

  // ── Build ────────────────────────────────────────────────────────────────────

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
              decoration: const BoxDecoration(
                color: Color(0x1A00897B), // AppTheme.primary @ 10% opacity
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.sms_outlined,
                  size: 48, color: AppTheme.primary),
            ),
            const SizedBox(height: 24),
            const Text(
              'Enter Verification Code',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'We sent a 6-digit OTP to\n${widget.identifier}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 36),

            // ── OTP boxes with shake ──────────────────────────────────────────
            AnimatedBuilder(
              animation: _shakeAnim,
              builder: (context, child) {
                final dx =
                    math.sin(_shakeAnim.value * math.pi * 6) * 10.0;
                return Transform.translate(
                  offset: Offset(dx, 0),
                  child: child,
                );
              },
              child: AutofillGroup(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(6, _buildOtpBox),
                ),
              ),
            ),

            const SizedBox(height: 36),
            LoadingButton(
                text: 'Verify OTP', loading: _loading, onPressed: _verify),
            const SizedBox(height: 24),

            // ── Resend ────────────────────────────────────────────────────────
            GestureDetector(
              onTap: _secondsLeft > 0 ? null : _resend,
              child: Text(
                _secondsLeft > 0
                    ? 'Resend OTP in ${_secondsLeft}s'
                    : 'Resend OTP',
                style: TextStyle(
                  color: _secondsLeft > 0
                      ? AppTheme.textSecondary
                      : AppTheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Single OTP box ───────────────────────────────────────────────────────────

  Widget _buildOtpBox(int i) {
    return SizedBox(
      width: 46,
      child: TextFormField(
        controller: _controllers[i],
        focusNode: _focuses[i],
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        // First box carries the SMS/email autofill hint so the OS can
        autofillHints:
            i == 0 ? const [AutofillHints.oneTimeCode] : null,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: _hasError ? AppTheme.error : AppTheme.textPrimary,
        ),
        decoration: InputDecoration(
          counterText: '',
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: _hasError ? AppTheme.error : const Color(0xFFD1D5DB),
              width: _hasError ? 1.5 : 1.0,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: _hasError ? AppTheme.error : AppTheme.primary,
              width: 2,
            ),
          ),
        ),
        onChanged: (v) {
          // ── Paste / SMS autofill: more than one char arrives at once ─────
          if (v.length > 1) {
            _fillFromPaste(v);
            return;
          }

          // ── Normal single-character entry ────────────────────────────────
          if (v.isNotEmpty) {
            if (i < 5) _focuses[i + 1].requestFocus();
          } else {
            // Backspace: move focus backwards
            if (i > 0) _focuses[i - 1].requestFocus();
          }

          // Auto-submit when all 6 digits are filled
          if (_otp.length == 6) {
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _verify());
          }
        },
      ),
    );
  }
}
