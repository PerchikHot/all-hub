import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'external_artwork.dart';

/// Screenshots for user-added PUBLIC repositories, stored only on this device.
class ExternalScreenshots {
  static const maxScreenshots = 6;
  static const maxBytes = 10 * 1024 * 1024;
  static const _prefix = 'external_screenshots_';
  static bool _validId(String id) =>
      RegExp(r'^external-[a-z0-9_.-]{3,160}$').hasMatch(id);
  static bool acceptsHeader(List<int> header, String extension, int size) =>
      size >= 12 && size <= maxBytes &&
      ExternalArtwork.validImageHeader(header, extension);

  static Future<Directory> _directory() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}${Platform.pathSeparator}external_screenshots');
  }

  static Future<List<String>> load(String projectId) async {
    if (!_validId(projectId)) return [];
    final prefs = await SharedPreferences.getInstance();
    final directory = await _directory();
    final prefix = '${directory.path}${Platform.pathSeparator}';
    final paths = prefs.getStringList('$_prefix$projectId') ?? <String>[];
    final result = <String>[];
    for (final path in paths.take(maxScreenshots)) {
      if (path.startsWith(prefix) && await File(path).exists()) result.add(path);
    }
    return result;
  }

  /// A cancelled or invalid picker selection leaves the existing list intact.
  static Future<int> choose(String projectId) async {
    if (!_validId(projectId)) throw ArgumentError('Invalid project ID');
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.image, allowMultiple: true, withData: false);
    if (selection == null || selection.files.isEmpty) return 0;
    final existing = await load(projectId);
    if (selection.files.length + existing.length > maxScreenshots) {
      throw const FormatException('Максимум 6 скриншотов на приложение');
    }
    final sources = <(File, String)>[];
    for (final chosen in selection.files) {
      if (chosen.path == null) {
        throw const FormatException('Файл недоступен для чтения');
      }
      final source = File(chosen.path!);
      final size = await source.length();
      final extension = (chosen.extension ?? '').toLowerCase();
      final header = await source.openRead(0, 16).fold<List<int>>(
          <int>[], (bytes, chunk) => bytes..addAll(chunk));
      if (!acceptsHeader(header, extension, size)) {
        throw const FormatException('Нужны PNG, JPG, GIF или WebP до 10 МБ');
      }
      sources.add((source, extension));
    }
    final directory = await _directory();
    await directory.create(recursive: true);
    final added = <String>[];
    try {
      for (var index = 0; index < sources.length; index++) {
        final (source, extension) = sources[index];
        final target = File('${directory.path}${Platform.pathSeparator}$projectId-${DateTime.now().microsecondsSinceEpoch}-$index.$extension');
        await source.copy(target.path);
        added.add(target.path);
      }
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setStringList('$_prefix$projectId', [...existing, ...added])) {
        throw StateError('Не удалось сохранить скриншоты');
      }
      return added.length;
    } catch (_) {
      for (final path in added) {
        try { await File(path).delete(); } on FileSystemException { }
      }
      rethrow;
    }
  }

  static Future<void> removeAt(String projectId, int index) async {
    if (!_validId(projectId)) return;
    final current = await load(projectId);
    if (index < 0 || index >= current.length) return;
    final removed = current.removeAt(index);
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setStringList('$_prefix$projectId', current)) {
      throw StateError('Не удалось изменить скриншоты');
    }
    try { await File(removed).delete(); } on FileSystemException { }
  }

  static Future<void> removeAll(String projectId) async {
    if (!_validId(projectId)) return;
    final current = await load(projectId);
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove('$_prefix$projectId')) {
      throw StateError('Не удалось удалить список скриншотов');
    }
    for (final path in current) {
      try { await File(path).delete(); } on FileSystemException { }
    }
  }
}

class ExternalScreenshotGallery extends StatefulWidget {
  final String projectId;
  const ExternalScreenshotGallery({super.key, required this.projectId});
  @override
  State<ExternalScreenshotGallery> createState() => _ExternalScreenshotGalleryState();
}

class _ExternalScreenshotGalleryState extends State<ExternalScreenshotGallery> {
  late Future<List<String>> _screenshots;
  @override
  void initState() { super.initState(); _reload(); }
  void _reload() { _screenshots = ExternalScreenshots.load(widget.projectId); }

  Future<void> _change(Future<void> Function() operation) async {
    try {
      await operation();
      if (mounted) setState(_reload);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Скриншоты: $error')));
    }
  }

  void _preview(String path) {
    showDialog<void>(context: context, builder: (dialogContext) => Dialog(
      child: SizedBox(width: 800,
        height: MediaQuery.sizeOf(dialogContext).height * 0.72,
        child: InteractiveViewer(minScale: 0.5, maxScale: 5,
          child: Image.file(File(path), fit: BoxFit.contain,
            errorBuilder: (_, __, ___) =>
                const Center(child: Text('Изображение недоступно')))),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<String>>(
    future: _screenshots,
    builder: (context, snapshot) {
      final paths = snapshot.data ?? <String>[];
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('Скриншоты (только на устройстве)',
            style: TextStyle(fontWeight: FontWeight.w600))),
          Text('${paths.length}/${ExternalScreenshots.maxScreenshots}'),
          IconButton(tooltip: 'Добавить скриншоты',
            icon: const Icon(Icons.add_photo_alternate_outlined),
            onPressed: paths.length >= ExternalScreenshots.maxScreenshots
              ? null : () => _change(() async {
                  await ExternalScreenshots.choose(widget.projectId);
                })),
        ]),
        if (snapshot.hasError)
          const Text('Не удалось прочитать локальные скриншоты'),
        if (paths.isEmpty)
          const Text('Можно добавить до 6 PNG, JPG, GIF или WebP.',
            style: TextStyle(fontSize: 12, color: Colors.white70)),
        if (paths.isNotEmpty)
          SizedBox(height: 126, child: ListView.separated(
            scrollDirection: Axis.horizontal, itemCount: paths.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) => SizedBox(width: 140, child: Stack(
              children: [
                Positioned.fill(child: InkWell(
                  onTap: () => _preview(paths[index]),
                  child: Image.file(File(paths[index]), fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const Center(child: Icon(Icons.broken_image_outlined))))),
                Positioned(right: 0, top: 0, child: IconButton(
                  tooltip: 'Удалить скриншот',
                  style: IconButton.styleFrom(backgroundColor: Colors.black87),
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => _change(
                    () => ExternalScreenshots.removeAt(widget.projectId, index)))),
              ],
            )),
          )),
      ]);
    },
  );
}
