import 'project_launcher.dart';
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
  final String? error;
  const GithubInfo({this.version, this.downloadUrl, this.workflowStatus, this.actionsUrl, this.error});
}

class GithubApi {
  static Future<GithubInfo> inspect(String repo) async {
    final result = await HubService.inspect(repo);
    final available = result.assets.where((a) => a.platform == currentPlatform);
    return GithubInfo(
      version: result.version,
      downloadUrl: available.isEmpty ? null : available.first.url,
      workflowStatus: result.workflow,
      actionsUrl: result.actionsUrl,
      error: result.error,
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
      scaffoldBackgroundColor: hubBackground),
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
  Future<GithubInfo> getInfo(String repo) => info.putIfAbsent(repo, () => GithubApi.inspect(repo));
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
    appBar: AppBar(title: const Text('ALL HUB', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2))),
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
        Text(tab == 0 ? 'Мои проекты' : 'Состояние сборок', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        for (final project in (tab == 0 ? filtered : items)) Card(color: hubPanel, clipBehavior: Clip.antiAlias, child: Column(children: [ProjectCover(id: project.id, title: project.name, type: project.type), Padding(
          padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [const Icon(Icons.widgets_outlined, size: 30), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(project.name, style: Theme.of(context).textTheme.titleLarge),
              Text(project.type == 'Android game' ? 'Игра для Android' : project.type == 'Android app' ? 'Приложение для Android' : project.type.toLowerCase().contains('mod') ? 'Мод Minecraft' : project.type, style: Theme.of(context).textTheme.bodySmall),
            ]))]),
            const SizedBox(height: 8), Text(project.description),
            if (project.repo == null) const Padding(padding: EdgeInsets.only(top: 12), child: Text('Репозиторий пока не подключён'))
            else FutureBuilder<GithubInfo>(future: getInfo(project.repo!), builder: (context, s) {
              if (!s.hasData) return const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator());
              final i = s.data!;
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 10),
                Text('Релиз: ${i.version ?? 'не опубликован'}'),
                Text('Сборка: ${i.workflowStatus ?? 'нет данных'}'),
                if (i.error != null) Text(i.error!, style: TextStyle(color: Theme.of(context).colorScheme.tertiary)),
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
                  if (tab == 0) FilledButton.icon(onPressed: () => open(i.downloadUrl ?? i.actionsUrl ?? 'https://github.com/${project.repo}/actions'), icon: const Icon(Icons.download), label: Text(i.downloadUrl != null ? (Platform.isAndroid ? 'Скачать APK' : 'Скачать Windows') : i.actionsUrl != null ? 'Получить сборку' : 'Сборки и загрузки')),
                  if (tab == 0 && ProjectLauncher.canLaunch(project.id))
                    FilledButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Открыть'),
                      onPressed: () async {
                        try {
                          final ok = await ProjectLauncher.launch(project.id);
                          if (!ok && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Приложение не найдено или EXE не выбран')));
                          }
                        } catch (e) {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Ошибка запуска: $e')));
                        }
                      },
                    ),
                  if (tab == 0 && Platform.isWindows && i.downloadUrl != null &&
                      Uri.parse(i.downloadUrl!).path.toLowerCase().endsWith('.exe'))
                    OutlinedButton.icon(
                      icon: const Icon(Icons.install_desktop),
                      label: const Text('Установить EXE'),
                      onPressed: () async {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Скачивание EXE из GitHub Releases...')));
                        try {
                          await ProjectLauncher.installWindowsExe(project.id, i.downloadUrl!);
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('EXE установлен и привязан. Нажми «Открыть».')));
                        } catch (e) {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Не удалось установить EXE: $e')));
                        }
                      },
                    ),
                  if (tab == 0 && Platform.isWindows)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Выбрать EXE'),
                      onPressed: () async {
                        final ok = await ProjectLauncher.configureWindowsExecutable(project.id);
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(ok ? 'EXE привязан' : 'EXE не выбран')));
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
