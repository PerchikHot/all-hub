import 'dart:io';
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
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() { paths = prefs.getStringList('ai_model_paths') ?? []; busy = false; });
  }
  Future<void> addModels() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: true);
    if (picked == null) return;
    if (mounted) setState(() { importing = true; importedCount = 0; });
    final next = [...paths];
    final support = await getApplicationSupportDirectory();
    for (final f in picked.files) {
      if (f.path == null || !f.name.toLowerCase().endsWith('.gguf')) continue;
      try {
        String path = f.path!;
        if (Platform.isAndroid) {
          final dest = Directory('${support.path}/models');
          await dest.create(recursive: true);
          path = '${dest.path}/${DateTime.now().microsecondsSinceEpoch}_${f.name}';
          await File(f.path!).copy(path);
        }
        if (!next.contains(path)) { next.add(path); importedCount++; }
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('ai_model_paths', next);
    if (mounted) setState(() { paths = next; importing = false; });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Импортировано GGUF: $importedCount')));
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
      FutureBuilder<FileStat?>(future: File(path).stat().then((s) => s.type == FileSystemEntityType.file ? s : null).catchError((_) => null), builder: (context, snap) => Card(child: ListTile(
        leading: Icon(snap.data != null ? Icons.memory : Icons.warning_amber),
        title: Text(path.split(Platform.pathSeparator).last),
        subtitle: Text(snap.data != null ? '${fileSize(snap.data!.size)} • движок не подключён' : 'Файл недоступен'),
        trailing: IconButton(tooltip: 'Убрать из списка', onPressed: () => confirmRemove(path), icon: const Icon(Icons.close)),
      ))),
  ])),
  ]);
}
