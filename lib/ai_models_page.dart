import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'local_ai_chat.dart';
import 'codex_page.dart';

class AiModelsPage extends StatefulWidget {
  const AiModelsPage({super.key});
  @override
  State<AiModelsPage> createState() => _AiModelsPageState();
}

class _AiModelsPageState extends State<AiModelsPage> {
  List<String> paths = [];
  bool busy = true;
  bool importing = false;
  int importedCount = 0;
  int mode = 0;
  int invalidCount = 0;
  Future<(int?, int?)> ggufDetails(String path) async {
    final version = await ggufVersion(path);
    if (version == null) return (null, null);
    try { return (version, await File(path).length()); }
    catch (_) { return (version, null); }
  }
  Future<int?> ggufVersion(String path) async {
    RandomAccessFile? handle;
    try {
      handle = await File(path).open();
      final bytes = await handle.read(8);
      if (bytes.length != 8 || bytes[0] != 0x47 || bytes[1] != 0x47 ||
          bytes[2] != 0x55 || bytes[3] != 0x46) return null;
      final version = ByteData.sublistView(Uint8List.fromList(bytes)).getUint32(4, Endian.little);
      return version >= 1 && version <= 4 ? version : null;
    } catch (_) { return null; }
    finally { await handle?.close(); }
  }
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() { paths = prefs.getStringList('ai_model_paths') ?? []; busy = false; });
  }
  Future<void> addModels() async {
    if (importing) return;
    final picked = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: true);
    if (picked == null) return;
    if (mounted) setState(() { importing = true; importedCount = 0; invalidCount = 0; });
    final next = [...paths];
    try {
      final support = await getApplicationSupportDirectory();
      for (final f in picked.files) {
        if (f.path == null || !f.name.toLowerCase().endsWith('.gguf')) continue;
        File? temp;
        try {
          final source = File(f.path!);
          if (await ggufVersion(source.path) == null) { invalidCount++; continue; }
          String path = source.path;
          if (Platform.isAndroid) {
            final dest = Directory('${support.path}/models');
            await dest.create(recursive: true);
            final filename = '${DateTime.now().microsecondsSinceEpoch}_${f.name}';
            temp = File('${dest.path}/$filename.part');
            await source.copy(temp.path);
            final sourceSize = await source.length();
            if (await temp.length() != sourceSize || await ggufVersion(temp.path) == null) {
              invalidCount++;
              continue;
            }
            final completed = await temp.rename('${dest.path}/$filename');
            path = completed.path;
            temp = null;
          }
          if (!next.contains(path)) { next.add(path); importedCount++; }
        } catch (_) {
          invalidCount++;
        } finally {
          if (temp != null) {
            try { if (await temp.exists()) await temp.delete(); } catch (_) {}
          }
        }
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('ai_model_paths', next);
      if (mounted) setState(() => paths = next);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка импорта моделей: $e')));
    } finally {
      if (mounted) {
        setState(() => importing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Импортировано GGUF: $importedCount. Ошибок: $invalidCount')));
      }
    }
  }
  Future<void> remove(String path) async {
    final support = await getApplicationSupportDirectory();
    final managedDir = Directory('${support.path}/models').absolute.path;
    final file = File(path);
    if (file.absolute.path.startsWith('$managedDir${Platform.pathSeparator}') && await file.exists()) {
      try { await file.delete(); } catch (_) {}
    }
    final next = paths.where((p) => p != path).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('ai_model_paths', next);
    if (mounted) setState(() => paths = next);
  }
  Future<void> confirmRemove(String path) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Удалить модель?'),
      content: const Text('Импортированная в All Hub копия GGUF будет удалена с устройства. Исходный файл вне приложения останется без изменений.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
      ],
    ));
    if (confirmed == true) await remove(path);
  }
  String fileSize(int bytes) => bytes >= 1073741824
      ? '${(bytes / 1073741824).toStringAsFixed(2)} ГБ'
      : '${(bytes / 1048576).toStringAsFixed(0)} МБ';
  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(padding: const EdgeInsets.all(12), child: SegmentedButton<int>(
      segments: const [ButtonSegment(value:0,label:Text('Ollama')),ButtonSegment(value:1,label:Text('Codex')),ButtonSegment(value:2,label:Text('GGUF'))],
      selected:{mode},onSelectionChanged:(v)=>setState(()=>mode=v.first))),
    Expanded(child:mode == 0 ? const LocalAiChat() : mode == 1 ? const CodexPage() : ListView(padding: const EdgeInsets.all(20), children: [
    Text('Локальные ИИ-модели', style: Theme.of(context).textTheme.headlineSmall),
    const SizedBox(height: 12),
    const Text('Добавь уже скачанные GGUF-модели. Они останутся локальными. Это список файлов, а не запущенный ИИ: для общения потребуется подключить совместимый движок инференса.'),
    const SizedBox(height: 16),
    FilledButton.icon(onPressed: busy || importing ? null : addModels, icon: const Icon(Icons.add), label: Text(importing ? 'Импортируем модели…' : 'Добавить GGUF-модели')),
    if (importing) const LinearProgressIndicator(),
    const SizedBox(height: 16),
    if (busy) const Center(child: CircularProgressIndicator()),
    if (!busy && paths.isEmpty) const Text('Модели пока не добавлены'),
    for (final path in paths)
      FutureBuilder<(int?, int?)>(future: ggufDetails(path), builder: (context, snap) => Card(child: ListTile(
        leading: Icon(snap.data?.$1 != null ? Icons.memory : Icons.warning_amber),
        title: Text(path.split(Platform.pathSeparator).last),
        subtitle: Text(snap.data?.$1 != null ? 'GGUF v${snap.data!.$1} • ${snap.data!.$2 == null ? "размер неизвестен" : fileSize(snap.data!.$2!)} • движок не подключён' : 'Невозможно прочитать GGUF'),
        trailing: IconButton(tooltip: 'Убрать из списка', onPressed: () => confirmRemove(path), icon: const Icon(Icons.close)),
      ))),
  ])),
  ]);
}
