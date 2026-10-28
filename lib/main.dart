import 'project_launcher.dart';
import 'version_status.dart';
import 'media_browser_page.dart';
import 'kopilka_page.dart';
import 'dart:io';
import 'hub_service.dart';
import 'hub_widgets.dart';
import 'development_center.dart';
import 'project_covers.dart';
import 'ai_models_page.dart';
import 'media_search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const AllHub());

class Project {
  final String id, name, type, description;
  final String? repo;
  const Project(this.id, this.name, this.type, this.description, this.repo);
  factory Project.fromJson(Map<String, dynamic> x) => Project(
    x['id'] as String, x['name'] as String, x['type'] as String,
    x['description'] as String, x['repo'] as String?);
}

class GithubInfo {
  final String? version, downloadUrl, workflowStatus, actionsUrl;
  final String? error, releaseNotes;
  const GithubInfo({this.version, this.downloadUrl, this.workflowStatus, this.actionsUrl, this.error, this.releaseNotes});
}

class GithubApi {
  static Future<GithubInfo> inspect(String repo, {String? projectId}) async {
    final result = await HubService.inspect(repo, projectId: projectId);
    final available = result.assets.where((a) {
      if (a.platform != currentPlatform) return false;
      final name = a.name.toLowerCase();
      if (projectId == 'kopilka') return name.startsWith('kopilka-');
      if (projectId == 'all-hub') return name.startsWith('allhub-') || name.startsWith('all-hub-');
      return true;
    }).toList();
    return GithubInfo(
      version: available.isEmpty ? null : available.first.version,
      downloadUrl: available.isEmpty ? null : available.first.url,
      workflowStatus: result.workflow,
      actionsUrl: result.actionsUrl,
      error: result.error,
      releaseNotes: available.isEmpty ? null : available.first.releaseNotes,
    );
  }
}

