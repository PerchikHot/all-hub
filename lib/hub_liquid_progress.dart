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
    final radius = Radius.circular(size.height / 2);
    final track = RRect.fromRectAndRadius(Offset.zero & size, radius);
    canvas.drawRRect(track, Paint()..color = const Color(0xFF293C59));
    canvas.save();
    canvas.clipRRect(track);

    final bounded = progress?.isFinite == true
        ? progress!.clamp(0.0, 1.0).toDouble() : null;
    final width = bounded == null ? size.width * .36 : size.width * bounded;
    final start = bounded == null
        ? (size.width + width) * phase - width : 0.0;
    final path = Path()..moveTo(start, 0);
    const segments = 48;
    for (var i = 0; i <= segments; i++) {
      final x = start + width * i / segments;
      final wave = math.sin((i / segments * 3 * math.pi) - phase * 2 * math.pi)
          * math.min(1.3, size.height * .13);
      path.lineTo(x, size.height * .25 + wave);
    }
    path..lineTo(start + width, size.height)
        ..lineTo(start, size.height)..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFF8FBFF));
    canvas.drawPath(path, Paint()
      ..color = const Color(0x88FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .7);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LiquidPainter old) =>
      phase != old.phase || progress != old.progress;
}
