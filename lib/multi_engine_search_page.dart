import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'media_browser_page.dart';

/// One query, several independent web search result pages.
/// Search providers do not offer a shared unrestricted image API.
class MultiEngineSearchPage extends StatefulWidget {
  const MultiEngineSearchPage({super.key, required this.query, required this.media});
  final String query;
  final String media;

  @override
  State<MultiEngineSearchPage> createState() => _MultiEngineSearchPageState();
}

class _MultiEngineSearchPageState extends State<MultiEngineSearchPage> {
  int selected = 0;

  late final List<(String, Uri)> sources = [
    ('Яндекс', Uri.https('yandex.ru', widget.media == 'videos' ? '/video/search' : '/images/search', {
      'text': widget.query,
      if (widget.media == 'gifs') 'type': 'gif',
    })),
    ('Google', Uri.https('www.google.com', '/search', {
      'q': widget.query,
      'tbm': widget.media == 'videos' ? 'vid' : 'isch',
      if (widget.media == 'gifs') 'tbs': 'itp:animated',
    })),
    ('Bing', Uri.https('www.bing.com', widget.media == 'videos' ? '/videos/search' : '/images/search', {
      'q': widget.query,
    })),
    ('DuckDuckGo', Uri.https('duckduckgo.com', '/', {
      'q': widget.query,
      'ia': widget.media == 'videos' ? 'videos' : 'images',
    })),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Поиск • Все источники')),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Text(
        'Один запрос для всех поисковиков. Переключай источники без повторного ввода. Их результаты не объединяются в одну ленту.',
      )),
      SizedBox(height: 50, child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < sources.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(sources[i].$1),
                selected: selected == i,
                onSelected: (_) => setState(() => selected = i),
              ),
            ),
        ],
      )),
      Expanded(child: KeyedSubtree(
        key: ValueKey(selected),
        child: Platform.isAndroid
            ? MediaBrowserPage(url: sources[selected].$2)
            : Center(child: FilledButton(
                onPressed: () => launchUrl(sources[selected].$2, mode: LaunchMode.externalApplication),
                child: Text('Открыть ${sources[selected].$1}'),
              )),
      )),
    ]),
  );
}
