import 'dart:convert';
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
          if (name.endsWith('.apk') || name.endsWith('.exe') || name.endsWith('.msi') || name.endsWith('.zip')) {
            url = file['browser_download_url']?.toString();
            break;
          }
        }
        url ??= data['html_url']?.toString();
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
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4D9DFF), brightness: Brightness.dark),
      scaffoldBackgroundColor: const Color(0xFF0A1221)),
    home: const HomePage());
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;
  late final Future<List<Project>> projects = _loadProjects();
  final Map<String, Future<GithubInfo>> info = {};
  Future<List<Project>> _loadProjects() async {
    final data = await rootBundle.loadString('assets/projects.json');
    return (jsonDecode(data) as List).map((x) => Project.fromJson(x as Map<String, dynamic>)).toList();
  }
  Future<void> open(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open link')));
    }
  }
  Future<GithubInfo> getInfo(String repo) => info.putIfAbsent(repo, () => GithubApi.inspect(repo));
  void refresh() => setState(info.clear);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ALL HUB', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2)),
      actions: [IconButton(tooltip: 'Refresh GitHub data', onPressed: refresh, icon: const Icon(Icons.refresh))]),
    body: FutureBuilder<List<Project>>(future: projects, builder: (context, snap) {
      if (snap.hasError) return Center(child: Text('Catalog error: ${snap.error}'));
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final items = snap.data!;
      if (tab == 2) return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('All Hub v0.1.0\n\nAndroid + Windows source project.\nGitHub release checks and CI status.\n\nInstallation, local model management and self-updates are planned for later versions.', textAlign: TextAlign.center)));
      return ListView(padding: const EdgeInsets.all(16), children: [
        Text(tab == 0 ? 'Your projects' : 'Build status', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        for (final project in items) Card(clipBehavior: Clip.antiAlias, child: Padding(
          padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [const Icon(Icons.widgets_outlined, size: 30), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(project.name, style: Theme.of(context).textTheme.titleLarge),
              Text(project.type, style: Theme.of(context).textTheme.bodySmall),
            ]))]),
            const SizedBox(height: 8), Text(project.description),
            if (project.repo == null) const Padding(padding: EdgeInsets.only(top: 12), child: Text('Repository not configured yet'))
            else FutureBuilder<GithubInfo>(future: getInfo(project.repo!), builder: (context, s) {
              if (!s.hasData) return const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator());
              final i = s.data!;
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 10),
                Text('Release: ${i.version ?? 'not published'}'),
                Text('CI: ${i.workflowStatus ?? 'not available'}'),
                if (i.error != null) Text(i.error!, style: TextStyle(color: Theme.of(context).colorScheme.tertiary)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  OutlinedButton.icon(onPressed: () => open('https://github.com/${project.repo}'), icon: const Icon(Icons.code), label: const Text('Repository')),
                  if (tab == 0 && i.downloadUrl != null) FilledButton.icon(onPressed: () => open(i.downloadUrl!), icon: const Icon(Icons.download), label: const Text('Get release')),
                  if (tab == 1) OutlinedButton(onPressed: () => open('https://github.com/${project.repo}/actions'), child: const Text('Actions')),
                ]),
              ]);
            }),
          ]))),
      ]);
    }),
    bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (i) => setState(() => tab = i), destinations: const [
      NavigationDestination(icon: Icon(Icons.grid_view), label: 'Projects'),
      NavigationDestination(icon: Icon(Icons.build_circle_outlined), label: 'Development'),
      NavigationDestination(icon: Icon(Icons.settings), label: 'About'),
    ]),
  );
}
