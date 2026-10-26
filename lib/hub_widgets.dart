import 'package:flutter/material.dart';

const hubBackground = Color(0xFF090E1C);
const hubPanel = Color(0xFF141C30);
const hubPurple = Color(0xFF397CFF);
const hubAccent = Color(0xFF53C9FF);

class HubBanner extends StatelessWidget {
  const HubBanner({super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(28),
      gradient: const LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color(0xFF173A82), Color(0xFF111E40), Color(0xFF0B1429)]),
      border: Border.all(color: const Color(0xFF345EA2), width: 1),
      boxShadow: const [BoxShadow(color: Color(0x330D64FF), blurRadius: 24, offset: Offset(0, 10))],
    ),
    child: Row(children: [
      const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('ТВОЯ ЭКОСИСТЕМА', style: TextStyle(fontSize: 11,
          color: hubAccent, fontWeight: FontWeight.w800, letterSpacing: 2)),
        SizedBox(height: 8),
        Text('ALL HUB', style: TextStyle(fontSize: 30,
          fontWeight: FontWeight.w900, letterSpacing: 2)),
        SizedBox(height: 6),
        Text('Игры, приложения и локальный ИИ — в одном месте.',
          style: TextStyle(fontSize: 13, color: Color(0xFFCBDCF8), height: 1.4)),
        SizedBox(height: 16),
        Row(children: [
          Icon(Icons.bolt, size: 15, color: hubAccent),
          SizedBox(width: 5),
          Text('ANDROID  /  WINDOWS', style: TextStyle(fontSize: 10,
            color: hubAccent, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        ]),
      ])),
      const SizedBox(width: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(shape: BoxShape.circle,
          color: const Color(0xFF0A142B),
          border: Border.all(color: const Color(0xFF407BDB), width: 2)),
        child: const HubAvatar(size: 76),
      ),
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
      ..strokeWidth = 3..color = const Color(0xFF53C9FF));
    final eye = Paint()..color = const Color(0xFFFF405B);
    canvas.drawOval(const Rect.fromLTWH(24, 52, 21, 8), eye);
    canvas.drawOval(const Rect.fromLTWH(55, 52, 21, 8), eye);
    canvas.restore();
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
