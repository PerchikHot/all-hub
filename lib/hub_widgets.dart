import 'package:flutter/material.dart';

const hubBackground = Color(0xFF090E1C);
const hubPanel = Color(0xFF141C30);
const hubPurple = Color(0xFF8A48F8);

class HubBanner extends StatelessWidget {
  const HubBanner({super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      gradient: const LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color(0xFF352062), Color(0xFF182A55), Color(0xFF101627)]),
      border: Border.all(color: const Color(0xFF6542B0)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const HubAvatar(size: 48),
      const SizedBox(height: 14),
      const Text('ALL HUB', style: TextStyle(fontSize: 29, fontWeight: FontWeight.w900, letterSpacing: 2)),
      const SizedBox(height: 6),
      const Text('Все твои проекты в одном месте', style: TextStyle(fontSize: 15, color: Color(0xFFD2D5E6))),
      const SizedBox(height: 12),
      const Text('Игры  •  Приложения  •  Моды  •  ИИ', style: TextStyle(color: Color(0xFFB7A5E8))),
    ]),
  );
}

class HubProjectHeader extends StatelessWidget {
  final String title;
  final String type;
  const HubProjectHeader({super.key, required this.title, required this.type});
  @override
  Widget build(BuildContext context) {
    final isGame = type.toLowerCase().contains('game');
    final isMod = type.toLowerCase().contains('mod');
    final icon = isGame ? Icons.sports_esports : isMod ? Icons.extension : Icons.smartphone;
    return Container(
      height: 108, width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        gradient: LinearGradient(colors: isGame
          ? const [Color(0xFF59369B), Color(0xFF241B50)]
          : isMod ? const [Color(0xFF173F67), Color(0xFF2C205E)]
          : const [Color(0xFF2B4C82), Color(0xFF34205F)]),
      ),
      child: Stack(children: [
        Positioned(right: 22, top: 13, child: Icon(icon, size: 82, color: Colors.white.withValues(alpha: 0.18))),
        Positioned(left: 16, bottom: 14, child: Text(title.toUpperCase(),
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 21, letterSpacing: 0.7))),
      ]),
    );
  }
}

class HubAvatar extends StatelessWidget {
  final double size;
  const HubAvatar({super.key, this.size = 48});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size, height: size,
    child: CustomPaint(painter: _ShadowEmblemPainter()),
  );
}

/// Temporary original silhouette until the approved character art is supplied.
class _ShadowEmblemPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    final hood = Path()
      ..moveTo(50, 6)
      ..cubicTo(22, 7, 9, 32, 10, 74)
      ..quadraticBezierTo(50, 101, 90, 74)
      ..cubicTo(91, 32, 78, 7, 50, 6)
      ..close();
    canvas.drawPath(hood, Paint()..color = const Color(0xFF050716));
    canvas.drawPath(hood, Paint()..style = PaintingStyle.stroke
      ..strokeWidth = 3..color = const Color(0xFF9164D8));
    final eye = Paint()..color = const Color(0xFFFF405B);
    canvas.drawOval(const Rect.fromLTWH(24, 52, 21, 8), eye);
    canvas.drawOval(const Rect.fromLTWH(55, 52, 21, 8), eye);
    canvas.restore();
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
