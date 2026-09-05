import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:vitapulse_ai/core/utils/error_handler.dart';
import 'package:vitapulse_ai/features/auth/data/auth_api.dart';
import 'package:vitapulse_ai/shared/widgets/app_error_banner.dart';
import 'package:vitapulse_ai/shared/widgets/auth_header_panel.dart';
import 'package:vitapulse_ai/shared/widgets/loading_button.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';

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

  bool _hasError = false;
  String? _inlineError;

  // ── Shake ──────────────────────────────────────────────────────────────────
  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnim;

  // ── Entrance ───────────────────────────────────────────────────────────────
  late final AnimationController _entranceCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _startTimer();

    _shakeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _shakeAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _shakeController, curve: Curves.elasticOut));

    _entranceCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim =
        CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOut);
    _slideAnim = Tween(begin: const Offset(0, 0.05), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _entranceCtrl, curve: Curves.easeOutCubic));
    _entranceCtrl.forward();

    for (final c in _controllers) {
      c.addListener(() => setState(() {}));
    }
  }

  // ── Timer ──────────────────────────────────────────────────────────────────

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

  // ── OTP helpers ────────────────────────────────────────────────────────────

  String get _otp => _controllers.map((c) => c.text).join();

  void _fillFromPaste(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    for (int j = 0; j < 6 && j < digits.length; j++) {
      _controllers[j].text = digits[j];
    }
    final lastFilled = math.min(digits.length - 1, 5);
    if (lastFilled >= 0) _focuses[lastFilled].requestFocus();
    if (digits.length >= 6) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _verify());
    }
  }

  // ── Shake + inline error ───────────────────────────────────────────────────

  void _triggerShake(String errorMsg) {
    setState(() {
      _hasError = true;
      _inlineError = errorMsg;
    });
    _shakeController.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _hasError = false);
    });
  }

  // ── Verify ─────────────────────────────────────────────────────────────────

  Future<void> _verify() async {
    if (_loading) return;
    if (_otp.length < 6) return;

    setState(() {
      _loading = true;
      _inlineError = null;
    });
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
      final msg = ErrorHandler.getMessage(e);
      _triggerShake(msg);
      for (final c in _controllers) { c.clear(); }
      _focuses[0].requestFocus();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Resend ─────────────────────────────────────────────────────────────────

  Future<void> _resend() async {
    if (_secondsLeft > 0) return;
    setState(() => _inlineError = null);
    try {
      final result = await AuthApi.sendOtp(widget.identifier, widget.purpose);
      _startTimer();
      for (final c in _controllers) { c.clear(); }
      _focuses[0].requestFocus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result.delivered
              ? 'OTP resent to your ${result.channel}.'
              : 'OTP generated (dev mode — check server logs).'),
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _inlineError = ErrorHandler.getMessage(e));
      }
    }
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _timer?.cancel();
    _shakeController.dispose();
    _entranceCtrl.dispose();
    for (final c in _controllers) { c.dispose(); }
    for (final f in _focuses) { f.dispose(); }
    super.dispose();
  }

  // ── Identifier mask ────────────────────────────────────────────────────────

  String get _maskedIdentifier {
    final id = widget.identifier;
    if (id.contains('@')) {
      final at = id.indexOf('@');
      final local = id.substring(0, at);
      if (local.length <= 2) return id;
      return '${local[0]}${'•' * (local.length - 2)}${local[local.length - 1]}@${id.substring(at + 1)}';
    }
    if (id.length <= 6) return id;
    return '${id.substring(0, 4)} ••••• ${id.substring(id.length - 3)}';
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final headerHeight =
        (MediaQuery.sizeOf(context).height * 0.22).clamp(148.0, 182.0);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: Column(
            children: [
              AuthHeaderPanel(
                title: 'Verify Your Identity',
                subtitle: 'Code sent to $_maskedIdentifier',
                height: headerHeight,
                logoSize: 32,
              ),
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // ── Title ─────────────────────────────────────────────
                      Text(
                        'Enter 6-Digit Code',
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Check your SMS or email inbox',
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Inline error ──────────────────────────────────────
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        child: _inlineError != null
                            ? Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: AppErrorBanner(message: _inlineError!),
                              )
                            : const SizedBox.shrink(),
                      ),

                      // ── OTP boxes with shake ──────────────────────────────
                      AnimatedBuilder(
                        animation: _shakeAnim,
                        builder: (context, child) {
                          final dx =
                              math.sin(_shakeAnim.value * math.pi * 6) * 10.0;
                          return Transform.translate(
                              offset: Offset(dx, 0), child: child);
                        },
                        child: AutofillGroup(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: List.generate(6, _buildOtpBox),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ── Circular countdown ────────────────────────────────
                      _CountdownArc(
                        secondsLeft: _secondsLeft,
                        totalSeconds: 60,
                      ),

                      const SizedBox(height: 20),

                      // ── Verify button ─────────────────────────────────────
                      LoadingButton(
                        text: 'Verify Code',
                        loading: _loading,
                        onPressed: _otp.length < 6 ? null : _verify,
                      ),

                      const SizedBox(height: 16),

                      // ── Resend ────────────────────────────────────────────
                      TextButton.icon(
                        onPressed: _secondsLeft > 0 ? null : _resend,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: Text(
                          _secondsLeft > 0
                              ? 'Resend OTP in ${_secondsLeft}s'
                              : 'Resend OTP',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Single OTP box ─────────────────────────────────────────────────────────

  Widget _buildOtpBox(int i) {
    final cs = Theme.of(context).colorScheme;
    final isFilled = _controllers[i].text.isNotEmpty;
    final isFocused = _focuses[i].hasFocus;

    final Color borderColor;
    final Color fillColor;
    final Color textColor;

    if (_hasError) {
      borderColor = cs.error;
      fillColor   = cs.errorContainer;
      textColor   = cs.onErrorContainer;
    } else if (isFilled) {
      borderColor = cs.primary;
      fillColor   = cs.primaryContainer;
      textColor   = cs.onPrimaryContainer;
    } else if (isFocused) {
      borderColor = cs.primary;
      fillColor   = cs.primaryContainer.withValues(alpha: 0.30);
      textColor   = cs.onSurface;
    } else {
      borderColor = cs.outline;
      fillColor   = cs.surface;
      textColor   = cs.onSurface;
    }

    return Semantics(
      label: 'OTP digit ${i + 1}',
      child: SizedBox(
        width: 44,
        child: TextFormField(
          controller: _controllers[i],
          focusNode: _focuses[i],
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          autofillHints:
              i == 0 ? const [AutofillHints.oneTimeCode] : null,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: textColor,
          ),
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: fillColor,
            contentPadding: const EdgeInsets.symmetric(vertical: 13),
            border: const OutlineInputBorder(
                borderRadius: AppRadius.brMd),
            enabledBorder: OutlineInputBorder(
              borderRadius: AppRadius.brMd,
              borderSide: BorderSide(
                color: borderColor,
                width: isFilled ? 1.5 : 1.0,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: AppRadius.brMd,
              borderSide: BorderSide(color: borderColor, width: 2),
            ),
          ),
          onChanged: (v) {
            if (v.length > 1) {
              _fillFromPaste(v);
              return;
            }
            if (v.isNotEmpty) {
              if (i < 5) _focuses[i + 1].requestFocus();
            } else {
              if (i > 0) _focuses[i - 1].requestFocus();
            }
            if (_otp.length == 6) {
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => _verify());
            }
          },
        ),
      ),
    );
  }
}

// ── Countdown arc ─────────────────────────────────────────────────────────────

class _CountdownArc extends StatelessWidget {
  final int secondsLeft;
  final int totalSeconds;

  const _CountdownArc({
    required this.secondsLeft,
    required this.totalSeconds,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final fraction = secondsLeft / totalSeconds;

    final arcColor = secondsLeft <= 15
        ? cs.error
        : secondsLeft <= 30
            ? cs.tertiary
            : cs.primary;

    return Column(
      children: [
        SizedBox(
          width: 64,
          height: 64,
          child: CustomPaint(
            painter: _ArcPainter(
              fraction: fraction,
              trackColor: cs.outlineVariant,
              arcColor: arcColor,
            ),
            child: Center(
              child: Text(
                '${secondsLeft}s',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: fraction == 0 ? cs.onSurfaceVariant : arcColor,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          fraction == 0 ? 'Code expired' : 'Expires in',
          style: tt.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ArcPainter extends CustomPainter {
  final double fraction;
  final Color trackColor;
  final Color arcColor;

  const _ArcPainter({
    required this.fraction,
    required this.trackColor,
    required this.arcColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - 6) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    final arcPaint = Paint()
      ..color = arcColor
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);
    if (fraction > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * fraction,
        false,
        arcPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.fraction != fraction || old.arcColor != arcColor;
}
