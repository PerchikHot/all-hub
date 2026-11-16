import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
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

  Future<void> addPhotos() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png'],
      allowMultiple: true,
      withData: true,
    );
    if (picked == null || !mounted) return;
    final added = <Uint8List>[];
    for (final file in picked.files) {
      final bytes = file.bytes ?? (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes != null && bytes.isNotEmpty) added.add(bytes);
    }
    if (mounted) setState(() => photos.addAll(added));
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
      });
    } catch (e) {
      if (mounted) setState(() => templateError = '$e');
    }
  }

  Future<void> exportTemplate() async {
    if (templateBytes == null || templateRoot == null || photos.isEmpty) {
      throw const FormatException('Выбери ZIP-шаблон и добавь фотографии');
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
      final bytes = replacement[file.name] ?? Uint8List.fromList(file.content as List<int>);
      result.addFile(ArchiveFile(file.name, bytes.length, bytes));
    }
    final encoded = Uint8List.fromList(ZipEncoder().encode(result));
    final saved = await FilePicker.platform.saveFile(
      dialogTitle: 'Экспорт ZIP по шаблону',
      fileName: 'Snapshot_Custom_Template.zip',
      type: FileType.custom, allowedExtensions: ['zip'], bytes: encoded);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(saved == null ? 'Сохранение отменено' : 'ZIP сохранён: $saved')));
  }

  String safeId(String input) {
    final value = input.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '');
    return value.isEmpty ? 'customSnapshotPack' : value;
  }

  Future<void> exportPack() async {
    if (photos.isEmpty) {
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
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить Snapshot ZIP',
        fileName: 'Snapshot_Pack_$id.zip',
        type: FileType.custom,
        allowedExtensions: ['zip'],
        bytes: bytes,
      );
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
      if (templateError != null) Text(templateError!, style: const TextStyle(color: Colors.redAccent)),
      if (templateName != null) TextButton(onPressed: busy ? null : () => setState(() {
        templateBytes = null; templateName = null; templateRoot = null; templatePhotoNames = [];
      }), child: const Text('Создать новый пак')),
      TextField(controller: title, decoration: const InputDecoration(labelText: 'Название пака')),
      const SizedBox(height: 12),
      TextField(controller: packId, decoration: const InputDecoration(labelText: 'ID пака (латиница)')),
      const SizedBox(height: 12),
      TextField(controller: category, decoration: const InputDecoration(labelText: 'Категория')),
      const SizedBox(height: 16),
      OutlinedButton.icon(onPressed: busy ? null : addPhotos,
        icon: const Icon(Icons.add_photo_alternate), label: const Text('Добавить PNG')),
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