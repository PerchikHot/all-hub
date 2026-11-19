import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A compact white flowing-liquid progress bar. Determinate mode fills to
/// [value]; null shows a moving stream without inventing a percentage.
class HubLiquidProgress extends StatefulWidget {
  const HubLiquidProgress({super.key, this.value, this.height = 8});
  final double? value;
  final double height;

  @override
  State<HubLiquidProgress> createState() => _HubLiquidProgressState();
}

class _HubLiquidProgressState extends State<HubLiquidProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flow = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 1700),
  )..repeat();

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: 'Прогресс загрузки',
      value: widget.value == null ? 'Выполняется'
          : '${(widget.value!.clamp(0.0, 1.0) * 100).round()}%',
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: AnimatedBuilder(
          animation: _flow,
          builder: (context, _) => CustomPaint(
            painter: _LiquidPainter(
              phase: reducedMotion ? 0 : _flow.value,
              progress: widget.value,
            ),
          ),
        ),
      ),
    );
  }
}

class _LiquidPainter extends CustomPainter {
  const _LiquidPainter({required this.phase, required this.progress});
  final double phase;
  final double? progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final h = size.height;
    final w = size.width;
    final track = RRect.fromRectAndRadius(
      Offset.zero & size, Radius.circular(h / 2),
    );
    canvas.drawRRect(track, Paint()..color = const Color(0xFF1C2941));
    canvas.save();
    canvas.clipRRect(track);

    final bounded = progress?.isFinite == true
        ? progress!.clamp(0.0, 1.0).toDouble() : null;
    final fill = bounded == null ? w * .32 : w * bounded;
    final start = bounded == null ? (w + fill) * phase - fill : 0.0;
    final end = start + fill;

    // The actual downloaded fraction determines the fill boundary.
    // Surface motion, viscosity and droplets are purely decorative.
    final body = Path()..moveTo(start, h);
    body.lineTo(start, h * .22);
    const steps = 64;
    for (var i = 0; i <= steps; i++) {
      final x = start + fill * i / steps;
      final ripple = math.sin(x * .065 - phase * math.pi * 2) * h * .035
          + math.sin(x * .13 + phase * math.pi * 2) * h * .022;
      body.lineTo(x, h * .20 + ripple);
    }
    body..lineTo(end, h)..close();
    canvas.drawPath(body, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [Color(0xFFFFFFFF), Color(0xFFF0F2F6),
          Color(0xFFCDD7E4)],
      ).createShader(Offset.zero & size));

    // Glossy streaks drift within the filled region.
    canvas.save();
    canvas.clipPath(body);
    for (var i = 0; i < 4; i++) {
      final x = start + ((phase * .55 + i * .27) % 1.0) * fill;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, h * .52),
          width: math.max(3, fill * .12), height: h * .14),
        Paint()..color = const Color(0x77FFFFFF),
      );
    }
    canvas.restore();

    // A rounded, slightly irregular meniscus and tiny suspended droplets.
    if (fill > h * .5 && (bounded == null || bounded < 1)) {
      final tip = end.clamp(0.0, w).toDouble();
      canvas.drawOval(
        Rect.fromCenter(center: Offset(tip - h * .10, h * .52),
          width: h * .40, height: h * .72),
        Paint()..color = const Color(0xFFF4F7FB),
      );
      for (var i = 0; i < 3; i++) {
        final drift = math.sin(phase * math.pi * 2 + i * 2.1);
        final dx = tip - h * (.20 + i * .28) + drift * h * .08;
        final dy = h * (.30 + i * .18);
        canvas.drawCircle(Offset(dx, dy), h * (.045 + i * .012),
          Paint()..color = const Color(0xDDFBFCFF));
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LiquidPainter old) =>
      phase != old.phase || progress != old.progress;
}
