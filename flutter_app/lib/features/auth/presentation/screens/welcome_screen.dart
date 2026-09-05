import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vitapulse_ai/shared/widgets/vitapulse_logo.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const Spacer(flex: 2),

                // ── Logo & wordmark ──────────────────────────────────────────
                const VitaPulseLogo(size: 80),
                const SizedBox(height: 20),
                const Text(
                  'HealthNest',
                  style: TextStyle(
                    color: Color(0xFFEFF6FF),
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your health companion',
                  style: TextStyle(
                    color: Color(0x8094A3B8),
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    letterSpacing: 0.2,
                  ),
                ),

                const Spacer(flex: 2),

                // ── Feature highlights ───────────────────────────────────────
                _FeatureRow(
                  icon: Icons.medication_outlined,
                  text: 'Manage Medications & Prescriptions',
                  accent: cs.secondary,
                ),
                const SizedBox(height: 14),
                _FeatureRow(
                  icon: Icons.psychology_outlined,
                  text: 'AI Health Assistant (24/7)',
                  accent: cs.secondary,
                ),
                const SizedBox(height: 14),
                _FeatureRow(
                  icon: Icons.family_restroom_outlined,
                  text: 'Family Health Management',
                  accent: cs.secondary,
                ),
                const SizedBox(height: 14),
                _FeatureRow(
                  icon: Icons.monitor_heart_outlined,
                  text: 'Health Monitoring & AI Insights',
                  accent: cs.secondary,
                ),

                const Spacer(flex: 3),

                // ── CTAs ─────────────────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: cs.primary,
                      shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
                      elevation: 0,
                    ),
                    onPressed: () => context.go('/auth/register'),
                    child: const Text(
                      'Get Started',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEFF6FF),
                      side: const BorderSide(color: Color(0x5594A3B8), width: 1.5),
                      shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
                    ),
                    onPressed: () => context.go('/auth/login'),
                    child: const Text(
                      'I already have an account',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),

                const SizedBox(height: 24),
                const Text(
                  'Compliant with Australian Privacy Principles',
                  style: TextStyle(
                    color: Color(0x5594A3B8),
                    fontSize: 11,
                    letterSpacing: 0.2,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color accent;

  const _FeatureRow({
    required this.icon,
    required this.text,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.15),
            borderRadius: AppRadius.brSm,
            border: Border.all(color: accent.withValues(alpha: 0.25)),
          ),
          child: Icon(icon, color: accent, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xCCEFF6FF),
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}
