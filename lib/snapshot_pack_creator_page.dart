import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// Builds Snapshot photo packages using the pack.ini/Data layout.
class SnapshotPackCreatorPage extends StatefulWidget {
  const SnapshotPackCreatorPage({super.key});
  @override
  State<SnapshotPackCreatorPage> createState() => _SnapshotPackCreatorPageState();
}

class _SnapshotPackCreatorPageState extends State<SnapshotPackCreatorPage> {
  final title = TextEditingController(text: 'My Snapshot Pack');
  final packId = TextEditingController(text: 'mySnapshotPack');
  final category = TextEditingController(text: 'Custom Photos');
  final photos = <Uint8List>[];
  Uint8List? templateBytes;
  String? templateName;
  List<String> templatePhotoNames = [];
  String? templateRoot;
  String? templateError;
  bool busy = false;

  @override
  void dispose() {
    title.dispose();
    packId.dispose();
    category.dispose();
    super.dispose();
  }

  Uint8List? convertToPng(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      return Uint8List.fromList(img.encodePng(decoded));
    } catch (_) {
      return null;
    }
  }

  Future<void> addPhotos() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp', 'tif', 'tiff'],
      allowMultiple: true,
      withData: true,
    );
    if (picked == null || !mounted) return;
    final added = <Uint8List>[];
    try {
    for (final file in picked.files) {
      final bytes = file.bytes ?? (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null) throw FormatException('Не удалось прочитать ${file.name}');
      final png = convertToPng(bytes);
      if (png == null) throw FormatException('Неподдерживаемое изображение: ${file.name}');
      added.add(png);
    }
    if (mounted) setState(() => photos.addAll(added));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка изображения: $e')));
    }
  }


  Future<void> addPhotosFromZip() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['zip'], withData: true);
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.single;
      final bytes = file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null) throw const FormatException('ZIP недоступен');
      final archive = ZipDecoder().decodeBytes(bytes);
      final imported = <Uint8List>[];
      for (final entry in archive.files) {
        if (!entry.isFile) continue;
        final lower = entry.name.toLowerCase();
        if (!RegExp(r'\.(png|jpg|jpeg|webp|gif|bmp|tif|tiff|dat)$').hasMatch(lower)) continue;
        final data = Uint8List.fromList(entry.content as List<int>);
        final png = convertToPng(data);
        if (png != null) imported.add(png);
      }
      if (imported.isEmpty) {
        throw const FormatException('В ZIP нет поддерживаемых изображений');
      }
      if (mounted) {
        setState(() => photos.addAll(imported));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Добавлено из ZIP: ${imported.length}')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка импорта ZIP: $e')));
    }
  }

  Future<void> importTemplate() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['zip'], withData: true);
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.single;
      final bytes = file.bytes ?? (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null) throw const FormatException('Не удалось прочитать ZIP');
      final archive = ZipDecoder().decodeBytes(bytes);
      final iniFiles = archive.files.where((f) => f.isFile && f.name.endsWith('/pack.ini')).toList();
      if (iniFiles.length != 1) throw const FormatException('В ZIP должен быть один pack.ini внутри папки пака');
      final ini = iniFiles.single;
      final root = ini.name.substring(0, ini.name.length - 'pack.ini'.length);
      final data = utf8.decode(ini.content as List<int>, allowMalformed: true);
      final match = RegExp(r'(?m)^names=(.*)$').firstMatch(data);
      if (match == null) throw const FormatException('В pack.ini нет списка names');
      final names = match.group(1)!.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if (names.isEmpty) throw const FormatException('В паке нет фотографий');
      for (final name in names) {
        if (!archive.files.any((f) => f.name == '${root}Data/$name.dat')) {
          throw FormatException('Отсутствует Data/$name.dat');
        }
      }
      if (!mounted) return;
      setState(() {
        templateBytes = bytes;
        templateName = file.name;
        templateRoot = root;
        templatePhotoNames = names;
        templateError = null;
        editedEvents.clear();
      });
    } catch (e) {
      if (mounted) setState(() => templateError = '$e');
    }
  }

  final Map<String, String> editedEvents = {};

  Future<void> editEventJson() async {
    if (templateBytes == null || templateRoot == null) return;
    try {
      final archive = ZipDecoder().decodeBytes(templateBytes!);
      final files = archive.files.where((f) => f.isFile &&
        f.name.startsWith(templateRoot!) && f.name.endsWith('.json')).toList();
      if (files.isEmpty) throw const FormatException('Нет JSON-событий');
      final chosen = await showDialog<String>(context: context, builder: (ctx) =>
        SimpleDialog(title: const Text('Выбери JSON-событие'),
          children: files.map((f) => SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, f.name),
            child: Text(f.name.split('/').last))).toList()));
      if (chosen == null || !mounted) return;
      final file = files.firstWhere((f) => f.name == chosen);
      final controller = TextEditingController(text: editedEvents[chosen] ??
        utf8.decode(file.content as List<int>, allowMalformed: true));
      final result = await showDialog<String>(context: context, builder: (ctx) =>
        AlertDialog(title: Text(chosen.split('/').last),
          content: SizedBox(width: 600, child: TextField(
            controller: controller, minLines: 10, maxLines: 18)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена')),
            FilledButton(onPressed: () {
              try {
                jsonDecode(controller.text);
                Navigator.pop(ctx, controller.text);
              } catch (_) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                  content: Text('Ошибка синтаксиса JSON')));
              }
            }, child: const Text('Сохранить')),
          ]));
      controller.dispose();
      if (result != null && mounted) setState(() => editedEvents[chosen] = result);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка редактора: $e')));
    }
  }

  // On Windows/Linux/macOS the save dialog only selects a destination; it
  // does not write the supplied bytes. Write and verify the ZIP explicitly.
  Future<String?> saveZip(String filename, Uint8List bytes, String dialogTitle) async {
    final selected = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: filename,
      type: FileType.custom,
      allowedExtensions: ['zip'],
      bytes: Platform.isAndroid || Platform.isIOS ? bytes : null,
    );
    if (selected == null) return null;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final destination = File(selected);
      await destination.writeAsBytes(bytes, flush: true);
      if (await destination.length() != bytes.length) {
        throw FileSystemException('ZIP записан не полностью', selected);
      }
    }
    return selected;
  }

  Future<void> exportTemplate() async {
    if (templateBytes == null || templateRoot == null) {
      throw const FormatException('Выбери ZIP-шаблон');
    }
    // A template has a fixed set of image IDs referenced by its events.
    // Never silently discard extra imported images during export.
    if (photos.length > templatePhotoNames.length) {
      throw FormatException('В шаблоне ${templatePhotoNames.length} слотов для фото, '
          'но добавлено ${photos.length}. Удали лишние изображения или '
          'выбери другой шаблон.');
    }
    final source = ZipDecoder().decodeBytes(templateBytes!);
    final root = templateRoot!;
    final replacement = <String, Uint8List>{};
    for (var i = 0; i < photos.length && i < templatePhotoNames.length; i++) {
      replacement['${root}Data/${templatePhotoNames[i]}.dat'] = photos[i];
    }
    final result = Archive();
    for (final file in source.files) {
      if (!file.isFile) continue;
      final bytes = editedEvents.containsKey(file.name)
          ? Uint8List.fromList(utf8.encode(editedEvents[file.name]!))
          : replacement[file.name] ?? Uint8List.fromList(file.content as List<int>);
      result.addFile(ArchiveFile(file.name, bytes.length, bytes));
    }
    final encoded = Uint8List.fromList(ZipEncoder().encode(result));
    final saved = await saveZip('Snapshot_Custom_Template.zip', encoded,
        'Экспорт ZIP по шаблону');
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(saved == null ? 'Сохранение отменено' : 'ZIP сохранён: $saved')));
  }

  String safeId(String input) {
    final value = input.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '');
    return value.isEmpty ? 'customSnapshotPack' : value;
  }

  Future<void> exportPack() async {
    if (photos.isEmpty && (templateBytes == null || editedEvents.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала добавь изображения')));
      return;
    }
    setState(() => busy = true);
    try {
      if (templateBytes != null) {
        await exportTemplate();
        return;
      }
      final id = safeId(packId.text);
      final root = 'Snapshot_Pack_$id';
      final names = List.generate(photos.length, (i) => 'custom_photo_${(i + 1).toString().padLeft(3, '0')}');
      final ini = StringBuffer()
        ..writeln('[Mod]')
        ..writeln('plugID=snapshot')
        ..writeln('id=$id')
        ..writeln('title="${title.text.replaceAll('"', '')}"')
        ..writeln('type=photos')
        ..writeln()
        ..writeln('[Defaults]')
        ..writeln('position=upskirt')
        ..writeln('type=mizuki')
        ..writeln('color=none')
        ..writeln()
        ..writeln('[Special Category]')
        ..writeln('specialCategory="${category.text.replaceAll('"', '')}"')
        ..writeln('specialCategoryColor=#8bb584')
        ..writeln()
        ..writeln('[Photos]')
        ..writeln('names=${names.join(',')}');
      final archive = Archive();
      void add(String path, List<int> bytes) {
        archive.addFile(ArchiveFile(path, bytes.length, bytes));
      }
      for (var i = 0; i < photos.length; i++) {
        // Original Snapshot packs store image bytes under .dat extensions.
        add('$root/Data/${names[i]}.dat', photos[i]);
      }
      add('$root/pack.ini', Uint8List.fromList(utf8.encode(ini.toString())));
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
      final saved = await saveZip('Snapshot_Pack_$id.zip', bytes,
          'Сохранить Snapshot ZIP');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(saved == null ? 'Сохранение отменено' : 'ZIP сохранён: $saved')));
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка экспорта: $error')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Snapshot Pack Creator')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Создай собственный фотопак для Snapshot',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      OutlinedButton.icon(onPressed: busy ? null : importTemplate,
        icon: const Icon(Icons.folder_zip_outlined), label: const Text('Открыть ZIP-шаблон')),
      if (templateName != null) Text('Шаблон: $templateName (${templatePhotoNames.length} фотографий)'),
      if (templateName != null) OutlinedButton.icon(onPressed: busy ? null : editEventJson,
        icon: const Icon(Icons.edit_note), label: const Text('Редактировать JSON-события')),
      if (editedEvents.isNotEmpty) Text('Изменено событий: ${editedEvents.length}'),
      if (templateError != null) Text(templateError!, style: const TextStyle(color: Colors.redAccent)),
      if (templateName != null) TextButton(onPressed: busy ? null : () => setState(() {
        templateBytes = null; templateName = null; templateRoot = null; templatePhotoNames = []; editedEvents.clear();
      }), child: const Text('Создать новый пак')),
      TextField(controller: title, decoration: const InputDecoration(labelText: 'Название пака')),
      const SizedBox(height: 12),
      TextField(controller: packId, decoration: const InputDecoration(labelText: 'ID пака (латиница)')),
      const SizedBox(height: 12),
      TextField(controller: category, decoration: const InputDecoration(labelText: 'Категория')),
      const SizedBox(height: 16),
      OutlinedButton.icon(onPressed: busy ? null : addPhotos,
        icon: const Icon(Icons.add_photo_alternate), label: const Text('Добавить изображение')),
      OutlinedButton.icon(onPressed: busy ? null : addPhotosFromZip,
        icon: const Icon(Icons.archive_outlined), label: const Text('Импорт PNG/JPG/WebP/GIF из ZIP')),
      const SizedBox(height: 8),
      Text('Изображений: ${photos.length}'),
      const SizedBox(height: 12),
      GridView.builder(
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
        itemCount: photos.length,
        itemBuilder: (context, i) => Stack(fit: StackFit.expand, children: [
          ClipRRect(borderRadius: BorderRadius.circular(8),
            child: Image.memory(photos[i], fit: BoxFit.cover)),
          Positioned(right: 0, top: 0, child: IconButton.filledTonal(
            onPressed: busy ? null : () => setState(() => photos.removeAt(i)),
            icon: const Icon(Icons.close, size: 18))),
        ]),
      ),
      const SizedBox(height: 20),
      FilledButton.icon(onPressed: busy ? null : exportPack,
        icon: const Icon(Icons.archive_outlined),
        label: Text(busy ? 'Сборка...' : templateBytes != null ? 'Экспорт по шаблону' : 'Собрать и сохранить ZIP')),
      const SizedBox(height: 12),
      const Text('Экспериментальный формат на основе PhotoOpps. Совместимость с импортом игры требует проверки.',
        style: TextStyle(color: Colors.grey)),
    ]),
  );
}
