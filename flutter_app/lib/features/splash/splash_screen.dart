import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:vitapulse_ai/core/utils/app_initializer.dart';
import 'package:vitapulse_ai/core/utils/auth_storage.dart';
import 'package:vitapulse_ai/features/legal/legal_screens.dart';
import 'package:vitapulse_ai/shared/widgets/vitapulse_logo.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logoCtrl;
  late final AnimationController _wordmarkCtrl;

  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _wordmarkFade;
  late final Animation<Offset> _wordmarkSlide;

  @override
  void initState() {
    super.initState();

    _logoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _wordmarkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );

    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOut),
    );
    _logoScale = Tween<double>(begin: 0.78, end: 1.0).animate(
      CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutBack),
    );
    _wordmarkFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _wordmarkCtrl, curve: Curves.easeOut),
    );
    _wordmarkSlide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(parent: _wordmarkCtrl, curve: Curves.easeOutCubic),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 80));
      if (!mounted) return;
      _logoCtrl.forward();
      await Future.delayed(const Duration(milliseconds: 220));
      if (!mounted) return;
      _wordmarkCtrl.forward();
      _checkAuth();
    });
  }

  Future<void> _checkAuth() async {
    await Future.wait([
      AppInitializer.init(),
      Future.delayed(const Duration(milliseconds: 1500)),
    ]);
    if (!mounted) return;
    final consented =
        Hive.box('app_preferences').get(kLegalConsentKey, defaultValue: false) ==
            true;
    if (!consented) {
      context.go('/legal/consent');
      return;
    }
    final loggedIn = await AuthStorage.isLoggedIn();
    if (!mounted) return;
    context.go(loggedIn ? '/home' : '/auth/welcome');
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _wordmarkCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF080E1E), // Midnight Medical
              Color(0xFF0F2248), // Mid navy
              Color(0xFF0A1C3A), // Deep navy
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Teal radial glow behind the logo
              Positioned.fill(
                child: FadeTransition(
                  opacity: _logoFade,
                  child: Center(
                    child: Container(
                      width: 280,
                      height: 280,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Color(0x1400B4A2),
                            Color(0x00080E1E),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Content
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ── Shield logo mark ──────────────────────────────────────
                    FadeTransition(
                      opacity: _logoFade,
                      child: ScaleTransition(
                        scale: _logoScale,
                        child: const VitaPulseLogo(size: 88),
                      ),
                    ),

                    const SizedBox(height: 28),

                    // ── Wordmark ──────────────────────────────────────────────
                    FadeTransition(
                      opacity: _wordmarkFade,
                      child: SlideTransition(
                        position: _wordmarkSlide,
                        child: Column(
                          children: [
                            const Text(
                              'HealthNest',
                              style: TextStyle(
                                color: Color(0xFFEFF6FF),
                                fontSize: 34,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.8,
                                height: 1,
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Your health companion',
                              style: TextStyle(
                                color: Color(0x8094A3B8),
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                                letterSpacing: 0.3,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 64),

                    // ── Dot progress indicator ────────────────────────────────
                    FadeTransition(
                      opacity: _wordmarkFade,
                      child: const _DotProgress(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Three dots — first is teal, others are dim — mimics a minimal loader.
class _DotProgress extends StatefulWidget {
  const _DotProgress();

  @override
  State<_DotProgress> createState() => _DotProgressState();
}

class _DotProgressState extends State<_DotProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = ((t * 3) - i).clamp(0.0, 1.0);
            final bright = (phase < 0.5 ? phase * 2 : (1 - phase) * 2).clamp(0.0, 1.0);
            final color = Color.lerp(
              const Color(0x33FFFFFF),
              Theme.of(context).colorScheme.secondary,
              bright,
            )!;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            );
          }),
        );
      },
    );
  }
}
