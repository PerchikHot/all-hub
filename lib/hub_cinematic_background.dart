import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Decorative All Hub backdrop, shared by Android and Windows.
/// Drawn locally: no network artwork, no image loading or scroll jank.
class HubCinematicBackground extends StatelessWidget {
  const HubCinematicBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).brightness != Brightness.dark) return child;
    return Stack(fit: StackFit.expand, children: [
      const IgnorePointer(child: RepaintBoundary(
        child: CustomPaint(painter: _HubBackdropPainter()))),
      child,
    ]);
  }
}

class _HubBackdropPainter extends CustomPainter {
  const _HubBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..shader = const LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [Color(0xFF071327), Color(0xFF101C40),
        Color(0xFF17112D), Color(0xFF070D1D)],
      stops: [0, .36, .7, 1],
    ).createShader(rect));

    for (final glow in [
      (Offset(size.width * .92, size.height * .10), size.width * .63,
        const Color(0x253D8CFF)),
      (Offset(size.width * .12, size.height * .88), size.width * .57,
        const Color(0x1C9154EA)),
    ]) {
      canvas.drawCircle(glow.$1, glow.$2, Paint()
        ..shader = RadialGradient(colors: [glow.$3, Colors.transparent])
          .createShader(Rect.fromCircle(center: glow.$1, radius: glow.$2)));
    }

    final origin = Offset(size.width * .85, size.height * .19);
    final diamond = Path()
      ..moveTo(origin.dx, origin.dy - 34)
      ..lineTo(origin.dx + 20, origin.dy)
      ..lineTo(origin.dx, origin.dy + 34)
      ..lineTo(origin.dx - 20, origin.dy)
      ..close();
    canvas.drawPath(diamond, Paint()
      ..color = const Color(0x334F9DFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
    for (var i = 0; i < 12; i++) {
      final x = size.width * ((i * .173) % 1);
      final y = size.height * ((i * .317) % 1);
      final radius = 1.0 + .6 * math.sin(i * 2.0).abs();
      canvas.drawCircle(Offset(x, y), radius,
        Paint()..color = const Color(0x335FADFF));
    }
  }

  @override
  bool shouldRepaint(covariant _HubBackdropPainter old) => false;
}
