import 'dart:math' as math;
import 'package:flutter/material.dart';

enum HubLiquidStyle { wave, capsule, segmented, reservoir }

/// A compact white flowing-liquid progress bar. Determinate mode fills to
/// [value]; null shows a moving stream without inventing a percentage.
class HubLiquidProgress extends StatefulWidget {
  const HubLiquidProgress({super.key, this.value, this.height = 12, this.style = HubLiquidStyle.wave});
  final double? value;
  final double height;
  final HubLiquidStyle style;

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
    final safeValue = widget.value != null && widget.value!.isFinite
        ? widget.value!.clamp(0.0, 1.0).toDouble() : null;
    return Semantics(
      label: 'Прогресс загрузки',
      value: safeValue == null ? 'Выполняется'
          : '${(safeValue * 100).round()}%',
      child: SizedBox(
        height: math.max(widget.height + 18, 42),
        width: double.infinity,
        child: AnimatedBuilder(
          animation: _flow,
          builder: (context, _) {
            final completed = safeValue == 1.0;
            return Row(children: [
              SizedBox(width: 46, height: 42,
                child: CustomPaint(painter: _GelNozzlePainter(
                  phase: reducedMotion ? 0 : _flow.value))),
              const SizedBox(width: 2),
              Expanded(child: SizedBox(height: widget.height,
                child: CustomPaint(painter: _LiquidPainter(
                  phase: reducedMotion ? 0 : _flow.value,
                  progress: safeValue,
                  style: widget.style,
                )))),
              const SizedBox(width: 3),
              SizedBox(width: 42, height: 42,
                child: CustomPaint(painter: _GelTargetPainter(
                  completed: completed,
                  phase: reducedMotion ? 0 : _flow.value))),
            ]);
          },
        ),
      ),
    );
  }
}

class _LiquidPainter extends CustomPainter {
  const _LiquidPainter({required this.phase, required this.progress, required this.style});
  final double phase;
  final double? progress;
  final HubLiquidStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final h = size.height;
    final w = size.width;
    final track = RRect.fromRectAndRadius(
      Offset.zero & size, Radius.circular(h / 2),
    );
    canvas.drawRRect(track, Paint()..color = const Color(0xFF111D35));
    canvas.drawRRect(track, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.min(1.5, h * .12)
      ..color = const Color(0xFF5F9FEF));
    canvas.drawRRect(track, Paint()
      ..color = const Color(0xFF4D8DD7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.min(1.6, h * .12));
    canvas.save();
    canvas.clipRRect(track);

    final bounded = progress?.isFinite == true
        ? progress!.clamp(0.0, 1.0).toDouble() : null;
    final fill = bounded == null ? w * .32 : w * bounded;
    if (bounded == 0) {
      canvas.restore();
      return;
    }
    final start = bounded == null ? (w + fill) * phase - fill : 0.0;
    final end = start + fill;

    // The actual downloaded fraction determines the fill boundary.
    // Surface motion, viscosity and droplets are purely decorative.
    final body = Path()..moveTo(start, h);
    body.lineTo(start, h * .20);
    const steps = 64;
    for (var i = 0; i <= steps; i++) {
      final x = start + fill * i / steps;
      final ripple = (style == HubLiquidStyle.capsule ? .10 :
          style == HubLiquidStyle.segmented ? .012 : .12) * h *
          math.sin(x * .065 - phase * math.pi * 2)
          + math.sin(x * .13 + phase * math.pi * 4) * h * .048;
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

    // Bright soft foam and reflections move independently of real progress.
    canvas.save();
    canvas.clipPath(body);
    canvas.drawRect(Offset(start, h * .12) & Size(fill, h * .18), Paint()
      ..color = const Color(0x99FFFFFF)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * .14));
    canvas.restore();

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

    // Gel-like bubbles stay inside the capsule; the real fill edge remains exact.
    canvas.save();
    canvas.clipPath(body);
    for (var i = 0; i < 7; i++) {
      final dx = start + ((i * .173 + phase * .16) % 1.0) * fill;
      final dy = h * (.30 + .36 * (1 + math.sin(i * 2.7 + phase * math.pi * 2)) / 2);
      canvas.drawCircle(Offset(dx, dy), h * (.045 + (i % 3) * .022),
        Paint()..color = const Color(0xB8FFFFFF));
    }
    canvas.restore();

    // A rounded, slightly irregular meniscus and tiny suspended droplets.
    if (fill > h * .5 && (bounded == null || bounded < 1)) {
      final tip = end.clamp(0.0, w).toDouble();
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(start, 0, fill, h));
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
      canvas.restore();
    }
    if (style == HubLiquidStyle.segmented) {
      for (var x = h * 1.7; x < w; x += h * 2.1) {
        canvas.drawLine(Offset(x, 1), Offset(x - h * .35, h - 1),
          Paint()..color = const Color(0xAA091A35)..strokeWidth = math.max(1, h * .12));
      }
    } else if (style == HubLiquidStyle.reservoir) {
      canvas.drawCircle(Offset(h * .5, h * .5), h * .43,
        Paint()..color = const Color(0xAAE8F6FF)..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, h * .1));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LiquidPainter old) =>
      phase != old.phase || progress != old.progress || style != old.style;
}

 
/// A stylized sci-fi dispenser, not a weapon or a functional control.
class _GelNozzlePainter extends CustomPainter {
  const _GelNozzlePainter({required this.phase});
  final double phase;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 31, size.height / 26);
    const y = 13.0;
    final outline = Paint()..color = const Color(0xFF69B7FF)
      ..style = PaintingStyle.stroke..strokeWidth = 1.6;
    final body = Path()
      ..moveTo(2, y - 7)..lineTo(18, y - 7)
      ..lineTo(18, y - 4)..lineTo(29, y - 4)
      ..lineTo(29, y + 3)..lineTo(17, y + 3)
      ..lineTo(14, y + 11)..lineTo(7, y + 11)
      ..lineTo(10, y + 3)..lineTo(2, y + 3)..close();
    canvas.drawPath(body, Paint()..color = const Color(0xFF17345D));
    canvas.drawPath(body, outline);
    canvas.drawLine(Offset(6, y - 3), Offset(17, y - 3),
      Paint()..color = const Color(0xFFB8DFFF)..strokeWidth = 2);
    final pulse = .65 + .35 * math.sin(phase * math.pi * 2).abs();
    canvas.drawCircle(Offset(29, y), 1.6 * pulse,
      Paint()..color = const Color(0xFFEAF9FF));
    canvas.restore();
  }
  @override
  bool shouldRepaint(covariant _GelNozzlePainter old) => old.phase != phase;
}

/// A playful, abstract concentric target with a completion flash.
class _GelTargetPainter extends CustomPainter {
  const _GelTargetPainter({required this.completed, required this.phase});
  final bool completed;
  final double phase;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate((size.width - 26) / 2, (size.height - 26) / 2);
    const center = Offset(13, 13);
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(center, 11.5 - i * 3.5, Paint()
        ..color = completed ? const Color(0xFFECF8FF) :
          (i.isEven ? const Color(0xFF4A91E8) : const Color(0xFF13294D))
        ..style = i == 0 ? PaintingStyle.stroke : PaintingStyle.fill
        ..strokeWidth = 1.7);
    }
    canvas.drawCircle(center, completed ? 4.0 + math.sin(phase * math.pi * 2).abs() * 2 : 2.5,
      Paint()..color = const Color(0xFFFFFFFF));
    canvas.restore();
  }
  @override
  bool shouldRepaint(covariant _GelTargetPainter old) =>
      old.phase != phase || old.completed != completed;
}
