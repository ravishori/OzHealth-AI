import 'package:flutter/material.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';

/// Press-down scale feedback (0.96) for interactive cards.
/// Respects [HealthcareColors.animationMultiplier] and reduced-motion.
class TapScale extends StatefulWidget {
  const TapScale({
    super.key,
    required this.child,
    required this.onTap,
    this.scale = 0.96,
  });

  final Widget child;
  final VoidCallback onTap;
  final double scale;

  @override
  State<TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<TapScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 110),
      reverseDuration: const Duration(milliseconds: 160),
    );
    _scale = Tween<double>(begin: 1, end: widget.scale).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Duration _dur(BuildContext context, Duration base) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce) return Duration.zero;
    return HealthcareColors.of(context).animatedDuration(base);
  }

  Future<void> _handleTap() async {
    final forward = _dur(context, const Duration(milliseconds: 110));
    final reverse = _dur(context, const Duration(milliseconds: 160));
    _ctrl.duration = forward;
    _ctrl.reverseDuration = reverse;
    await _ctrl.forward();
    if (!mounted) return;
    await _ctrl.reverse();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleTap,
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}
