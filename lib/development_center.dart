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
  static const repositories = <String>[
    'PerchikHot/all-hub',
    'PerchikHot/Eclipse-Arena-',
    'PerchikHot/Shadow-rp',
  ];
  late Future<Map<String, dynamic>> data = load();
  Future<Map<String, dynamic>> load() async {
    final result = <String, dynamic>{};
    for (final repo in repositories) {
      try {
        final response = await http.get(
          Uri.parse('https://api.github.com/repos/$repo/actions/runs?per_page=3'),
          headers: const {'Accept':'application/vnd.github+json', 'User-Agent':'AllHub'},
        ).timeout(const Duration(seconds: 12));
        if (response.statusCode != 200) {
          result[repo] = 'HTTP ${response.statusCode}';
        } else {
          result[repo] = (jsonDecode(response.body)['workflow_runs'] as List<dynamic>?) ?? [];
        }
      } catch (e) { result[repo] = e.toString(); }
    }
    return result;
  }

  Future<void> open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void refresh() => setState(() { data = load(); });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Центр разработки'), actions: [
      IconButton(onPressed: refresh, icon: const Icon(Icons.refresh), tooltip: 'Обновить')
    ]),
    body: FutureBuilder<Map<String, dynamic>>(future: data, builder: (context, snapshot) {
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      return ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Сборки GitHub Actions', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Реальные данные GitHub. Для анализа ошибок можно скопировать запрос и передать его ИИ.'),
        const SizedBox(height: 12),
        for (final repo in repositories) Card(child: Padding(padding: const EdgeInsets.all(14), child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(repo.split('/').last, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (snapshot.data![repo] is String)
              Text('Не удалось получить сборки: ${snapshot.data![repo]}')
            else if ((snapshot.data![repo] as List).isEmpty)
              const Text('Сборки не найдены')
            else for (final run in (snapshot.data![repo] as List)) ...[
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
                    final prompt = 'Помоги разобрать сборку GitHub Actions проекта $repo. '
                      'Ссылка: ${run['html_url']}. '
                      'Проверь ошибки, предложи исправления и не изменяй код без подтверждения.';
                    await Clipboard.setData(ClipboardData(text: prompt));
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Запрос для ИИ скопирован')));
                  },
                  icon: const Icon(Icons.smart_toy_outlined), label: const Text('Запрос для ИИ')),
              ]),
              const Divider(),
            ],
            TextButton(onPressed: () => open('https://github.com/$repo/actions'),
              child: const Text('Все сборки →')),
          ]))),
      ]);
    }),
  );
}
