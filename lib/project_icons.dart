import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Show the real approved launcher artwork, not generic Material symbols.
/// All Hub and Kopilka ship offline assets; the remaining three load their
/// respective repository launcher artwork and persist in the disk cache.
class VeyrionProjectIcon extends StatelessWidget {
  final String id;
  final double size;
  const VeyrionProjectIcon({super.key, required this.id, this.size = 68});

  @override
  Widget build(BuildContext context) {
    final local = switch (id) {
      'all-hub' => 'assets/icons/all_hub.webp',
      'kopilka' => 'assets/icons/kopilka.webp',
      _ => null,
    };
    final remote = switch (id) {
      'eclipse-arena' =>
        'https://raw.githubusercontent.com/PerchikHot/Eclipse-Arena-/main/assets/launcher.webp',
      'shadow-rp' =>
        'https://raw.githubusercontent.com/PerchikHot/Shadow-rp/main/assets/launcher.webp',
      'nova-game' =>
        'https://raw.githubusercontent.com/PerchikHot/-/main/assets/launcher.webp',
      _ => null,
    };
    Widget fallback() => const ColoredBox(
      color: Color(0xFF101B37),
      child: Center(child: Icon(Icons.apps_rounded, color: Color(0xFF56C9FF))),
    );
    final Widget artwork;
    if (local != null) {
      artwork = Image.asset(local, width: size, height: size,
          fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback());
    } else if (remote != null) {
      artwork = CachedNetworkImage(imageUrl: remote,
        width: size, height: size, fit: BoxFit.cover,
        placeholder: (_, _) => fallback(),
        errorWidget: (_, _, _) => fallback());
    } else {
      artwork = fallback();
    }
    return Container(
      width: size, height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .24),
        border: Border.all(color: const Color(0xFF4A9DDB), width: 1.2),
        boxShadow: const [BoxShadow(color: Color(0x44377DC8), blurRadius: 12)],
      ),
      child: artwork,
    );
  }
}
