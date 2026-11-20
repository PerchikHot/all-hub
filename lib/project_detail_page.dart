import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'hub_liquid_progress.dart';
import 'hub_wait_indicator.dart';
import 'main.dart';
import 'project_covers.dart';
import 'project_launcher.dart';
import 'version_status.dart';

/// Project details remain inside All Hub. Only the repository link opens
/// the external browser when explicitly requested.
class ProjectDetailPage extends StatefulWidget {
  const ProjectDetailPage({super.key, required this.project});
  final Project project;
  @override
  State<ProjectDetailPage> createState() => _ProjectDetailPageState();
}

class _ProjectDetailPageState extends State<ProjectDetailPage> {
  late Future<GithubInfo> info = _load();
  late Future<String?> installed = ProjectLauncher.installedVersion(widget.project.id);
  bool busy = false;

  Future<GithubInfo> _load() async {
    final repo = widget.project.repo;
    if (repo == null) return const GithubInfo();
    return GithubApi.inspect(repo, projectId: widget.project.id);
  }

  Future<void> refresh() async {
    setState(() {
      info = _load();
      installed = ProjectLauncher.installedVersion(widget.project.id);
    });
    await info;
  }

  Future<void> install(GithubInfo release) async {
    if (release.downloadUrl == null || busy) return;
    setState(() => busy = true);
    try {
      if (Platform.isAndroid) {
        await ProjectLauncher.runInstallExclusive(widget.project.id,
          () => ProjectLauncher.installAndroidApk(
            release.downloadUrl!,
            projectId: widget.project.id,
            externalRepo: widget.project.id.startsWith('external-')
              ? widget.project.repo : null,
            sha256Digest: release.sha256Digest));
      } else if (Platform.isWindows) {
        if (widget.project.id == 'all-hub') {
          await ProjectLauncher.updateAllHubWindows(
            release.downloadUrl!,
            version: release.version,
            sha256Digest: release.sha256Digest);
        } else {
          await ProjectLauncher.updateAndLaunchWindows(
            widget.project.id, release.downloadUrl!,
            version: release.version,
            externalRepo: widget.project.id.startsWith('external-')
              ? widget.project.repo : null,
            sha256Digest: release.sha256Digest);
        }
      }
      if (mounted) await refresh();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось установить: $error')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.project;
    final repo = p.repo;
    final author = repo == null ? 'Не указан' : repo.split('/').first;
    return Scaffold(
      appBar: AppBar(
        title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [IconButton(
          tooltip: 'Обновить сведения',
          onPressed: refresh,
          icon: const Icon(Icons.refresh_rounded))]),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: AspectRatio(aspectRatio: 1.7,
              child: ProjectCover(id: p.id, title: p.name, type: p.type))),
          const SizedBox(height: 20),
          Text(p.name, style: Theme.of(context).textTheme.headlineSmall
            ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(p.type, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 16),
          Text('О проекте', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(p.description),
          const SizedBox(height: 18),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_outline_rounded),
            title: const Text('Автор / владелец репозитория'),
            subtitle: Text(author)),
          if (repo != null) ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.code_rounded),
            title: const Text('Репозиторий'),
            subtitle: Text(repo),
            trailing: const Icon(Icons.open_in_new_rounded),
            onTap: () => launchUrl(Uri.parse('https://github.com/$repo'),
              mode: LaunchMode.externalApplication)),
          const SizedBox(height: 14),
          if (repo == null) const Text('Для этого проекта не подключён репозиторий.'),
          if (repo != null) FutureBuilder<GithubInfo>(
            future: info,
            builder: (context, snapshot) {
              if (snapshot.hasError) return Text('Не удалось проверить релиз: ${snapshot.error}');
              if (!snapshot.hasData) return const Center(child: HubWaitIndicator());
              final release = snapshot.data!;
              return FutureBuilder<String?>(
                future: installed,
                builder: (context, version) {
                  if (version.hasError) {
                    return Text('Не удалось определить установленную версию: ${version.error}');
                  }
                  if (version.connectionState != ConnectionState.done) {
                    return const Center(child: HubWaitIndicator());
                  }
                  final local = version.data;
                  final available = release.version;
                  final comparison = local == null || available == null
                    ? null : comparePublishedVersions(local, available);
                  final label = projectInstallActionLabel(local, available);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Установлено: ${local ?? "не обнаружено"}'),
                      Text('Доступно: ${available ?? "не опубликовано"}'),
                      Text(describeUpdateStatus(local, available)),
                      if (release.error != null) Text(release.error!),
                      const SizedBox(height: 12),
                      if (busy) ValueListenableBuilder<double?>(
                        valueListenable: ProjectLauncher.downloadProgress,
                        builder: (context, progress, _) =>
                          HubLiquidProgress(value: progress)),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: busy || release.downloadUrl == null
                          || comparison == 1 ? null : () => install(release),
                        icon: const Icon(Icons.download_rounded),
                        label: Text(busy ? 'Загружаем…' : label)),
                    ],
                  );
                },
              );
            },
          ),
        ]),
      ),
    );
  }
}
