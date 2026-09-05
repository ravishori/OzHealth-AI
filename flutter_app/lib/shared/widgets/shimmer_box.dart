import 'package:flutter/material.dart';

/// Animated shimmer skeleton placeholder. Drop-in replacement for
/// CircularProgressIndicator loading states.
///
/// Usage:
///   ShimmerBox(width: double.infinity, height: 64, radius: 12)
///   ShimmerBox.circle(size: 48)
///   ShimmerLine()               // full-width 14-high text line
class ShimmerBox extends StatefulWidget {
  const ShimmerBox({
    super.key,
    this.width,
    this.height = 16,
    this.radius = 8,
    this.shape = BoxShape.rectangle,
  });

  const ShimmerBox.circle({super.key, required double size})
      : width = size,
        height = size,
        radius = size / 2,
        shape = BoxShape.circle;

  final double? width;
  final double height;
  final double radius;
  final BoxShape shape;

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _anim = Tween<double>(begin: -1.5, end: 2.5).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = cs.surfaceContainerHighest;
    final highlight = cs.surfaceContainerLow;

    return AnimatedBuilder(
      animation: _anim,
      builder: (ctx, _) {
        final v = _anim.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            shape: widget.shape,
            borderRadius: widget.shape == BoxShape.circle
                ? null
                : BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(v - 1, 0),
              end: Alignment(v + 1, 0),
              colors: [base, highlight, highlight, base],
              stops: const [0.0, 0.4, 0.6, 1.0],
            ),
          ),
        );
      },
    );
  }
}

/// A single shimmer text line (full-width, short height).
class ShimmerLine extends StatelessWidget {
  const ShimmerLine({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 6,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => ShimmerBox(
        width: width,
        height: height,
        radius: radius,
      );
}

/// A multi-line shimmer card skeleton with a leading icon placeholder,
/// a title line, and two body lines.
class ShimmerCard extends StatelessWidget {
  const ShimmerCard({super.key, this.height = 90, this.margin});

  final double height;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Use minHeight so content always determines the actual height.
      // A fixed `height` would clip the inner Column if padding leaves
      // less vertical space than the shimmer lines need (e.g. 76dp card
      // with padding:16 → 44dp inner, but 3 lines + gaps = 51dp → 7px overflow).
      constraints: BoxConstraints(minHeight: height),
      margin: margin ?? const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ShimmerBox.circle(size: 44),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ShimmerLine(height: 14, radius: 6),
                SizedBox(height: 6),
                ShimmerLine(width: 160, height: 12, radius: 5),
                SizedBox(height: 5),
                ShimmerLine(width: 100, height: 10, radius: 5),
              ],
            ),
          ),
          SizedBox(width: 12),
          ShimmerBox(width: 44, height: 24, radius: 12),
        ],
      ),
    );
  }
}
