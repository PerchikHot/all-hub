import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Waiting / refreshing: a looping figure-eight with two rounded lobes and
/// contrasting dots. Unlike file transfers, this never implies a percentage.
class HubWaitIndicator extends StatefulWidget {
  const HubWaitIndicator({super.key, this.size = 42});
  final double size;
  @override
  State<HubWaitIndicator> createState() => _HubWaitIndicatorState();
}

class _HubWaitIndicatorState extends State<HubWaitIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 1500),
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
        width: widget.size, height: widget.size * .65,
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
    final scale = size.width / 48;
    final left = center + Offset(-11 * scale, 0);
    final right = center + Offset(11 * scale, 0);
    final lobePaint = Paint()..color = const Color(0xFFECF2FF);
    final outline = Paint()
      ..color = const Color(0xFF91B9F2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 * scale;
    for (final point in [left, right]) {
      canvas.drawCircle(point, 10 * scale, lobePaint);
      canvas.drawCircle(point, 10 * scale, outline);
      canvas.drawCircle(point + Offset(0, 2 * scale), 2.7 * scale,
        Paint()..color = const Color(0xFF6886B6));
    }
    // An illuminated bead travels continuously around the figure-eight.
    final t = phase * math.pi * 2;
    final x = math.sin(t) * 20 * scale;
    final y = math.sin(2 * t) * 9 * scale;
    canvas.drawCircle(center + Offset(x, y), 3 * scale,
      Paint()..color = const Color(0xFF5D9BFF));
    canvas.drawCircle(center + Offset(x, y), 1.3 * scale,
      Paint()..color = Colors.white);
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
