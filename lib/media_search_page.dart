import 'media_gallery_page.dart';
import 'dart:io';
import 'media_browser_page.dart';
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
  bool galleryMode = true;
  String character = '';
  static const characters = <String, String>{
    '': 'Без персонажа',
    'Alpha The Eminence in Shadow': 'Альфа — Восхождение в тени',
    'Erza Scarlet Fairy Tail': 'Эрза Скарлет — Fairy Tail',
    'Rias Gremory High School DxD': 'Риас Гремори — DxD',
    'Yamato One Piece': 'Ямато — One Piece',
    'Boa Hancock One Piece': 'Боа Хэнкок — One Piece',
    'Nami One Piece': 'Нами — One Piece',
    'Aqua Konosuba': 'Аква — Konosuba',
    'Darkness Konosuba': 'Даркнесс — Konosuba',
    'Esdeath Akame ga Kill': 'Эсдес — Akame ga Kill',
    'Tsunade Naruto': 'Цунаде — Naruto',
  };

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Uri searchUri() {
    final custom = controller.text.trim();
    final query = [topic, if (character.isNotEmpty) character, if (custom.isNotEmpty) custom, if (media == 'gifs') 'animated gif'].join(' ');
    if (engine == 'google') {
      return Uri.https('www.google.com', '/search', {
        'q': query,
        'tbm': media == 'videos' ? 'vid' : 'isch',
        if (media == 'gifs') 'tbs': 'itp:animated',
        'safe': 'off',
      });
    }
    if (engine == 'duckduckgo') {
      return Uri.https('duckduckgo.com', '/', {
        'q': query,
        'ia': media == 'videos' ? 'videos' : 'images',
        'kp': '-2',
      });
    }
    return Uri.https('www.bing.com', media == 'videos' ? '/videos/search' : '/images/search', {
      'q': query,
      'adlt': 'off',
    });
  }

  Future<void> openSearch() async {
    if (!adultConfirmed) return;
    final uri = searchUri();
    try {
      if (Platform.isAndroid) {
        if (!mounted) return;
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => MediaBrowserPage(url: uri),
        ));
        return;
      }
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
  Widget build(BuildContext context) => Column(children: [
    Padding(padding: const EdgeInsets.all(8), child: SegmentedButton<bool>(
      segments: const [
        ButtonSegment(value: true, icon: Icon(Icons.grid_view), label: Text('Лента')),
        ButtonSegment(value: false, icon: Icon(Icons.travel_explore), label: Text('Веб-поиск')),
      ],
      selected: {galleryMode},
      onSelectionChanged: (v) => setState(() => galleryMode = v.first),
    )),
    Expanded(child: galleryMode ? (adultConfirmed ? const MediaGalleryPage() : Center(child: Padding(
      padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.visibility_outlined, size: 44),
        const SizedBox(height: 16),
        const Text('Лента может содержать изображения 18+. Подтверди возраст, чтобы продолжить.', textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FilledButton(onPressed: () => setState(() => adultConfirmed = true), child: const Text('Мне есть 18 лет')),
      ]),
    ))) : ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text('Поиск фото, GIF и видео', style: Theme.of(context).textTheme.headlineSmall),
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
          ButtonSegment(value: 'gifs', icon: Icon(Icons.gif_box_outlined), label: Text('GIF')),
          ButtonSegment(value: 'videos', icon: Icon(Icons.video_library_outlined), label: Text('Видео')),
        ],
        selected: {media},
        onSelectionChanged: (v) => setState(() => media = v.first),
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        initialValue: character,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Персонаж из списка', border: OutlineInputBorder()),
        items: characters.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))).toList(),
        onChanged: (v) { if (v != null) setState(() => character = v); },
      ),
      const SizedBox(height: 12),
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
        label: Text('Найти ${media == 'images' ? 'фото' : media == 'gifs' ? 'GIF' : 'видео'} в интернете'),
      ),
      const SizedBox(height: 12),
      const Text('На Android поиск открывается внутри All Hub. Прямые ссылки на фото, GIF и видео можно сохранить кнопкой загрузки. Файлы хранятся в папке приложения AllHubMedia. Сайты могут ограничивать скачивание.'),
      const SizedBox(height: 8),
      const Text('All Hub не хранит результаты поиска и не обходит ограничения поисковых систем. Фильтрация и доступность зависят от выбранного сервиса.'),
    ],
  )),
  ]);
}
