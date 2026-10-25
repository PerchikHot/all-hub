import 'dart:convert';
import 'dart:io';
import 'hub_service.dart';
import 'hub_widgets.dart';
import 'development_center.dart';
import 'project_covers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
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
  static const _headers = {'Accept': 'application/vnd.github+json', 'User-Agent': 'AllHub/0.1'};
  static Future<GithubInfo> inspect(String repo) async {
    try {
      final results = await Future.wait([
        http.get(Uri.parse('https://api.github.com/repos/$repo/releases/latest'), headers: _headers).timeout(const Duration(seconds: 12)),
        http.get(Uri.parse('https://api.github.com/repos/$repo/actions/runs?per_page=1'), headers: _headers).timeout(const Duration(seconds: 12)),
      ]);
      String? version, url, status, error;
      if (results[0].statusCode == 200) {
        final data = jsonDecode(results[0].body) as Map<String, dynamic>;
        version = data['tag_name']?.toString();
        final assets = data['assets'] as List<dynamic>? ?? [];
        for (final a in assets) {
          final file = a as Map<String, dynamic>;
          final name = (file['name'] ?? '').toString().toLowerCase();
          if ((Platform.isAndroid && name.endsWith('.apk')) || (Platform.isWindows && (name.endsWith('.exe') || name.endsWith('.msi') || name.contains('windows') && name.endsWith('.zip')))) {
            url = file['browser_download_url']?.toString();
            break;
          }
        }

      } else if (results[0].statusCode == 404) {
        error = 'No published release';
      } else {
        error = 'Release API: HTTP ${results[0].statusCode}';
      }
      if (results[1].statusCode == 200) {
        final data = jsonDecode(results[1].body) as Map<String, dynamic>;
        final runs = data['workflow_runs'] as List<dynamic>? ?? [];
        if (runs.isNotEmpty) {
          final run = runs.first as Map<String, dynamic>;
          status = "${run['status'] ?? 'unknown'} / ${run['conclusion'] ?? 'pending'}";
        }
      }
      return GithubInfo(version: version, downloadUrl: url, workflowStatus: status, error: error);
    } catch (e) {
      return GithubInfo(error: 'Network error: $e');
    }
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
  late final Future<List<Project>> projects = _loadProjects();
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
  void refresh() => setState(() { info.clear(); });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ALL HUB', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2)),
      actions: [IconButton(tooltip: 'Обновить данные GitHub', onPressed: refresh, icon: const Icon(Icons.refresh))]),
    body: FutureBuilder<List<Project>>(future: projects, builder: (context, snap) {
      if (snap.hasError) return Center(child: Text('Catalog error: ${snap.error}'));
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final items = snap.data!;
      if (tab == 1) return const DevelopmentCenter();
      if (tab == 2) return ListView(padding: const EdgeInsets.all(20), children: [
        const Text('Настройки', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const ListTile(leading: Icon(Icons.sync), title: Text('Общий каталог Android и Windows'),
          subtitle: Text('Каталог обновляется из GitHub, файлы загрузки выбираются под платформу.')),
        if (Platform.isWindows) ...[
          ValueListenableBuilder<int>(valueListenable: CoverSettings.revision,
            builder: (context, _, _) => ListTile(title: const Text('Папка изображений'),
              subtitle: Text(CoverSettings.folder ?? 'Не выбрана'))),
          FilledButton(onPressed: () async { await CoverSettings.chooseFolder(); },
            child: const Text('Выбрать папку')),
          OutlinedButton(onPressed: () async { await CoverSettings.clear(); },
            child: const Text('Сбросить папку')),
        ],
        const ListTile(title: Text('All Hub 0.4.0'),
          subtitle: Text('Общий каталог и загрузки APK / Windows')),
      ]);
      final filtered = items.where((p) => (!showOnlyAvailable || p.repo != null) && (category == 'All' || p.type.toLowerCase().contains(category.toLowerCase())) && (search.isEmpty || ('${p.name} ${p.description}').toLowerCase().contains(search.toLowerCase()))).toList();
      return ListView(padding: const EdgeInsets.all(16), children: [
        if (tab == 0) ...[const HubBanner(), const SizedBox(height: 20)],
        if (tab == 0) ...[
          TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Поиск проектов', border: OutlineInputBorder()), onChanged: (v) => setState(() => search = v)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [for (final c in ['All', 'game', 'app', 'mod']) ChoiceChip(label: Text(c == 'All' ? 'All' : c == 'game' ? 'Игры' : c == 'app' ? 'Приложения' : 'Моды'), selected: category == c, onSelected: (_) => setState(() => category = c))]),
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
                  if (tab == 0 && i.downloadUrl != null) FilledButton.icon(onPressed: () => open(i.downloadUrl!), icon: const Icon(Icons.download), label: Text(Platform.isAndroid ? 'Скачать APK' : 'Скачать Windows')),
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
      NavigationDestination(icon: Icon(Icons.settings), label: 'Настройки'),
    ]),
  );
}
