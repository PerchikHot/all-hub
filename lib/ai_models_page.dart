import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'local_ai_chat.dart';
import 'codex_page.dart';
import 'gguf_header.dart';
import 'native_llama_runtime.dart';

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
  String? selectedGguf;
  int invalidCount = 0;
  final Map<String, Future<GgufHeader?>> inspections = {};
  Future<GgufHeader?> inspect(String path) =>
      inspections.putIfAbsent(path, () => GgufHeader.read(path));
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() {
      paths = prefs.getStringList('ai_model_paths') ?? [];
      final saved = prefs.getString('ai_selected_gguf');
      selectedGguf = paths.contains(saved) ? saved : null;
      busy = false;
    });
  }
  Future<void> selectGguf(String path) async {
    if (!paths.contains(path) || await inspect(path) == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_selected_gguf', path);
    if (mounted) setState(() => selectedGguf = path);
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
          if (await GgufHeader.read(source.path) == null) { invalidCount++; continue; }
          String path = source.path;
          if (Platform.isAndroid) {
            final dest = Directory('${support.path}/models');
            await dest.create(recursive: true);
            final filename = '${DateTime.now().microsecondsSinceEpoch}_${f.name}';
            temp = File('${dest.path}/$filename.part');
            await source.copy(temp.path);
            final sourceSize = await source.length();
            if (await temp.length() != sourceSize || await GgufHeader.read(temp.path) == null) {
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
      if (mounted) setState(() { paths = next; inspections.clear(); });
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
      try {
        await file.delete();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось удалить файл модели: $e')));
        return;
      }
    }
    final next = paths.where((p) => p != path).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('ai_model_paths', next);
    if (selectedGguf == path) {
      await prefs.remove('ai_selected_gguf');
    }
    if (mounted) setState(() {
      paths = next;
      inspections.remove(path);
      if (selectedGguf == path) selectedGguf = null;
    });
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
    if (confirmed == true && mounted) await remove(path);
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
    const SizedBox(height: 12),
    ListTile(
      leading: const Icon(Icons.memory_outlined),
      title: const Text('Нативный движок llama.cpp'),
      subtitle: Text(NativeLlamaRuntime.availability),
    ),
    const SizedBox(height: 16),
    FilledButton.icon(onPressed: busy || importing ? null : addModels, icon: const Icon(Icons.add), label: Text(importing ? 'Импортируем модели…' : 'Добавить GGUF-модели')),
    if (importing) const LinearProgressIndicator(),
    const SizedBox(height: 16),
    if (busy) const Center(child: CircularProgressIndicator()),
    if (!busy && paths.isEmpty) const Text('Модели пока не добавлены'),
    if (selectedGguf != null) const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Text('Выбранная модель сохранена для будущего локального движка. Генерация текста пока недоступна.'),
    ),
    for (final path in paths)
      FutureBuilder<GgufHeader?>(future: inspect(path), builder: (context, snap) => Card(child: ListTile(
        leading: Icon(snap.data != null ? Icons.memory : Icons.warning_amber),
        title: Text(path.split(Platform.pathSeparator).last),
        subtitle: Text(snap.data != null ? 'GGUF v${snap.data!.version} • ${fileSize(snap.data!.bytes)} • тензоров: ${snap.data!.tensorCount} • метаданных: ${snap.data!.metadataCount} • движок не подключён' : 'Невозможно прочитать GGUF'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            tooltip: selectedGguf == path ? 'Выбранная модель' : 'Выбрать для локального ИИ',
            onPressed: snap.data == null ? null : () => selectGguf(path),
            icon: Icon(selectedGguf == path ? Icons.radio_button_checked : Icons.radio_button_unchecked),
          ),
          IconButton(tooltip: 'Убрать из списка', onPressed: () => confirmRemove(path), icon: const Icon(Icons.close)),
        ]),
      ))),
  ])),
  ]);
}
