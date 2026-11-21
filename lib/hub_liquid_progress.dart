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
    with TickerProviderStateMixin {
  late final AnimationController _splash = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 850),
  );
  double? _previousProgress;

  late final AnimationController _flow = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 1700),
  )..repeat();

  @override
  void initState() {
    super.initState();
    _previousProgress = _safeProgress(widget.value);
  }

  static double? _safeProgress(double? value) =>
      value != null && value.isFinite ? value.clamp(0.0, 1.0).toDouble() : null;

  @override
  void didUpdateWidget(covariant HubLiquidProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _safeProgress(widget.value);
    if (next != null && next >= 1 &&
        (_previousProgress == null || _previousProgress! < 1)) {
      _splash.forward(from: 0);
    } else if (next == null || next < 1) {
      _splash.reset();
    }
    _previousProgress = next;
  }

  @override
  void dispose() {
    _splash.dispose();
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final safeValue = _safeProgress(widget.value);
    return Semantics(
      label: 'Прогресс загрузки',
      value: safeValue == null ? 'Выполняется'
          : '${(safeValue * 100).round()}%',
      child: SizedBox(
        height: math.max(widget.height + 12, 28),
        width: double.infinity,
        child: TickerMode(
          enabled: !reducedMotion,
          child: AnimatedBuilder(
          animation: Listenable.merge([_flow, _splash]),
          builder: (context, _) {
            return SizedBox(
              height: math.max(widget.height, 12),
              width: double.infinity,
              child: CustomPaint(painter: _LiquidPainter(
                phase: reducedMotion ? 0 : _flow.value,
                progress: safeValue,
                style: widget.style,
                splash: reducedMotion ? 1 : _splash.value,
              )),
            );
          },
        ),
        ),
      ),
    );
  }
}

