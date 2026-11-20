import 'dart:math' as math;
import 'dart:io';
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

/// Eyra's portrait-based response indicator. Uses the portrait selected in
/// settings, not a generic loading circle. Motion is decorative, not progress.
class HubAiResponding extends StatefulWidget {
  const HubAiResponding({super.key, this.avatarPath});
  final String? avatarPath;

  @override
  State<HubAiResponding> createState() => _HubAiRespondingState();
}

class _HubAiRespondingState extends State<HubAiResponding>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 1850),
  )..repeat();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final file = widget.avatarPath == null ? null : File(widget.avatarPath!);
    final hasPortrait = file != null && file.existsSync();
    return Semantics(
      label: 'Эйра формирует ответ, анимация ожидания',
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final phase = reduced ? 0.0 : controller.value * math.pi * 2;
          final sway = math.sin(phase);
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 118, height: 142,
                child: Stack(alignment: Alignment.center, children: [
                  Container(
                    width: 114, height: 138,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(color: const Color(0xFF4D86CD), width: 1.5),
                      boxShadow: [BoxShadow(
                        color: const Color(0x554C91FF),
                        blurRadius: 9 + (reduced ? 0 : 5 * (sway + 1) / 2),
                      )],
                    ),
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: SizedBox(
                      width: 108, height: 132,
                      child: hasPortrait
                        ? Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()
                              ..translate(2.0 * sway, -1.7 * math.cos(phase))
                              ..scale(1.05 + .016 * sway),
                            child: Image.file(file!, fit: BoxFit.cover,
                              gaplessPlayback: true,
                              errorBuilder: (_, __, ___) =>
                                const Icon(Icons.face_rounded, size: 48)),
                          )
                        : const ColoredBox(
                            color: Color(0xFF152A48),
                            child: Center(child: Icon(Icons.face_rounded,
                              size: 48, color: Color(0xFF9CC9FF))),
                          ),
                    ),
                  ),
                  Positioned(
                    right: 2, bottom: 1,
                    child: Container(
                      width: 12, height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFF79D9FC),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF10243D), width: 2),
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Эйра думает и отвечает', style: TextStyle(
                    color: Color(0xFFDCEBFF), fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    for (var i = 0; i < 3; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Transform.translate(
                          offset: Offset(0, reduced ? 0 :
                            -4 * math.max(0, math.sin(phase - i * .75))),
                          child: const CircleAvatar(radius: 3.5,
                            backgroundColor: Color(0xFF9CC9FF)),
                        ),
                      ),
                  ]),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
