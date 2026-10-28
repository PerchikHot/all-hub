import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class DevelopmentCenter extends StatefulWidget {
  const DevelopmentCenter({super.key});
  @override
  State<DevelopmentCenter> createState() => _DevelopmentCenterState();
}

class _DevelopmentCenterState extends State<DevelopmentCenter> {
  // A single repository may build more than one app.
  static const projects = <String, String>{
    'All Hub': 'PerchikHot/all-hub',
    'Nova Game': 'PerchikHot/-',
    'Shadow RP': 'PerchikHot/Shadow-rp',
    'Копилка': 'PerchikHot/all-hub',
    'Eclipse Arena': 'PerchikHot/Eclipse-Arena-',
  };

  List<dynamic> runsFor(String project, dynamic raw) {
    if (raw is! List) return const [];
    return raw.where((run) {
      if (run is! Map) return false;
      final name = (run['name'] ?? '').toString().toLowerCase();
      // Recording CI status does not produce an installable package.
      if (name.startsWith('record ')) return false;
      switch (project) {
        case 'All Hub':
          return name == 'build all hub';
        case 'Копилка':
          return name.contains('kopilka') && name.contains('apk');
        case 'Nova Game':
          return name == 'android apk';
        case 'Shadow RP':
          return name == 'build android apk';
        case 'Eclipse Arena':
          return name.contains('eclipse arena');
        default:
          return false;
      }
    }).toList();
  }
  late Future<Map<String, dynamic>> data = load();
  Future<Map<String, dynamic>> load() async {
    final entries = await Future.wait(projects.values.toSet().map((repo) async {
      try {
        final response = await http.get(
          Uri.parse('https://api.github.com/repos/$repo/actions/runs?per_page=20'),
          headers: const {'Accept':'application/vnd.github+json', 'User-Agent':'AllHub'},
        ).timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) return MapEntry<String, dynamic>(repo, 'HTTP ${response.statusCode}');
        return MapEntry<String, dynamic>(repo, (jsonDecode(response.body)['workflow_runs'] as List<dynamic>?) ?? []);
      } catch (e) {
        return MapEntry<String, dynamic>(repo, e.toString());
      }
    }));
    return Map<String, dynamic>.fromEntries(entries);
  }

  Future<void> open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> refresh() async {
    final pending = load();
    setState(() => data = pending);
    await pending;
  }

  @override
  Widget build(BuildContext context) => Scaffold(

    body: FutureBuilder<Map<String, dynamic>>(future: data, builder: (context, snapshot) {
      if (!snapshot.hasData) return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 16), Text('Загружаем сборки GitHub…')]));
      return RefreshIndicator(onRefresh: refresh, child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(16), children: [
        const Text('Сборки GitHub Actions', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Реальные данные GitHub. Для анализа ошибок можно скопировать запрос и передать его ИИ.'),
        const SizedBox(height: 12),
        for (final project in projects.entries) Card(child: Padding(padding: const EdgeInsets.all(14), child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(project.key, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (snapshot.data![project.value] is String)
              Text('Не удалось получить сборки: ${snapshot.data![project.value]}')
            else if (runsFor(project.key, snapshot.data![project.value]).isEmpty)
              const Text('Сборки не найдены')
            else for (final run in runsFor(project.key, snapshot.data![project.value])) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(run['conclusion'] == 'success' ? Icons.check_circle :
                  run['conclusion'] == 'failure' ? Icons.error_outline : Icons.hourglass_top,
                  color: run['conclusion'] == 'success' ? Colors.greenAccent :
                    run['conclusion'] == 'failure' ? Colors.orangeAccent : Colors.blueAccent),
                title: Text('${run['name'] ?? 'Workflow'} • #${run['run_number']}'),
                subtitle: Text('${run['status']} / ${run['conclusion'] ?? 'pending'}'),
                onTap: () => open(run['html_url'] as String),
              ),
              Wrap(spacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: () => open(run['html_url'] as String),
                  icon: const Icon(Icons.open_in_new), label: const Text('Открыть лог')),
                OutlinedButton.icon(
                  onPressed: () async {
                    final prompt = 'Помоги разобрать сборку GitHub Actions проекта ${project.key} (${project.value}). '
                      'Ссылка: ${run['html_url']}. '
                      'Проверь ошибки, предложи исправления и не изменяй код без подтверждения.';
                    await Clipboard.setData(ClipboardData(text: prompt));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Запрос для ИИ скопирован')));
                    }
                  },
                  icon: const Icon(Icons.smart_toy_outlined), label: const Text('Запрос для ИИ')),
              ]),
              const Divider(),
            ],
            TextButton(onPressed: () => open('https://github.com/${project.value}/actions'),
              child: const Text('Все сборки →')),
          ]))),
      ]));
    }),
  );
}
