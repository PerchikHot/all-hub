import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'hub_liquid_progress.dart';

/// Reference-inspired update panel. Only downloading is measured here;
/// unpacking and installation must be reported by their actual controllers.
class HubUpdatePanel extends StatelessWidget {
  const HubUpdatePanel({
    super.key,
    required this.progress,
    this.title = 'Обновление приложения',
    this.installedVersion,
    this.availableVersion,
    this.downloadedBytes,
    this.totalBytes,
    this.bytesPerSecond,
    this.onPause,
    this.onCancel,
    this.paused = false,
  });

  final double progress;
  final String title;
  final String? installedVersion;
  final String? availableVersion;
  final int? downloadedBytes;
  final int? totalBytes;
  final double? bytesPerSecond;
  final VoidCallback? onPause;
  final VoidCallback? onCancel;
  final bool paused;

  static String formatBytes(num bytes) {
    if (!bytes.isFinite || bytes < 0) return '—';
    if (bytes < 1024) return '${bytes.round()} Б';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    if (bytes < 1073741824) return '${(bytes / 1048576).toStringAsFixed(1)} МБ';
    return '${(bytes / 1073741824).toStringAsFixed(2)} ГБ';
  }

  String get remaining {
    final speed = bytesPerSecond;
    final total = totalBytes;
    final done = downloadedBytes;
    if (speed == null || !speed.isFinite || speed <= 0 ||
        total == null || done == null || total < done) return '—';
    final seconds = ((total - done) / speed).ceil();
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$secs' : '$minutes:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final p = progress.isFinite ? progress.clamp(0.0, 1.0).toDouble() : 0.0;
    const accent = Color(0xFF67BCFF);
    const muted = Color(0xFFB3C9E7);
    final versionText = installedVersion != null && availableVersion != null
        ? '$installedVersion   →   $availableVersion'
        : null;
    return Semantics(
      label: 'Панель обновления приложения',
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF152E55), Color(0xFF080F25), Color(0xFF172447)],
          ),
          border: Border.all(color: accent.withValues(alpha: .8), width: 1.5),
          boxShadow: [BoxShadow(color: accent.withValues(alpha: .18),
              blurRadius: 18, spreadRadius: 1)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: Colors.white,
              fontSize: 19, fontWeight: FontWeight.bold)),
          if (versionText != null) ...[
            const SizedBox(height: 5),
            Text(versionText, style: const TextStyle(color: muted, fontSize: 13)),
          ],
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: HubLiquidProgress(value: p, height: 35)),
            const SizedBox(width: 12),
            SizedBox(width: 92, height: 92,
              child: CustomPaint(
                painter: _UpdateRingPainter(p),
                child: Center(child: Text('${(p * 100).round()}%',
                  style: const TextStyle(color: Colors.white, fontSize: 24,
                    fontWeight: FontWeight.bold))),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 18, runSpacing: 8, children: [
            _metric(Icons.download_rounded,
              downloadedBytes == null ? 'Объём: —' :
                '${formatBytes(downloadedBytes!)} / ${totalBytes == null ? "—" : formatBytes(totalBytes!)}'),
            _metric(Icons.speed_rounded,
              bytesPerSecond == null ? 'Скорость: —' :
                '${formatBytes(bytesPerSecond!)} / с'),
            _metric(Icons.schedule_rounded, 'Осталось: $remaining'),
          ]),
          const SizedBox(height: 16),
          const Divider(color: Color(0xFF33517F)),
          const SizedBox(height: 8),
          const Wrap(spacing: 14, runSpacing: 12, children: [
            _Stage(icon: Icons.verified_outlined, text: 'Проверка', done: true),
            _Stage(icon: Icons.download_rounded, text: 'Загрузка', active: true),
            _Stage(icon: Icons.inventory_2_outlined, text: 'Распаковка'),
            _Stage(icon: Icons.settings_outlined, text: 'Установка'),
            _Stage(icon: Icons.flag_outlined, text: 'Завершение'),
          ]),
          if (onPause != null || onCancel != null) ...[
            const SizedBox(height: 18),
            Row(children: [
              if (onPause != null) Expanded(child: OutlinedButton.icon(
                onPressed: onPause,
                icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                label: Text(paused ? 'Продолжить' : 'Пауза'),
              )),
              if (onPause != null && onCancel != null)
                const SizedBox(width: 10),
              if (onCancel != null) Expanded(child: OutlinedButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.close_rounded),
                label: const Text('Отмена'),
              )),
            ]),
          ],
        ]),
      ),
    );
  }

  static Widget _metric(IconData icon, String value) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: const Color(0xFF78C6FF)),
      const SizedBox(width: 6),
      Text(value, style: const TextStyle(
        color: Color(0xFFD4E8FF), fontSize: 12)),
    ],
  );
}

class _Stage extends StatelessWidget {
  const _Stage({required this.icon, required this.text,
    this.done = false, this.active = false});
  final IconData icon;
  final String text;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = done ? const Color(0xFF66E5DA) :
        active ? const Color(0xFF6DC6FF) : const Color(0xFF7287AB);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 19, color: color),
      const SizedBox(width: 5),
      Text(text, style: TextStyle(color: color, fontSize: 12,
        fontWeight: active ? FontWeight.bold : FontWeight.normal)),
    ]);
  }
}

class _UpdateRingPainter extends CustomPainter {
  const _UpdateRingPainter(this.value);
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(center, radius, Paint()
      ..color = const Color(0xFF25416B)
      ..strokeWidth = 8..style = PaintingStyle.stroke);
    if (value > 0) {
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * value, false, Paint()
        ..color = const Color(0xFF68C8FF)
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 8..style = PaintingStyle.stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _UpdateRingPainter old) => old.value != value;
}
