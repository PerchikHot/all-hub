import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'project_launcher.dart';

/// Reactive install progress for both APK and Windows EXE/ZIP updates.
/// Indeterminate while connecting/verifying, percent while bytes are known.
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
            builder: (context, value, child) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value == null
                      ? 'Подготовка загрузки…'
                      : 'Загрузка: ${(value * 100).toStringAsFixed(0)}%'),
                  LinearProgressIndicator(value: value),
                ],
              ),
            ),
          );
        },
      );
}
