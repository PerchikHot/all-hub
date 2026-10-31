import 'package:flutter/material.dart';

/// Consistent, offline project identity for All Hub cards.
/// Distinct from optional user-supplied cover artwork.
class VeyrionProjectIcon extends StatelessWidget {
  final String id;
  final double size;
  const VeyrionProjectIcon({super.key, required this.id, this.size = 68});

  @override
  Widget build(BuildContext context) {
    final spec = switch (id) {
      'all-hub' => (Icons.hub_rounded, const Color(0xFF56C9FF), 'AH'),
      'eclipse-arena' => (Icons.sports_martial_arts_rounded, const Color(0xFFAA7DFF), 'EA'),
      'shadow-rp' => (Icons.forum_rounded, const Color(0xFF55B5FF), 'RP'),
      'kopilka' => (Icons.savings_rounded, const Color(0xFF66E3C0), '₽'),
      'nova-game' => (Icons.auto_awesome_rounded, const Color(0xFFFF83D1), 'N'),
      _ => (Icons.apps_rounded, const Color(0xFF90A9E8), 'APP'),
    };
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF203B76), Color(0xFF0A1228)]),
        border: Border.all(color: spec.$2.withValues(alpha: .85), width: 1.5),
        boxShadow: [BoxShadow(color: spec.$2.withValues(alpha: .24),
          blurRadius: 18, spreadRadius: 1)],
      ),
      child: Stack(alignment: Alignment.center, children: [
        Icon(spec.$1, size: size * .50, color: spec.$2),
        Positioned(right: size * .08, bottom: size * .07,
          child: Text(spec.$3, style: TextStyle(
            fontSize: size * .12, fontWeight: FontWeight.w900,
            color: Colors.white.withValues(alpha: .82)))),
      ]),
    );
  }
}
