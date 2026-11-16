import 'dart:io';
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
      allowedExtensions: ['png', 'jpg', 'jpeg'],
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
      add('$root/pack.ini', Uint8List.fromList(ini.toString().codeUnits));
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
      TextField(controller: title, decoration: const InputDecoration(labelText: 'Название пака')),
      const SizedBox(height: 12),
      TextField(controller: packId, decoration: const InputDecoration(labelText: 'ID пака (латиница)')),
      const SizedBox(height: 12),
      TextField(controller: category, decoration: const InputDecoration(labelText: 'Категория')),
      const SizedBox(height: 16),
      OutlinedButton.icon(onPressed: busy ? null : addPhotos,
        icon: const Icon(Icons.add_photo_alternate), label: const Text('Добавить PNG/JPG')),
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
        label: Text(busy ? 'Сборка...' : 'Собрать и сохранить ZIP')),
      const SizedBox(height: 12),
      const Text('Экспериментальный формат на основе PhotoOpps. Совместимость с импортом игры требует проверки.',
        style: TextStyle(color: Colors.grey)),
    ]),
  );
}