class _LiquidPainter extends CustomPainter {
  const _LiquidPainter({required this.phase, required this.progress, required this.style, required this.splash});
  final double splash;
  final double phase;
  final double? progress;
  final HubLiquidStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final h = size.height;
    final w = size.width;
    if (h <= 0 || w <= 0) return;
    final track = RRect.fromRectAndRadius(
      Offset.zero & size, Radius.circular(h / 2),
    );
    canvas.drawRRect(track, Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xFF071021), Color(0xFF1B3657),
          Color(0xFF0A142A)],
      ).createShader(Offset.zero & size));
    canvas.drawRRect(track, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.min(2.2, h * .10)
      ..color = const Color(0xFF70C5FF));
    canvas.drawRRect(track, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.min(5, h * .22)
      ..color = const Color(0x4458B7FF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));

    canvas.save();
    canvas.clipRRect(track);

    final bounded = progress?.isFinite == true
        ? progress!.clamp(0.0, 1.0).toDouble() : null;
    // Unknown-duration work is a gently breathing reservoir, not a white
    // slug racing from left to right and impersonating a download percentage.
    // Indeterminate mode must never resemble 100% completed progress.
    // A travelling glassy highlight communicates activity without a fake fill.
    if (bounded == null) {
      final travel = (phase * 1.4) % 1.0;
      final center = (travel * 1.4 - .2) * w;
      final bandWidth = math.min(w * .32, math.max(h * 2.4, 24.0));
      final band = Rect.fromCenter(
        center: Offset(center, h / 2),
        width: bandWidth,
        height: h,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(band, Radius.circular(h / 2)),
        Paint()
          ..shader = const LinearGradient(
            colors: [
              Color(0x00FFFFFF),
              Color(0x77FFFFFF),
              Color(0xFFEAF8FF),
              Color(0x77FFFFFF),
              Color(0x00FFFFFF),
            ],
          ).createShader(band),
      );
      canvas.restore();
      return;
    }
    final fill = w * bounded;
    if (bounded == 0) {
      canvas.restore();
      return;
    }
    final start = 0.0;
    final end = start + fill;

    // The actual downloaded fraction determines the fill boundary.
    // Surface motion, viscosity and droplets are purely decorative.
    final body = Path()..moveTo(start, h);
    body.lineTo(start, bounded == null ? h * .40 : h * .20);
    const steps = 96;
    for (var i = 0; i <= steps; i++) {
      final x = start + fill * i / steps;
      final ripple = (style == HubLiquidStyle.capsule ? .10 :
          style == HubLiquidStyle.segmented ? .012 : .12) * h *
          math.sin(x * .065 - phase * math.pi * 2)
          + math.sin(x * .13 + phase * math.pi * 4) * h * .048
          + math.sin(x * .23 - phase * math.pi * 6) * h * .024;
      body.lineTo(x, (bounded == null ? h * .40 : h * .20) + ripple);
    }
    body..lineTo(end, h)..close();
    canvas.drawPath(body, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [Color(0xFFFFFFFF), Color(0xFFF0F2F6),
          Color(0xFFCDD7E4)],
      ).createShader(Offset.zero & size));

    // The reference uses thick, sculpted white liquid, not a flat fill.
    // Broad glossy folds are layered beneath the animated crests.
    canvas.save();
    canvas.clipPath(body);
    for (var i = 0; i < 5; i++) {
      final t = (i * .24 + phase * .09) % 1.0;
      final x = start + fill * t;
      final swell = h * (.28 + .09 * math.sin(i * 1.7 + phase * 5));
      canvas.drawOval(Rect.fromCenter(
        center: Offset(x, h * .56),
        width: h * (1.2 + (i % 3) * .3),
        height: swell * 1.5,
      ), Paint()
        ..shader = RadialGradient(colors: const [
          Color(0xEEFFFFFF), Color(0x99EDF6FF), Color(0x00D7EBFF),
        ]).createShader(Rect.fromCircle(
          center: Offset(x, h * .56), radius: h)));
    }
    canvas.restore();

    // Large rolling crests, based on the update-screen reference: the
    // surface bulges in broad, irregular waves rather than tiny ripples.
    // Everything is clipped to the true fill and capsule.
    canvas.save();
    canvas.clipPath(body);
    final crest = Path()..moveTo(start, h * .48);
    for (var i = 0; i <= 120; i++) {
      final t = i / 120;
      final x = start + fill * t;
      final envelope = math.sin(t * math.pi).abs();
      final rolling = math.sin(t * math.pi * 5 - phase * math.pi * 2);
      final secondary = math.sin(t * math.pi * 9 + phase * math.pi * 1.4);
      crest.lineTo(x, h * (.40 - envelope * (.15 * rolling + .05 * secondary)));
    }
    crest..lineTo(end, h)..lineTo(start, h)..close();
    canvas.drawPath(crest, Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xFFFEFFFF), Color(0xFFF1F6FD), Color(0xFFB8D4F4)],
      ).createShader(Offset.zero & size));
    canvas.restore();

    // Slow translucent surface sheets simulate heavy folds of liquid.
    canvas.save();
    canvas.clipPath(body);
    for (var i = 0; i < 4; i++) {
      final t = ((i * .31 + phase * .13) % 1.0);
      final x = start + fill * t;
      final radius = h * (.32 + i * .035);
      canvas.drawOval(Rect.fromCenter(
        center: Offset(x, h * (.42 + .08 * math.sin(phase * 6 + i))),
        width: radius * 2.4, height: radius * 1.1,
      ), Paint()..color = const Color(0x77FFFFFF));
    }
    canvas.restore();

    // Bright soft foam and reflections move independently of real progress.
    canvas.save();
    canvas.clipPath(body);
    canvas.drawRect(Offset(start, h * .12) & Size(fill, h * .18), Paint()
      ..color = const Color(0x99FFFFFF)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * .14));
    canvas.restore();

    // Layered translucent flow makes the white liquid feel viscous.
    canvas.save();
    canvas.clipPath(body);
    for (var i = 0; i < 5; i++) {
      final x = start + ((phase * .32 + i * .23) % 1.0) * fill;
      canvas.drawOval(Rect.fromCenter(
        center: Offset(x, h * (.40 + .07 * math.sin(i + phase * 6))),
        width: math.max(h * .7, fill * .19), height: h * .35),
        Paint()..color = const Color(0x55FFFFFF));
    }
    canvas.restore();

    // Viscous strands stretch and merge with the main white flow. The
    // geometry is strictly clipped to the measured fill, so decoration never
    // makes the download appear further along than it really is.
    canvas.save();
    canvas.clipPath(body);
    for (var i = 0; i < 9; i++) {
      final seed = i * .137;
      final travel = (seed + phase * (.10 + (i % 3) * .025)) % 1.0;
      final x = start + fill * travel;
      final sway = math.sin(phase * math.pi * 2 + i * 1.8);
      final strandWidth = h * (.12 + (i % 4) * .035);
      final strandLength = h * (.20 + .22 * (1 + sway) / 2);
      final strand = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, h * (.15 + .10 * sway),
          strandWidth, strandLength),
        Radius.circular(strandWidth / 2),
      );
      canvas.drawRRect(strand, Paint()
        ..color = i.isEven
          ? const Color(0x88FFFFFF)
          : const Color(0x55D9E4F1));
    }
    // A smooth reflective ribbon reads as thick, cohesive liquid rather
    // than a sequence of detached dots.
    final ribbon = Path()..moveTo(start, h * .68);
    for (var i = 0; i <= 72; i++) {
      final x = start + fill * i / 72;
      final y = h * (.68 + .075 *
        math.sin(i * .20 - phase * math.pi * 2));
      ribbon.lineTo(x, y);
    }
    canvas.drawPath(ribbon, Paint()
      ..color = const Color(0xAAFFFFFF)
      ..strokeWidth = math.max(1, h * .075)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke);
    canvas.restore();

    // Rounded hanging droplets add the reference's characteristic heavy
    // drips without ever crossing the measured progress boundary.
    canvas.save();
    canvas.clipPath(body);
    for (var i = 0; i < 6; i++) {
      final t = (i + .6) / 7;
      final x = start + fill * t;
      final wobble = math.sin(phase * math.pi * 2 + i * 1.9);
      final dropLength = h * (.13 + .13 * (1 + wobble) / 2);
      final neckWidth = h * (.075 + (i % 3) * .012);
      final top = h * (.54 + .04 * math.sin(i * 2.1));
      final drop = Path()
        ..moveTo(x - neckWidth, top)
        ..quadraticBezierTo(x - neckWidth * 1.3, top + dropLength * .7,
          x - neckWidth * .7, top + dropLength)
        ..quadraticBezierTo(x, top + dropLength + neckWidth * .65,
          x + neckWidth * .7, top + dropLength)
        ..quadraticBezierTo(x + neckWidth * 1.3, top + dropLength * .7,
          x + neckWidth, top)
        ..close();
      canvas.drawPath(drop, Paint()..color = const Color(0xFFF9FCFF));
      canvas.drawOval(Rect.fromCenter(
        center: Offset(x - neckWidth * .3, top + dropLength * .72),
        width: neckWidth * .5, height: neckWidth * .8),
        Paint()..color = const Color(0x99FFFFFF));
    }
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

    // Small surface spills live outside the glass clip but inside the
    // widget's reserved vertical gutter. Never change the progress edge.
    if (bounded > .08 && bounded < 1) {
      for (var i = 0; i < 4; i++) {
        final t = (i + .65) / 5;
        final x = math.min(fill - h * .16, math.max(h * .16, fill * t));
        final sway = math.sin(phase * math.pi * 2 + i * 2.3);
        final length = h * (.12 + .09 * (1 + sway) / 2);
        final y = i.isEven ? -h * .04 : h * .96;
        final drop = Path()
          ..moveTo(x - h * .075, y)
          ..quadraticBezierTo(x - h * .10, y + (i.isEven ? -length : length) * .55,
              x, y + (i.isEven ? -length : length))
          ..quadraticBezierTo(x + h * .10, y + (i.isEven ? -length : length) * .55,
              x + h * .075, y)
          ..close();
        canvas.drawPath(drop, Paint()..color = const Color(0xCFF5FAFF));
      }
    }

    // One-shot completion splash, fired only on transition to 100%.
    if (bounded >= 1 && splash > 0 && splash < 1) {
      final fade = (1 - splash) * (1 - splash);
      final paint = Paint()
        ..color = Color.fromRGBO(239, 249, 255, fade.clamp(0.0, 1.0));
      final origin = Offset(w * .94, h * .5);
      for (var i = 0; i < 9; i++) {
        final angle = -math.pi + i * math.pi / 8;
        final distance = h * (.15 + 1.1 * Curves.easeOutCubic.transform(splash));
        final center = origin + Offset(math.cos(angle), math.sin(angle)) * distance;
        canvas.drawCircle(center, h * (.035 + (i % 3) * .018) * (1 - splash * .6), paint);
      }
      final ring = Paint()
        ..color = Color.fromRGBO(185, 229, 255, fade.clamp(0.0, 1.0))
        ..strokeWidth = math.max(.8, h * .045) * (1 - splash)
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(origin, h * (.25 + splash * .95), ring);
    }
  }

  @override
  bool shouldRepaint(covariant _LiquidPainter old) =>
      phase != old.phase || progress != old.progress ||
      style != old.style || splash != old.splash;
}

 
