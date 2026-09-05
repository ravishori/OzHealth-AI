import 'package:flutter/material.dart';

/// HealthNest shield logo with ECG pulse line.
/// Rendered via CustomPainter — no asset files required.
class VitaPulseLogo extends StatelessWidget {
  final double size;

  const VitaPulseLogo({super.key, this.size = 72});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _ShieldPainter()),
    );
  }
}

class _ShieldPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final shieldPath = Path()
      ..moveTo(w * 0.5, h * 0.04)
      ..lineTo(w * 0.1, h * 0.22)
      ..lineTo(w * 0.1, h * 0.52)
      ..cubicTo(w * 0.1, h * 0.74, w * 0.28, h * 0.9, w * 0.5, h * 0.97)
      ..cubicTo(w * 0.72, h * 0.9, w * 0.9, h * 0.74, w * 0.9, h * 0.52)
      ..lineTo(w * 0.9, h * 0.22)
      ..close();

    final shieldPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF2B5FAD), Color(0xFF0F3068)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(shieldPath, shieldPaint);

    canvas.drawPath(
      shieldPath,
      Paint()
        ..color = const Color(0x14FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    final ecgPath = Path()
      ..moveTo(w * 0.15, h * 0.52)
      ..lineTo(w * 0.30, h * 0.52)
      ..lineTo(w * 0.38, h * 0.34)
      ..lineTo(w * 0.47, h * 0.66)
      ..lineTo(w * 0.56, h * 0.44)
      ..lineTo(w * 0.62, h * 0.52)
      ..lineTo(w * 0.85, h * 0.52);

    canvas.drawPath(
      ecgPath,
      Paint()
        ..color = const Color(0xFF00B4A2)
        ..strokeWidth = w * 0.05
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
