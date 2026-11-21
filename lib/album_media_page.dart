import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Google Photos share links are album pages, not a supported image-list API.
/// Importing user-selected images gives a real, stable in-app feed without
/// scraping private URLs or silently claiming to sync the entire album.
class AlbumMediaPage extends StatefulWidget {
  const AlbumMediaPage({super.key});
  @override
  State<AlbumMediaPage> createState() => _AlbumMediaPageState();
}

class _AlbumMediaPageState extends State<AlbumMediaPage>
    with AutomaticKeepAliveClientMixin {
  static const _key = 'media_google_album_url_v1';
  final _link = TextEditingController();
  final _scroll = ScrollController();
  final _images = <String>[];
  final _seen = <String>{};
  bool _picking = false;
  String? _message;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) setState(() => _link.text = prefs.getString(_key) ?? '');
    });
  }

  Uri? get _albumUri {
    final uri = Uri.tryParse(_link.text.trim());
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty ||
        !{'photos.app.goo.gl', 'photos.google.com'}.contains(uri.host.toLowerCase())) {
      return null;
    }
    return uri;
  }

  Future<void> _saveLink() async {
    if (_albumUri == null) {
      setState(() => _message = 'Нужна ссылка на альбом Google Фото (https).');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, _link.text.trim());
    if (mounted) setState(() => _message = 'Ссылка сохранена. Для ленты импортируй фотографии из альбома.');
  }

  Future<void> _openAlbum() async {
    final uri = _albumUri;
    if (uri == null) {
      setState(() => _message = 'Сначала укажи корректную ссылку Google Фото.');
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      setState(() => _message = 'Не удалось открыть альбом.');
    }
  }

  Future<void> _importImages() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image, allowMultiple: true, withData: false);
      if (result == null) return;
      var added = 0;
      for (final file in result.files) {
        final path = file.path;
        if (path == null || !_seen.add(path)) continue;
        if (!await File(path).exists()) {
          _seen.remove(path);
          continue;
        }
        _images.add(path);
        added++;
      }
      if (mounted) setState(() => _message =
          'Добавлено: $added. Всего в ленте: ${_images.length}. Порядок сохранён.');
    } catch (error) {
      if (mounted) setState(() => _message = 'Не удалось импортировать изображения: $error');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  void dispose() {
    _link.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _link,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Ссылка на альбом Google Фото',
              hintText: 'https://photos.app.goo.gl/...',
              prefixIcon: Icon(Icons.photo_album_outlined)),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(onPressed: _saveLink,
              icon: const Icon(Icons.save_outlined), label: const Text('Сохранить ссылку')),
            OutlinedButton.icon(onPressed: _openAlbum,
              icon: const Icon(Icons.open_in_new), label: const Text('Открыть альбом')),
            FilledButton.icon(onPressed: _picking ? null : _importImages,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(_picking ? 'Импорт...' : 'Добавить фото в ленту')),
          ]),
          const SizedBox(height: 6),
          const Text('Google Фото не предоставляет по публичной ссылке стабильный список прямых адресов всех снимков. Выбери фотографии через системный проводник: они появятся ниже без самопроизвольной перестановки. Это импорт, не автоматическая синхронизация.'),
          if (_message != null) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_message!, style: Theme.of(context).textTheme.bodySmall)),
        ]),
      ),
      Expanded(child: _images.isEmpty
        ? const Center(child: Text('Лента пуста. Добавь изображения из альбома.'))
        : GridView.builder(
            controller: _scroll,
            key: const PageStorageKey('google-album-local-feed'),
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8,
              childAspectRatio: .8),
            itemCount: _images.length,
            itemBuilder: (context, index) => ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(File(_images[index]),
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const Center(
                  child: Icon(Icons.broken_image_outlined))),
            ),
          )),
    ]);
  }
}
