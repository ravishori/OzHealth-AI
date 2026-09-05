import 'package:flutter/material.dart';
import 'package:vitapulse_ai/shared/widgets/vitapulse_logo.dart';

class AuthHeaderPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final double height;
  final Widget? stepRow;
  final VoidCallback? onBack;
  final double logoSize;

  const AuthHeaderPanel({
    super.key,
    required this.title,
    required this.subtitle,
    this.height = 200,
    this.stepRow,
    this.onBack,
    this.logoSize = 40,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Dark atmospheric gradient tinted by the active theme's primary hue.
    // Darkening primary heavily keeps the header always readable (white text),
    // while the hue shifts to match the chosen theme.
    final topColor    = Color.lerp(cs.primary, Colors.black, 0.72)!;
    final middleColor = Color.lerp(cs.primary, Colors.black, 0.55)!;
    final bottomColor = Color.lerp(cs.primary, Colors.black, 0.65)!;

    return Container(
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [topColor, middleColor, bottomColor],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Subtle radial glow in the theme's container colour
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 1.3,
                  colors: [
                    cs.primaryContainer.withValues(alpha: 0.10),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (stepRow != null) ...[
                    stepRow!,
                    const SizedBox(height: 10),
                  ],
                  VitaPulseLogo(size: logoSize),
                  const SizedBox(height: 10),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFEFF6FF),
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0x99FFFFFF),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),

          if (onBack != null)
            SafeArea(
              bottom: false,
              child: Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(Icons.chevron_left,
                      color: Color(0x99FFFFFF), size: 28),
                  tooltip: 'Back',
                  onPressed: onBack,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class AuthStepRow extends StatelessWidget {
  final int currentStep;
  final int totalSteps;

  const AuthStepRow({
    super.key,
    required this.currentStep,
    this.totalSteps = 2,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 1; i <= totalSteps; i++) ...[
          _StepPill(
            done: currentStep > i,
            active: currentStep == i,
          ),
          const SizedBox(width: 4),
        ],
        const SizedBox(width: 4),
        Text(
          'Step $currentStep of $totalSteps'
          '${currentStep == totalSteps ? " · Optional" : ""}',
          style: const TextStyle(
            fontSize: 10,
            color: Color(0x80FFFFFF),
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

class _StepPill extends StatelessWidget {
  final bool active;
  final bool done;

  const _StepPill({required this.active, required this.done});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 4,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        color: done
            ? Colors.white.withValues(alpha: 0.40)
            : active
                ? Colors.white
                : Colors.white.withValues(alpha: 0.20),
      ),
    );
  }
}
