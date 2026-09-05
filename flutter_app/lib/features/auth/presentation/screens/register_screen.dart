import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vitapulse_ai/core/utils/error_handler.dart';
import 'package:vitapulse_ai/features/auth/data/auth_api.dart';
import 'package:vitapulse_ai/shared/widgets/app_error_banner.dart';
import 'package:vitapulse_ai/shared/widgets/auth_header_panel.dart';
import 'package:vitapulse_ai/shared/widgets/form_field_label.dart';
import 'package:vitapulse_ai/shared/widgets/loading_button.dart';
import 'package:vitapulse_ai/shared/widgets/server_settings_dialog.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with TickerProviderStateMixin {
  // ── Step tracking ──────────────────────────────────────────────────────────
  int _step = 1;

  // ── Step 1 fields ──────────────────────────────────────────────────────────
  final _step1Key = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _identifierCtrl = TextEditingController();

  // ── Step 2 fields ──────────────────────────────────────────────────────────
  final _ageCtrl = TextEditingController();
  String _gender = 'Male';
  String _bloodGroup = '';

  bool _loading = false;
  String? _networkError;

  static const _bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
  static const _genders = ['Male', 'Female', 'Other'];

  // ── Entrance animation ─────────────────────────────────────────────────────
  late final AnimationController _entranceCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  // ── Step-transition animation ──────────────────────────────────────────────
  late final AnimationController _stepCtrl;
  late final Animation<Offset> _stepSlide;
  late final Animation<double> _stepFade;

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

    _stepCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 250));
    _stepSlide = Tween(begin: const Offset(0.18, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _stepCtrl, curve: Curves.easeOutCubic));
    _stepFade = CurvedAnimation(parent: _stepCtrl, curve: Curves.easeOut);
    _stepCtrl.forward();
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _stepCtrl.dispose();
    _nameCtrl.dispose();
    _identifierCtrl.dispose();
    _ageCtrl.dispose();
    super.dispose();
  }

  // ── Validation ─────────────────────────────────────────────────────────────

  String? _validateIdentifier(String? v) {
    if (v == null || v.trim().isEmpty) return 'Email or phone is required';
    final s = v.trim();
    if (s.contains('@')) {
      if (!RegExp(r'^[\w.+\-]+@[\w\-]+\.[a-zA-Z]{2,}$').hasMatch(s)) {
        return 'Enter a valid email address';
      }
      return null;
    }
    final digits = s.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 8) {
      return 'Enter a valid phone number (at least 8 digits)';
    }
    final isAuLocal = RegExp(r'^0[0-9]{9}$').hasMatch(digits);
    final isInLocal = RegExp(r'^[6-9][0-9]{9}$').hasMatch(digits);
    if (!s.startsWith('+') && !isAuLocal && !isInLocal) {
      return 'Include country code: +61 (AU) or +91 (IN)';
    }
    return null;
  }

  // ── Navigation between steps ───────────────────────────────────────────────

  void _goToStep2() {
    if (!_step1Key.currentState!.validate()) return;
    _stepCtrl.reset();
    setState(() {
      _step = 2;
      _networkError = null;
    });
    _stepCtrl.forward();
  }

  void _backToStep1() {
    _stepCtrl.reset();
    setState(() {
      _step = 1;
      _networkError = null;
    });
    _stepCtrl.forward();
  }

  // ── Send OTP ───────────────────────────────────────────────────────────────

  Future<void> _sendOtp() async {
    setState(() => _networkError = null);
    setState(() => _loading = true);
    try {
      final identifier = _identifierCtrl.text.trim();
      final result = await AuthApi.sendOtp(identifier, 'register');
      if (mounted) {
        if (!result.delivered) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('OTP generated but delivery failed. Check server logs.'),
          ));
        }
        context.push('/auth/otp', extra: {
          'identifier': identifier,
          'purpose': 'register',
          'name': _nameCtrl.text.trim(),
          'age': int.tryParse(_ageCtrl.text.trim()),
          'gender': _gender,
          'blood_group': _bloodGroup.isEmpty ? null : _bloodGroup,
        });
      }
    } catch (e) {
      if (mounted) setState(() => _networkError = ErrorHandler.getMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final headerHeight =
        (MediaQuery.sizeOf(context).height * 0.25).clamp(168.0, 210.0);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: Column(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _step == 1
                    ? AuthHeaderPanel(
                        key: const ValueKey('h1'),
                        title: 'Create Account',
                        subtitle: 'Your identity',
                        height: headerHeight,
                        stepRow: AuthStepRow(currentStep: _step),
                        logoSize: 36,
                      )
                    : AuthHeaderPanel(
                        key: const ValueKey('h2'),
                        title: 'Health Profile',
                        subtitle: 'Helps personalise your experience',
                        height: headerHeight,
                        stepRow: AuthStepRow(currentStep: _step),
                        onBack: _backToStep1,
                        logoSize: 36,
                      ),
              ),
              Expanded(
                child: SlideTransition(
                  position: _stepSlide,
                  child: FadeTransition(
                    opacity: _stepFade,
                    child: _step == 1 ? _buildStep1() : _buildStep2(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Step 1 ─────────────────────────────────────────────────────────────────

  Widget _buildStep1() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Form(
        key: _step1Key,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Section header ──────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome to HealthNest',
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Create your health profile',
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
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
                    onPressed: () => showServerSettingsDialog(context),
                  ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Name ────────────────────────────────────────────────────────
            const FormFieldLabel('FULL NAME *'),
            TextFormField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'Enter your full name',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (v) =>
                  (v?.trim().isEmpty ?? true) ? 'Name is required' : null,
            ),
            const SizedBox(height: 16),

            // ── Identifier ──────────────────────────────────────────────────
            const FormFieldLabel('EMAIL OR PHONE *'),
            TextFormField(
              controller: _identifierCtrl,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(
                hintText: 'email@example.com or +61 4xx xxx xxx',
                prefixIcon: Icon(Icons.contact_mail_outlined),
                helperText: 'Phone: include country code (+61 AU · +91 IN)',
                helperMaxLines: 1,
              ),
              validator: _validateIdentifier,
            ),
            const SizedBox(height: 28),

            // ── CTA ─────────────────────────────────────────────────────────
            LoadingButton(
              text: 'Continue',
              loading: false,
              onPressed: _goToStep2,
              trailingIcon: Icons.arrow_forward,
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // ── Sign-in link ─────────────────────────────────────────────
            Center(
              child: TextButton(
                onPressed: () => context.go('/auth/login'),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: RichText(
                  text: TextSpan(
                    style: tt.bodySmall?.copyWith(fontSize: 13),
                    children: [
                      TextSpan(
                        text: 'Already have an account? ',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                      TextSpan(
                        text: 'Sign in',
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
    );
  }

  // ── Step 2 ─────────────────────────────────────────────────────────────────

  Widget _buildStep2() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section header ────────────────────────────────────────────────
          Text(
            'Optional Health Details',
            style: tt.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Skip freely — you can add these later in your profile.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 20),

          // ── Age ───────────────────────────────────────────────────────────
          const FormFieldLabel('AGE'),
          SizedBox(
            width: 110,
            child: TextFormField(
              controller: _ageCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: '—',
                suffixText: 'yrs',
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Gender ────────────────────────────────────────────────────────
          const FormFieldLabel('GENDER'),
          Wrap(
            spacing: 8,
            children: _genders
                .map((g) => _SelectChip(
                      label: g,
                      selected: _gender == g,
                      onTap: () => setState(() => _gender = g),
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),

          // ── Blood group ───────────────────────────────────────────────────
          const FormFieldLabel('BLOOD GROUP'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _bloodGroups
                .map((b) => _SelectChip(
                      label: b,
                      selected: _bloodGroup == b,
                      onTap: () => setState(
                          () => _bloodGroup = _bloodGroup == b ? '' : b),
                    ))
                .toList(),
          ),

          if (_networkError != null) ...[
            const SizedBox(height: 16),
            AppErrorBanner(message: _networkError!),
          ],

          const SizedBox(height: 28),

          // ── CTA ───────────────────────────────────────────────────────────
          LoadingButton(
            text: 'Send OTP & Finish',
            loading: _loading,
            onPressed: _sendOtp,
            trailingIcon: Icons.send_outlined,
          ),
          const SizedBox(height: 12),

          // ── Back ──────────────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 44,
            child: TextButton.icon(
              onPressed: _loading ? null : _backToStep1,
              icon: const Icon(Icons.chevron_left, size: 18),
              label: const Text('Back'),
              style: TextButton.styleFrom(
                foregroundColor: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _SelectChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SelectChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? cs.primaryContainer : cs.surface,
            border: Border.all(
              color: selected ? cs.primary : cs.outline,
              width: selected ? 1.5 : 1,
            ),
            borderRadius: AppRadius.brFull,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