class AllHub extends StatelessWidget {
  const AllHub({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'All Hub', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(seedColor: hubPurple, brightness: Brightness.dark),
      scaffoldBackgroundColor: hubBackground,
      cardTheme: CardThemeData(color: hubPanel, elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: Color(0xFF263956)))),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: const Color(0xFF15223A),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none)),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Color(0xFF101B30), indicatorColor: Color(0xFF234A88)),
      appBarTheme: const AppBarTheme(backgroundColor: hubBackground,
        centerTitle: false, surfaceTintColor: Colors.transparent)),
    home: const HomePage());
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;
  String category = 'All';
  String search = '';
  bool showOnlyAvailable = false;
  late Future<List<Project>> projects = _loadProjects();
  @override
  void initState() {
    super.initState();
    CoverSettings.load();
    migrateAllHubMedia();
  }
  final Map<String, Future<GithubInfo>> info = {};
  Future<List<Project>> _loadProjects() async {
    final data = await rootBundle.loadString('assets/projects.json');
    final live = await HubService.catalog(data);
    return live.map((p) => Project(p.id, p.name, p.type, p.description, p.repo)).toList();
  }
  Future<void> open(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open link')));
    }
  }
  Future<GithubInfo> getInfo(String repo, String id) => info.putIfAbsent(id, () => GithubApi.inspect(repo, projectId: id));
  Future<void> refresh() async {
    setState(() { info.clear(); projects = _loadProjects(); });
    await projects;
    CoverSettings.revision.value++;
  }

  Widget _settings() => ListView(padding: const EdgeInsets.all(20), children: [
        const Text('Настройки', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const ListTile(leading: Icon(Icons.sync), title: Text('Общий каталог Android и Windows'),
          subtitle: Text('Каталог обновляется из GitHub, файлы загрузки выбираются под платформу.')),
        if (Platform.isWindows || Platform.isAndroid) ...[
          ValueListenableBuilder<int>(valueListenable: CoverSettings.revision,
            builder: (context, revision, child) => ListTile(title: Text(Platform.isAndroid ? 'Импортированные изображения' : 'Папка изображений'),
              subtitle: Text(CoverSettings.folder ?? 'Не выбрана'))),
          FilledButton(onPressed: () async { await CoverSettings.chooseFolder(); },
            child: Text(Platform.isAndroid ? 'Добавить изображения' : 'Выбрать / переназначить папку')),
          OutlinedButton(onPressed: () async { await CoverSettings.clear(); },
            child: Text(Platform.isAndroid ? 'Не использовать импортированные фото' : 'Сбросить папку')),
        ],
        ValueListenableBuilder<int>(valueListenable: CoverSettings.revision,
          builder: (context, revision, child) => SwitchListTile(
            title: const Text('Обложки 18+ (футанари)'),
            subtitle: const Text('Поиск по тегам Danbooru для взрослых персонажей. Может содержать откровенные изображения. Локальные фото имеют приоритет.'),
            value: CoverSettings.adultCovers,
            onChanged: (enabled) => CoverSettings.setAdultCovers(enabled))),
        ValueListenableBuilder<int>(valueListenable: CoverSettings.statusRevision,
          builder: (context, revision, child) => ExpansionTile(
            title: const Text('Диагностика интернет-обложек'),
            subtitle: Text(CoverSettings.errors.isEmpty
              ? 'Ошибок поиска пока нет'
              : 'Проблемы: ${CoverSettings.errors.length}'),
            children: CoverSettings.errors.entries.map((entry) =>
              ListTile(title: Text(entry.key), subtitle: Text(entry.value))).toList(),
          )),
        const ListTile(title: Text('All Hub 0.6.0'),
          subtitle: Text('Общий каталог и загрузки APK / Windows')),
        ]);
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Row(children: [HubAvatar(size: 32), SizedBox(width: 10), Text('ALL HUB', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2))]), actions: [IconButton(tooltip: 'Обновить каталог', onPressed: refresh, icon: const Icon(Icons.refresh_rounded))]),
    body: tab == 1 ? const DevelopmentCenter() : tab == 2 ? const AiModelsPage() : tab == 3 ? const MediaSearchPage() : tab == 4 ? _settings() :
      FutureBuilder<List<Project>>(future: projects, builder: (context, snap) {
      if (snap.hasError) return Center(child: Text('Ошибка каталога: ${snap.error}'));
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final items = snap.data!;

      final filtered = items.where((p) => (!showOnlyAvailable || p.repo != null) && (category == 'All' || p.type.toLowerCase().contains(category.toLowerCase())) && (search.isEmpty || ('${p.name} ${p.description}').toLowerCase().contains(search.toLowerCase()))).toList();
      return RefreshIndicator(onRefresh: refresh, child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(16), children: [
        if (tab == 0) ...[const HubBanner(), const SizedBox(height: 20)],
        if (tab == 0) ...[
          TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Поиск проектов', border: OutlineInputBorder()), onChanged: (v) => setState(() => search = v)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [for (final c in ['All', 'game', 'app', 'mod']) ChoiceChip(label: Text(c == 'All' ? 'Все' : c == 'game' ? 'Игры' : c == 'app' ? 'Приложения' : 'Моды'), selected: category == c, onSelected: (_) => setState(() => category = c))]),
          const SizedBox(height: 16),
        ],
        Row(children: [Expanded(child: Text(tab == 0 ? 'Мои проекты' : 'Состояние сборок', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800))), Text('${(tab == 0 ? filtered : items).length} ПРОЕКТА', style: const TextStyle(color: hubAccent, fontSize: 11, fontWeight: FontWeight.w700))]),
        const SizedBox(height: 16),
        for (final project in (tab == 0 ? filtered : items)) Card(margin: const EdgeInsets.only(bottom: 14), clipBehavior: Clip.antiAlias, child: Column(children: [ProjectCover(id: project.id, title: project.name, type: project.type), Padding(
          padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [const Icon(Icons.widgets_outlined, size: 30), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(project.name, style: Theme.of(context).textTheme.titleLarge),
              Text(project.type == 'Android game' ? 'Игра для Android' : project.type == 'Android app' ? 'Приложение для Android' : project.type.toLowerCase().contains('mod') ? 'Мод Minecraft' : project.type, style: Theme.of(context).textTheme.bodySmall),
            ]))]),
            const SizedBox(height: 8), Text(project.description),
            if (project.id == 'kopilka') Padding(
              padding: const EdgeInsets.only(top: 12),
              child: FilledButton.icon(
                icon: const Icon(Icons.account_balance_wallet_outlined),
                label: const Text('Открыть Копилку'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const KopilkaPage())),
              ),
            ),
            if (project.repo == null) const Padding(padding: EdgeInsets.only(top: 12), child: Text('Репозиторий пока не подключён'))
            else FutureBuilder<GithubInfo>(future: getInfo(project.repo!, project.id), builder: (context, s) {
              if (!s.hasData) return const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator());
              final i = s.data!;
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 10),
                Row(children: [
                  const Icon(Icons.system_update_alt_rounded, size: 17, color: hubAccent),
                  const SizedBox(width: 7),
                  Expanded(child: Text(i.downloadUrl != null
                    ? 'Опубликован установочный файл'
                    : 'Файл для этой платформы не опубликован',
                    style: const TextStyle(fontWeight: FontWeight.w600))),
                ]),
                if (project.id == ProjectLauncher.activeDownloadProject.value)
                  ValueListenableBuilder<double?>(
                    valueListenable: ProjectLauncher.downloadProgress,
                    builder: (context, progress, child) => progress == null
                      ? const SizedBox.shrink()
                      : Padding(padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Загрузка: ${(progress * 100).toStringAsFixed(0)}%'),
                            LinearProgressIndicator(value: progress),
                          ]))),
                FutureBuilder<String?>(
                  future: ProjectLauncher.installedVersion(project.id),
                  builder: (context, installed) => Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Установлено: ${installed.data ?? 'версия неизвестна'}',
                        style: Theme.of(context).textTheme.bodySmall),
                      Text('Опубликовано: ${i.version ?? 'нет релиза'}',
                        style: Theme.of(context).textTheme.bodySmall),
                      Text(describeUpdateStatus(installed.data, i.version),
                        style: TextStyle(color: comparePublishedVersions(
                          installed.data ?? '', i.version ?? '') == -1
                          ? Colors.greenAccent : hubAccent)),
                    ]),
                  ),
                ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Что нового и диагностика', style: TextStyle(fontSize: 13)),
                  children: [
                    if (i.releaseNotes != null && i.releaseNotes!.isNotEmpty)
                      Align(alignment: Alignment.centerLeft,
                        child: Text('Описание релиза: ${i.releaseNotes}')),
                    Align(alignment: Alignment.centerLeft,
                      child: Text('Состояние сборки: ${i.workflowStatus ?? 'нет данных'}')),
                    if (i.error != null)
                      Align(alignment: Alignment.centerLeft, child: Text(i.error!,
                        style: TextStyle(color: Theme.of(context).colorScheme.tertiary))),
                  ],
                ),
                if (tab == 0 && ProjectLauncher.canLaunch(project.id))
                  FutureBuilder<bool>(
                    future: ProjectLauncher.isAvailable(project.id),
                    builder: (context, status) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        Icon(status.data == true ? Icons.check_circle_outline : Icons.info_outline,
                          size: 16, color: status.data == true ? Colors.greenAccent : Colors.orangeAccent),
                        const SizedBox(width: 6),
                        Expanded(child: Text(status.data == true
                          ? 'Готово к запуску'
                          : Platform.isAndroid ? 'APK не установлен или не обнаружен' : 'EXE ещё не привязан',
                          style: Theme.of(context).textTheme.bodySmall)),
                      ]),
                    ),
                  ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  OutlinedButton.icon(onPressed: () => open('https://github.com/${project.repo}'), icon: const Icon(Icons.code), label: const Text('Репозиторий')),
                  if (tab == 0 && i.downloadUrl == null)
                    FilledButton.icon(onPressed: () => open(i.actionsUrl ?? 'https://github.com/${project.repo}/actions'), icon: const Icon(Icons.download), label: const Text('Сборка пока недоступна')),
                  if (tab == 0 && ProjectLauncher.canLaunch(project.id))
                    FilledButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Открыть'),
                      onPressed: () async {
                        try {
                          final ok = await ProjectLauncher.launch(project.id);
                          if (!ok && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Приложение не найдено или EXE не выбран')));
                          }
                        } catch (e) {
                          if (context.mounted) {
                             ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка запуска: $e')));
                           }
                        }
                      },
                    ),
                  if (tab == 0 && Platform.isAndroid && i.downloadUrl != null &&
                      Uri.parse(i.downloadUrl!).path.toLowerCase().endsWith('.apk'))
                    OutlinedButton.icon(
                      icon: const Icon(Icons.install_mobile),
                      label: const Text('Скачать APK и установить'),
                      onPressed: () async {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Скачивание APK...')));
                        try {
                          await ProjectLauncher.installAndroidApk(i.downloadUrl!, projectId: project.id);
                        } catch (e) {
                          if (context.mounted) {
                             ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка установки APK: $e')));
                           }
                        }
                      },
                    ),
                  if (tab == 0 && Platform.isWindows && i.downloadUrl != null &&
                      Uri.parse(i.downloadUrl!).path.toLowerCase().endsWith('.exe'))
                    OutlinedButton.icon(
                      icon: const Icon(Icons.install_desktop),
                      label: const Text('Скачать и установить'),
                      onPressed: () async {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Скачивание EXE из GitHub Releases...')));
                        try {
                          await ProjectLauncher.installWindowsExe(project.id, i.downloadUrl!);
                          await ProjectLauncher.recordInstalledVersion(project.id, i.version);
                          if (context.mounted) {
                             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('EXE установлен и привязан. Нажми «Открыть».')));
                           }
                        } catch (e) {
                          if (context.mounted) {
                             ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось установить EXE: $e')));
                           }
                        }
                      },
                    ),
                  if (tab == 0 && Platform.isWindows && i.downloadUrl != null &&
                      Uri.parse(i.downloadUrl!).path.toLowerCase().endsWith('.zip'))
                    OutlinedButton.icon(
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: const Text('Скачать и установить'),
                      onPressed: () async {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Скачиваем игру со всеми файлами...')));
                        try {
                          await ProjectLauncher.installWindowsZip(project.id, i.downloadUrl!);
                          await ProjectLauncher.recordInstalledVersion(project.id, i.version);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Игра установлена. Нажми «Открыть».')));
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Ошибка установки: $e')));
                          }
                        }
                      },
                    ),
                  if (tab == 0 && Platform.isWindows)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Выбрать EXE'),
                      onPressed: () async {
                        final ok = await ProjectLauncher.configureWindowsExecutable(project.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(ok ? 'EXE привязан' : 'EXE не выбран')));
                        }
                      },
                    ),
                  if (tab == 1) OutlinedButton(onPressed: () => open('https://github.com/${project.repo}/actions'), child: const Text('Actions')),
                ]),
              ]);
            }),
          ]))])),
      ]));
    }),
    bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (i) => setState(() => tab = i), destinations: const [
      NavigationDestination(icon: Icon(Icons.grid_view), label: 'Проекты'),
      NavigationDestination(icon: Icon(Icons.build_circle_outlined), label: 'Разработка'),
      NavigationDestination(icon: Icon(Icons.smart_toy_outlined), label: 'ИИ'),
      NavigationDestination(icon: Icon(Icons.travel_explore), label: 'Медиа'),
      NavigationDestination(icon: Icon(Icons.settings), label: 'Настройки'),
    ]),
  );
}
