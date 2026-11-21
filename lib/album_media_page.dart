import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
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
  static const _filesKey = 'media_album_imported_files_v2';
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
    _restore();
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

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_filesKey) ?? <String>[];
    final existing = <String>[];
    for (final path in saved) {
      if (await File(path).exists()) existing.add(path);
    }
    if (!mounted) return;
    setState(() {
      _link.text = prefs.getString(_key) ?? '';
      _images.addAll(existing);
      _seen.addAll(existing);
    });
    if (existing.length != saved.length) {
      await prefs.setStringList(_filesKey, existing);
    }
  }

  Future<void> _addFiles(List<File> files) async {
    if (_picking) return;
    setState(() => _picking = true);
    var added = 0;
    var skipped = 0;
    try {
      final root = Directory('${(await getApplicationSupportDirectory()).path}/album_media');
      await root.create(recursive: true);
      final prefs = await SharedPreferences.getInstance();
      for (final file in files) {
        if (!await file.exists()) { skipped++; continue; }
        final name = file.path.toLowerCase();
        if (!RegExp(r'\\.(jpg|jpeg|png|webp|gif|bmp|heic|heif)$').hasMatch(name)) {
          skipped++;
          continue;
        }
        // Use a content digest to prevent duplicate imports from different paths.
        final bytes = await file.readAsBytes();
        final digest = base64Url.encode(utf8.encode(
          '${bytes.length}:${_hashBytes(bytes)}')).replaceAll('=', '');
        final ext = name.substring(name.lastIndexOf('.'));
        final target = File('${root.path}/$digest$ext');
        if (_seen.contains(target.path)) { skipped++; continue; }
        if (!await target.exists()) await target.writeAsBytes(bytes, flush: true);
        _seen.add(target.path);
        _images.add(target.path);
        added++;
        // Persist each successful import, so a partial batch is not lost.
        await prefs.setStringList(_filesKey, _images);
        if (mounted && added % 25 == 0) {
          setState(() => _message = 'Импортировано: $added. Пропущено: $skipped.');
        }
      }
      if (mounted) setState(() => _message =
        'Реально сохранено: $added. Пропущено: $skipped. Всего: ${_images.length}.');
    } catch (error) {
      if (mounted) setState(() => _message =
        'Импорт прерван: $error. Уже добавленные файлы сохранены.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  // Lightweight deterministic fingerprint; equality is also checked by file size.
  String _hashBytes(List<int> bytes) {
    var hash = 0xcbf29ce484222325;
    for (final byte in bytes) {
      hash = ((hash ^ byte) * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16);
  }

  Future<void> _importImages() async {
    if (_picking) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image, allowMultiple: true, withData: false);
      if (result == null) return;
      await _addFiles(result.files.where((f) => f.path != null)
          .map((f) => File(f.path!)).toList());
    } catch (error) {
      if (mounted) setState(() => _message = 'Ошибка выбора файлов: $error');
    }
  }

  Future<void> _importFolder() async {
    if (_picking) return;
    try {
      final path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Выбрать папку — импортировать все фото');
      if (path == null) return;
      setState(() => _picking = true);
      final files = <File>[];
      await for (final item in Directory(path).list(recursive: true, followLinks: false)) {
        if (item is File && RegExp(r'\\.(jpg|jpeg|png|webp|gif|bmp|heic|heif)$',
            caseSensitive: false).hasMatch(item.path)) files.add(item);
      }
      if (mounted) setState(() => _picking = false);
      await _addFiles(files);
    } catch (error) {
      if (mounted) setState(() {
        _picking = false;
        _message = 'Не удалось прочитать папку: $error';
      });
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
            FilledButton.icon(onPressed: _picking ? null : _importFolder,
              icon: const Icon(Icons.select_all),
              label: const Text('Выделить всё в папке и добавить')),
          ]),
          const SizedBox(height: 6),
          const Text('Google Фото не предоставляет по публичной ссылке стабильный список прямых адресов всех снимков. Выбери файлы или всю папку: изображения копируются в хранилище All Hub и остаются после перезапуска. Это импорт, не автоматическая синхронизация.'),
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
                errorBuilder: (context, error, stackTrace) => const Center(
                  child: Icon(Icons.broken_image_outlined))),
            ),
          )),
    ]);
  }
}
