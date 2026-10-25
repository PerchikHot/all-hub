import 'dart:io';
import 'hub_service.dart';
import 'hub_widgets.dart';
import 'development_center.dart';
import 'project_covers.dart';
import 'ai_models_page.dart';
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
  final String? version, downloadUrl, workflowStatus;
  final String? error;
  const GithubInfo({this.version, this.downloadUrl, this.workflowStatus, this.error});
}

class GithubApi {
  static Future<GithubInfo> inspect(String repo) async {
    final result = await HubService.inspect(repo);
    final available = result.assets.where((a) => a.platform == currentPlatform);
    return GithubInfo(
      version: result.version,
      downloadUrl: available.isEmpty ? null : available.first.url,
      workflowStatus: result.workflow,
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
  void refresh() => setState(() { info.clear(); projects = _loadProjects(); });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ALL HUB', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2)),
      actions: [IconButton(tooltip: 'Обновить данные GitHub', onPressed: refresh, icon: const Icon(Icons.refresh))]),
    body: FutureBuilder<List<Project>>(future: projects, builder: (context, snap) {
      if (snap.hasError) return Center(child: Text('Ошибка каталога: ${snap.error}'));
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final items = snap.data!;
      if (tab == 1) return const DevelopmentCenter();
      if (tab == 2) return const AiModelsPage();
      if (tab == 3) {
        return ListView(padding: const EdgeInsets.all(20), children: [
        const Text('Настройки', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const ListTile(leading: Icon(Icons.sync), title: Text('Общий каталог Android и Windows'),
          subtitle: Text('Каталог обновляется из GitHub, файлы загрузки выбираются под платформу.')),
        if (Platform.isWindows || Platform.isAndroid) ...[
          ValueListenableBuilder<int>(valueListenable: CoverSettings.revision,
            builder: (context, revision, child) => ListTile(title: const Text('Папка изображений'),
              subtitle: Text(CoverSettings.folder ?? 'Не выбрана'))),
          FilledButton(onPressed: () async { await CoverSettings.chooseFolder(); },
            child: const Text('Выбрать / переназначить папку')),
          OutlinedButton(onPressed: () async { await CoverSettings.clear(); },
            child: const Text('Сбросить папку')),
        ],
        ValueListenableBuilder<int>(valueListenable: CoverSettings.revision,
          builder: (context, revision, child) => SwitchListTile(
            title: const Text('Обложки 18+ (футанари)'),
            subtitle: const Text('Поиск по тегам Danbooru для взрослых персонажей. Может содержать откровенные изображения. Локальные фото имеют приоритет.'),
            value: CoverSettings.adultCovers,
            onChanged: (enabled) => CoverSettings.setAdultCovers(enabled))),
        const ListTile(title: Text('All Hub 0.4.0'),
          subtitle: Text('Общий каталог и загрузки APK / Windows')),
        ]);
      }
      final filtered = items.where((p) => (!showOnlyAvailable || p.repo != null) && (category == 'All' || p.type.toLowerCase().contains(category.toLowerCase())) && (search.isEmpty || ('${p.name} ${p.description}').toLowerCase().contains(search.toLowerCase()))).toList();
      return ListView(padding: const EdgeInsets.all(16), children: [
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
              Text(project.type == 'Android game' ? 'Игра для Android' : project.type == 'Android app' ? 'Приложение для Android' : 'Мод Minecraft', style: Theme.of(context).textTheme.bodySmall),
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
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  OutlinedButton.icon(onPressed: () => open('https://github.com/${project.repo}'), icon: const Icon(Icons.code), label: const Text('Репозиторий')),
                  if (tab == 0) FilledButton.icon(onPressed: () => open(i.downloadUrl ?? 'https://github.com/${project.repo}/actions'), icon: const Icon(Icons.download), label: Text(i.downloadUrl != null ? (Platform.isAndroid ? 'Скачать APK' : 'Скачать Windows') : 'Сборки и загрузки')),
                  if (tab == 1) OutlinedButton(onPressed: () => open('https://github.com/${project.repo}/actions'), child: const Text('Actions')),
                ]),
              ]);
            }),
          ]))])),
      ]);
    }),
    bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (i) => setState(() => tab = i), destinations: const [
      NavigationDestination(icon: Icon(Icons.grid_view), label: 'Проекты'),
      NavigationDestination(icon: Icon(Icons.build_circle_outlined), label: 'Разработка'),
      NavigationDestination(icon: Icon(Icons.smart_toy_outlined), label: 'ИИ'),
      NavigationDestination(icon: Icon(Icons.settings), label: 'Настройки'),
    ]),
  );
}
