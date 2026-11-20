import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Waiting / refreshing: a looping figure-eight with two rounded lobes and
/// contrasting dots. Unlike file transfers, this never implies a percentage.
class HubWaitIndicator extends StatefulWidget {
  const HubWaitIndicator({super.key, this.size = 84});
  final double size;
  @override
  State<HubWaitIndicator> createState() => _HubWaitIndicatorState();
}

class _HubWaitIndicatorState extends State<HubWaitIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 1050),
  )..repeat();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: 'Загрузка страницы',
      child: SizedBox(
        width: widget.size, height: widget.size * .78,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => CustomPaint(
            painter: _WaitPainter(phase: reduceMotion ? 0 : controller.value),
          ),
        ),
      ),
    );
  }
}

class _WaitPainter extends CustomPainter {
  const _WaitPainter({required this.phase});
  final double phase;
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final scale = size.width / 64;
    final left = center + Offset(-13 * scale, 3 * scale);
    final right = center + Offset(13 * scale, 3 * scale);
    // A subtle upper-body silhouette makes the paired animated shapes
    // legible as Eyra's stylized bust even at small loading-indicator sizes.
    final shoulderPath = Path()
      ..moveTo(center.dx - 31 * scale, center.dy + 20 * scale)
      ..quadraticBezierTo(center.dx - 31 * scale, center.dy - 12 * scale,
          center.dx - 13 * scale, center.dy - 13 * scale)
      ..quadraticBezierTo(center.dx, center.dy - 23 * scale,
          center.dx + 13 * scale, center.dy - 13 * scale)
      ..quadraticBezierTo(center.dx + 31 * scale, center.dy - 12 * scale,
          center.dx + 31 * scale, center.dy + 20 * scale);
    canvas.drawPath(shoulderPath, Paint()
      ..color = const Color(0xFF8C5B72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2 * scale);
    final lobePaint = Paint()..color = const Color(0xFFE9B79F);
    final outline = Paint()
      ..color = const Color(0xFFB97E73)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 * scale;
    // Both clearly visible rounded forms move alternately; no progress
    // percentage is implied by this decorative loading animation.
    // Both lobes stay visible; each bounce compresses briefly on landing.
    for (var i = 0; i < 2; i++) {
      final localPhase = (phase * 2 - i) % 2;
      final active = localPhase < 1;
      final progress = active ? localPhase : 0.0;
      final lift = active ? math.pow(math.sin(progress * math.pi), 1.4).toDouble() * 5 * scale : 0.0;
      final landing = active && progress > .84
        ? math.sin((progress - .84) / .16 * math.pi) * .10 : 0.0;
      final point = (i == 0 ? left : right) - Offset(0, lift);
      canvas.save();
      canvas.translate(point.dx, point.dy);
      canvas.scale(1 + landing, 1 - landing);
      canvas.drawOval(Rect.fromCenter(center: Offset.zero,
        width: 25 * scale, height: 27 * scale), lobePaint);
      canvas.drawOval(Rect.fromCenter(center: Offset.zero,
        width: 25 * scale, height: 27 * scale), outline);
      canvas.drawCircle(Offset(0, 3 * scale), 2.4 * scale,
        Paint()..color = const Color(0xFFB86B79));
      canvas.restore();
    }
  }
  @override
  bool shouldRepaint(covariant _WaitPainter old) => old.phase != phase;
}

/// Response generation: an animated three-dot bubble, without pretending to
/// expose the model's private reasoning or a fictitious completion percentage.
class HubAiResponding extends StatefulWidget {
  const HubAiResponding({super.key});
  @override
  State<HubAiResponding> createState() => _HubAiRespondingState();
}

class _HubAiRespondingState extends State<HubAiResponding>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 1200),
  )..repeat();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Эйра формирует ответ',
    child: AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome_rounded, color: Color(0xFF9CC9FF), size: 18),
          const SizedBox(width: 9),
          const Text('Эйра отвечает', style: TextStyle(
            color: Color(0xFFDCEBFF), fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          for (var i = 0; i < 3; i++) Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Transform.translate(
              offset: Offset(0, -3 * math.max(0,
                math.sin(controller.value * 2 * math.pi - i * .8))),
              child: const CircleAvatar(
                radius: 3, backgroundColor: Color(0xFF9CC9FF)),
            ),
          ),
        ],
      ),
    ),
  );
}
