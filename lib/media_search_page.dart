import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Searches the open web through external search engines.
/// No images or videos are stored, scraped or proxied by All Hub.
class MediaSearchPage extends StatefulWidget {
  const MediaSearchPage({super.key});

  @override
  State<MediaSearchPage> createState() => _MediaSearchPageState();
}

class _MediaSearchPageState extends State<MediaSearchPage> {
  final controller = TextEditingController();
  String topic = 'futanari';
  String media = 'images';
  String engine = 'bing';
  bool adultConfirmed = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Uri searchUri() {
    final custom = controller.text.trim();
    final query = custom.isEmpty ? topic : '$topic $custom';
    if (engine == 'google') {
      return Uri.https('www.google.com', '/search', {
        'q': query,
        'tbm': media == 'images' ? 'isch' : 'vid',
        'safe': 'off',
      });
    }
    if (engine == 'duckduckgo') {
      return Uri.https('duckduckgo.com', '/', {
        'q': query,
        'ia': media == 'images' ? 'images' : 'videos',
        'kp': '-2',
      });
    }
    return Uri.https('www.bing.com', media == 'images' ? '/images/search' : '/videos/search', {
      'q': query,
      'adlt': 'off',
    });
  }

  Future<void> openSearch() async {
    if (!adultConfirmed) return;
    final uri = searchUri();
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть поиск в браузере')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Браузер недоступен')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text('Поиск фото и видео', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      const Text('Поиск по интернету через Google, Bing или DuckDuckGo. Результаты открываются во внешнем браузере. Некоторые результаты могут содержать материалы 18+.'),
      const SizedBox(height: 16),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'futanari', label: Text('Футанари')),
          ButtonSegment(value: 'transgender', label: Text('Транс')),
        ],
        selected: {topic},
        onSelectionChanged: (v) => setState(() => topic = v.first),
      ),
      const SizedBox(height: 12),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'images', icon: Icon(Icons.image_outlined), label: Text('Фото')),
          ButtonSegment(value: 'videos', icon: Icon(Icons.video_library_outlined), label: Text('Видео')),
        ],
        selected: {media},
        onSelectionChanged: (v) => setState(() => media = v.first),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: controller,
        decoration: const InputDecoration(
          labelText: 'Дополнительный запрос',
          hintText: 'Например: anime, cosplay, art',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.search),
        ),
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => openSearch(),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: engine,
        decoration: const InputDecoration(labelText: 'Поисковик', border: OutlineInputBorder()),
        items: const [
          DropdownMenuItem(value: 'bing', child: Text('Bing')),
          DropdownMenuItem(value: 'google', child: Text('Google')),
          DropdownMenuItem(value: 'duckduckgo', child: Text('DuckDuckGo')),
        ],
        onChanged: (v) { if (v != null) setState(() => engine = v); },
      ),
      const SizedBox(height: 12),
      CheckboxListTile(
        value: adultConfirmed,
        onChanged: (v) => setState(() => adultConfirmed = v ?? false),
        title: const Text('Мне есть 18 лет'),
        subtitle: const Text('Понимаю, что внешний поиск может показывать откровенные материалы'),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: adultConfirmed ? openSearch : null,
        icon: const Icon(Icons.open_in_browser),
        label: Text('Найти ${media == 'images' ? 'фото' : 'видео'} в интернете'),
      ),
      const SizedBox(height: 12),
      const Text('All Hub не хранит результаты поиска и не обходит ограничения поисковых систем. Фильтрация и доступность зависят от выбранного сервиса.'),
    ],
  );
}
