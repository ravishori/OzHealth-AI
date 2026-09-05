import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vitapulse_ai/core/error/error_reporter.dart';
import 'package:vitapulse_ai/core/utils/error_handler.dart';
import 'package:vitapulse_ai/features/auth/data/auth_api.dart';
import 'package:vitapulse_ai/shared/widgets/app_error_banner.dart';
import 'package:vitapulse_ai/shared/widgets/auth_header_panel.dart';
import 'package:vitapulse_ai/shared/widgets/form_field_label.dart';
import 'package:vitapulse_ai/shared/widgets/loading_button.dart';
import 'package:vitapulse_ai/shared/widgets/server_settings_dialog.dart';

enum _IdType { unknown, email, phone }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _identifierCtrl = TextEditingController();
  bool _loading = false;
  String? _networkError;
  _IdType _idType = _IdType.unknown;

  late final AnimationController _entranceCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim =
        CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOut);
    _slideAnim = Tween(begin: const Offset(0, 0.05), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOutCubic));
    _entranceCtrl.forward();
    _identifierCtrl.addListener(_onChanged);
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _identifierCtrl
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  void _onChanged() {
    final v = _identifierCtrl.text;
    final next = v.isEmpty
        ? _IdType.unknown
        : v.contains('@')
            ? _IdType.email
            : RegExp(r'^\+?[\d\s\-()+]{3,}').hasMatch(v)
                ? _IdType.phone
                : _IdType.unknown;
    if (next != _idType || _networkError != null) {
      setState(() {
        _idType = next;
        _networkError = null;
      });
    }
  }

  String? _validateIdentifier(String? v) {
    if (v == null || v.trim().isEmpty) {
      return 'Please enter your email or phone number';
    }
    final s = v.trim();
    if (s.contains('@')) {
      if (!RegExp(r'^[\w.+\-]+@[\w\-]+\.[a-zA-Z]{2,}$').hasMatch(s)) {
        return 'Enter a valid email address';
      }
      return null;
    }
    final digits = s.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 8) return 'Phone must be at least 8 digits';
    final isAuLocal = RegExp(r'^0[0-9]{9}$').hasMatch(digits);
    final isInLocal = RegExp(r'^[6-9][0-9]{9}$').hasMatch(digits);
    if (!s.startsWith('+') && !isAuLocal && !isInLocal) {
      return 'Include country code: +61 (AU) or +91 (IN)';
    }
    return null;
  }

  Future<void> _sendOtp() async {
    setState(() => _networkError = null);
    if (!_formKey.currentState!.validate()) return;
    final identifier = _identifierCtrl.text.trim();
    setState(() => _loading = true);
    try {
      final result = await AuthApi.sendOtp(identifier, 'auth');
      if (mounted) {
        if (!result.delivered) {
          ErrorReporter.report(
            Exception('OTP delivery failed via ${result.channel}'),
            StackTrace.current,
            context: 'login_otp_undelivered',
          );
        }
        context.push('/auth/otp',
            extra: {'identifier': identifier, 'purpose': 'auth', 'name': null});
      }
    } catch (e) {
      ErrorReporter.report(e, StackTrace.current, context: 'login_send_otp');
      if (mounted) setState(() => _networkError = ErrorHandler.getMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  IconData get _prefixIcon {
    switch (_idType) {
      case _IdType.email:
        return Icons.alternate_email;
      case _IdType.phone:
        return Icons.phone_outlined;
      case _IdType.unknown:
        return Icons.contact_mail_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final headerHeight =
        (MediaQuery.sizeOf(context).height * 0.27).clamp(180.0, 240.0);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: Column(
            children: [
              AuthHeaderPanel(
                title: 'Welcome Back',
                subtitle: 'Sign in to your health account',
                height: headerHeight,
              ),
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Section header ──────────────────────────────────
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Continue with OTP',
                                    style: tt.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: cs.onSurface,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    "We'll send a one-time code to verify you.",
                                    style: tt.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (kDebugMode)
                              IconButton(
                                icon: Icon(
                                  Icons.wifi_find_rounded,
                                  size: 20,
                                  color: cs.onSurfaceVariant,
                                ),
                                tooltip: 'Server settings',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () =>
                                    showServerSettingsDialog(context),
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // ── Identifier field ────────────────────────────────
                        const FormFieldLabel('EMAIL OR PHONE'),
                        TextFormField(
                          controller: _identifierCtrl,
                          keyboardType: _idType == _IdType.phone
                              ? TextInputType.phone
                              : TextInputType.emailAddress,
                          textInputAction: TextInputAction.done,
                          autocorrect: false,
                          decoration: InputDecoration(
                            hintText: 'email@example.com or +61 4xx xxx xxx',
                            prefixIcon: Icon(
                              _prefixIcon,
                              color: _idType != _IdType.unknown
                                  ? cs.primary
                                  : cs.onSurfaceVariant,
                            ),
                            suffixIcon: _idType == _IdType.phone
                                ? Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Chip(
                                      label: const Text('AU / IN',
                                          style: TextStyle(fontSize: 10)),
                                      backgroundColor:
                                          cs.secondaryContainer,
                                      labelStyle: TextStyle(
                                          color: cs.onSecondaryContainer,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 10),
                                      padding: EdgeInsets.zero,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  )
                                : null,
                          ),
                          onFieldSubmitted: (_) => _sendOtp(),
                          validator: _validateIdentifier,
                        ),
                        const SizedBox(height: 6),
                        const _HelperText(),

                        // ── Network error ───────────────────────────────────
                        if (_networkError != null) ...[
                          const SizedBox(height: 10),
                          AppErrorBanner(message: _networkError!),
                        ],
                        const SizedBox(height: 24),

                        // ── CTA ─────────────────────────────────────────────
                        LoadingButton(
                          text: 'Send OTP',
                          loading: _loading,
                          onPressed: _sendOtp,
                          trailingIcon: Icons.arrow_forward,
                        ),
                        const SizedBox(height: 16),
                        const Divider(height: 1),
                        const SizedBox(height: 16),

                        // ── Register link ───────────────────────────────────
                        Center(
                          child: TextButton(
                            onPressed: () => context.go('/auth/register'),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              tapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: RichText(
                              text: TextSpan(
                                style: tt.bodySmall?.copyWith(fontSize: 13),
                                children: [
                                  TextSpan(
                                    text: 'New to HealthNest? ',
                                    style:
                                        TextStyle(color: cs.onSurfaceVariant),
                                  ),
                                  TextSpan(
                                    text: 'Create account',
                                    style: TextStyle(
                                      color: cs.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HelperText extends StatelessWidget {
  const _HelperText();

  @override
  Widget build(BuildContext context) => Text(
        'Phone: include country code (+61 AU · +91 IN)',
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
}
