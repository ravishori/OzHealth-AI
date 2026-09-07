import 'package:flutter/material.dart';

/// Entrance fade + slight upward slide — used for staggered dashboard sections.
class FadeSlide extends StatelessWidget {
  const FadeSlide({
    super.key,
    required this.animation,
    required this.child,
    this.offset = const Offset(0, 0.06),
  });

  final Animation<double> animation;
  final Widget child;
  final Offset offset;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce) return child;

    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(begin: offset, end: Offset.zero).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: child,
      ),
    );
  }
}
