import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'project_launcher.dart';
import 'hub_update_panel.dart';
import 'hub_wait_indicator.dart';

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
              if (safe != null) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: HubUpdatePanel(
                    progress: safe,
                    title: 'Загрузка обновления',
                  ),
                );
              }
              return const Semantics(
                liveRegion: true,
                label: 'Подготовка обновления',
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Подготовка загрузки…'),
                      SizedBox(height: 8),
                      HubWaitIndicator(size: 66),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
}
