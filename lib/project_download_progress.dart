import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'project_launcher.dart';

/// A single, platform-independent update surface. Installation is separate
/// from downloading: the progress bar must never imply an APK was installed.
class ProjectDownloadProgress extends StatelessWidget {
  final String projectId;
  final ValueListenable<String?> activeProject;
  final ValueListenable<double?> progress;

  ProjectDownloadProgress({
    super.key,
    required this.projectId,
    ValueListenable<String?>? activeProject,
    ValueListenable<double?>? progress,
  })  : activeProject = activeProject ?? ProjectLauncher.activeDownloadProject,
        progress = progress ?? ProjectLauncher.downloadProgress;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
        valueListenable: activeProject,
        builder: (context, active, child) {
          if (active != projectId) return const SizedBox.shrink();
          return ValueListenableBuilder<double?>(
            valueListenable: progress,
            builder: (context, value, child) {
              final safe = value != null && value.isFinite
                  ? value.clamp(0.0, 1.0).toDouble() : null;
              return Semantics(
                liveRegion: true,
                label: safe == null
                    ? 'Подготовка обновления'
                    : 'Загрузка обновления ${(safe * 100).round()} процентов',
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF182F59), Color(0xFF111B34)],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFF3E69AC)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.downloading_rounded,
                            color: Color(0xFF7DCCFF), size: 22),
                        const SizedBox(width: 10),
                        Expanded(child: Text(value == null || safe == null
                            ? 'Подготовка загрузки…'
                            : 'Загрузка: ${(safe * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFEAF4FF),
                          ),
                        )),
                      ]),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: safe,
                        minHeight: 7,
                        borderRadius: BorderRadius.circular(12),
                        backgroundColor: const Color(0xFF304262),
                        color: const Color(0xFF65B9FF),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'После загрузки может потребоваться подтверждение установки.',
                        style: TextStyle(
                          color: Color(0xFFAAC1DE), fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
}
