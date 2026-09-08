import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vitapulse_ai/core/utils/auth_storage.dart';
import 'package:vitapulse_ai/features/onboarding/onboarding_prefs.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';

/// One guided-tour step. [featureRoute] documents an existing in-app route
/// that must already ship before this step is shown.
class OnboardingStep {
  final String title;
  final String body;
  final IconData icon;
  final String featureRoute;
  final String semanticsLabel;

  const OnboardingStep({
    required this.title,
    required this.body,
    required this.icon,
    required this.featureRoute,
    required this.semanticsLabel,
  });
}

/// Steps map 1:1 to features present in [app_router] (medicines/reminders,
/// prescriptions/records, health metrics, AI chat, emergency SOS).
const kDefaultOnboardingSteps = <OnboardingStep>[
  OnboardingStep(
    title: 'Medicines & reminders',
    body:
        'Search medicines and set on-device reminders so dose times are easier to track.',
    icon: Icons.medication_outlined,
    featureRoute: '/home/reminders',
    semanticsLabel: 'Medicines and reminders introduction',
  ),
  OnboardingStep(
    title: 'Prescriptions & records',
    body:
        'Scan or enter prescriptions and keep medical documents in one place.',
    icon: Icons.folder_shared_outlined,
    featureRoute: '/home/records',
    semanticsLabel: 'Prescriptions and medical records introduction',
  ),
  OnboardingStep(
    title: 'Health metrics',
    body:
        'Log readings such as blood pressure, heart rate, and weight over time.',
    icon: Icons.monitor_heart_outlined,
    featureRoute: '/home/health',
    semanticsLabel: 'Health metrics introduction',
  ),
  OnboardingStep(
    title: 'AI Health Assistant',
    body:
        'Ask general health questions in the app. This is not a diagnosis — '
        'always follow advice from a qualified clinician.',
    icon: Icons.psychology_outlined,
    featureRoute: '/home/ai-chat',
    semanticsLabel: 'AI Health Assistant introduction',
  ),
  OnboardingStep(
    title: 'Emergency SOS',
    body:
        'Reach emergency tools and contacts quickly when you need urgent help.',
    icon: Icons.sos_outlined,
    featureRoute: '/home/emergency',
    semanticsLabel: 'Emergency SOS introduction',
  ),
];

typedef OnboardingCompleteCallback = Future<void> Function();

class OnboardingScreen extends StatefulWidget {
  final List<OnboardingStep> steps;
  final OnboardingCompleteCallback? onCompleted;
  final Future<bool> Function()? isLoggedIn;

  /// Sync test override for login state (avoids SecureStorage / async hangs).
  final bool? exitLoggedIn;

  /// Optional navigation override for widget tests (avoids GoRouter).
  final void Function(String location)? onExitNavigate;

  const OnboardingScreen({
    super.key,
    this.steps = kDefaultOnboardingSteps,
    this.onCompleted,
    this.isLoggedIn,
    this.exitLoggedIn,
    this.onExitNavigate,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _index = 0;
  bool _finishing = false;

  List<OnboardingStep> get _steps => widget.steps;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _completeTour() async {
    if (_finishing) return;
    _finishing = true;
    if (mounted) setState(() {});

    final complete = widget.onCompleted ?? markOnboardingCompleted;
    final navigate = widget.onExitNavigate;

    try {
      await complete();
    } catch (_) {
      // Persistence errors must not trap the user on this screen.
    }

    var loggedIn = widget.exitLoggedIn ?? false;
    if (widget.exitLoggedIn == null) {
      if (widget.isLoggedIn != null) {
        try {
          loggedIn = await widget.isLoggedIn!();
        } catch (_) {
          loggedIn = false;
        }
      } else if (navigate == null) {
        try {
          loggedIn = await AuthStorage.isLoggedIn();
        } catch (_) {
          loggedIn = false;
        }
      }
    }

    final location = loggedIn ? '/home' : '/auth/welcome';
    if (navigate != null) {
      navigate(location);
      return;
    }
    if (!mounted) return;
    context.go(location);
  }

  void _next() {
    if (_index >= _steps.length - 1) {
      _completeTour();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _back() {
    if (_index <= 0) return;
    _pageController.previousPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = _steps.length;
    final isLast = _index >= total - 1;
    final progress = total == 0 ? 1.0 : (_index + 1) / total;

    return Scaffold(
      key: const Key('onboarding_screen'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      label: 'Onboarding progress, step ${_index + 1} of $total',
                      child: LinearProgressIndicator(
                        key: const Key('onboarding_progress'),
                        value: progress,
                        minHeight: 4,
                        borderRadius: AppRadius.brFull,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Semantics(
                    button: true,
                    label: 'Skip onboarding',
                    child: TextButton(
                      key: const Key('onboarding_skip'),
                      onPressed: _finishing ? null : () => _completeTour(),
                      child: const Text('Skip'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Step ${_index + 1} of $total',
                key: const Key('onboarding_step_label'),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
              Expanded(
                child: PageView.builder(
                  key: const Key('onboarding_pager'),
                  controller: _pageController,
                  itemCount: total,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) {
                    final step = _steps[i];
                    return Semantics(
                      container: true,
                      label: step.semanticsLabel,
                      child: _OnboardingStepBody(step: step),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (_index > 0)
                    Semantics(
                      button: true,
                      label: 'Back to previous onboarding step',
                      child: OutlinedButton(
                        key: const Key('onboarding_back'),
                        onPressed: _finishing ? null : _back,
                        child: const Text('Back'),
                      ),
                    )
                  else
                    const SizedBox(width: 88),
                  const Spacer(),
                  Semantics(
                    button: true,
                    label: isLast
                        ? 'Finish onboarding'
                        : 'Next onboarding step',
                    child: FilledButton(
                      key: Key(isLast
                          ? 'onboarding_finish'
                          : 'onboarding_next'),
                      onPressed: _finishing ? null : () => _next(),
                      child: Text(isLast ? 'Finish' : 'Next'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingStepBody extends StatelessWidget {
  final OnboardingStep step;

  const _OnboardingStepBody({required this.step});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: AppRadius.brXxl,
          ),
          child: Icon(step.icon, size: 44, color: cs.onPrimaryContainer),
        ),
        const SizedBox(height: 28),
        Text(
          step.title,
          key: Key('onboarding_title_${step.featureRoute}'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 12),
        Text(
          step.body,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.45,
              ),
        ),
      ],
    );
  }
}
