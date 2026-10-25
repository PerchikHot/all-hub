import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CodexPage extends StatefulWidget {
  const CodexPage({super.key});
  @override
  State<CodexPage> createState() => _CodexPageState();
}
class _CodexPageState extends State<CodexPage> {
  final folder = TextEditingController();
  final prompt = TextEditingController();
  final output = <String>[];
  bool running = false;
  String? error;
  @override
  void initState() { super.initState(); restore(); }
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    folder.text = prefs.getString('codex_workspace') ?? '';
  }
  Future<void> choose() async {
    final chosen = await FilePicker.platform.getDirectoryPath(dialogTitle:'Папка проекта для Codex');
    if (chosen == null) return;
    folder.text = chosen;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('codex_workspace', chosen);
    if (mounted) { setState(() {}); }
  }
  Future<void> run() async {
    final task = prompt.text.trim();
    final workspace = folder.text.trim();
    if (task.isEmpty || workspace.isEmpty || running) return;
    if (!Platform.isWindows) return;
    if (!await Directory(workspace).exists()) {
      setState(() => error = 'Папка проекта не найдена');
      return;
    }
    setState(() { running = true; error = null; output.add('Задача: $task'); });
    try {
      // No shell: the user's prompt is passed as a single CLI argument.
      // Codex runs with workspace-write sandbox; no dangerous bypass flags.
      final result = await Process.run('codex',
        ['exec', '--sandbox', 'workspace-write', '--skip-git-repo-check', task],
        workingDirectory: workspace,
        runInShell: false);
      if (mounted) { setState(() {
        output.add(result.stdout.toString().trim());
        if (result.exitCode != 0) { error = result.stderr.toString().trim().isEmpty
          ? 'Codex завершился с кодом ${result.exitCode}'
          : result.stderr.toString().trim(); }
      }); }
    } catch (e) {
      if (mounted) { setState(() => error = 'Не удалось запустить Codex: $e. Проверь команду codex и авторизацию.'); }
    } finally {
      if (mounted) { setState(() => running = false); }
    }
  }
  @override
  void dispose() { folder.dispose(); prompt.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => ListView(padding:const EdgeInsets.all(16),children:[
    Text('Codex — работа с проектами',style:Theme.of(context).textTheme.titleLarge),
    const SizedBox(height:8),
    Text(Platform.isWindows
      ? 'Используется уже установленный Codex CLI. Изменения разрешены только в выбранной папке проекта. Проверь результат перед публикацией.'
      : 'Запуск установленного на ПК Codex доступен в Windows-версии All Hub. На Android потребуется отдельное защищённое подключение к ПК или облаку.'),
    const SizedBox(height:12),
    TextField(controller:folder,readOnly:true,decoration:InputDecoration(labelText:'Папка проекта',
      suffixIcon:IconButton(onPressed:Platform.isWindows?choose:null,icon:const Icon(Icons.folder_open)))),
    const SizedBox(height:12),
    TextField(controller:prompt,maxLines:5,minLines:3,decoration:const InputDecoration(
      labelText:'Задание Codex',hintText:'Исправь ошибки в проекте и проверь тесты',border:OutlineInputBorder())),
    const SizedBox(height:12),
    FilledButton.icon(onPressed:Platform.isWindows && !running?run:null,
      icon:const Icon(Icons.terminal),label:Text(running?'Codex работает…':'Запустить задачу')),
    if (running) const LinearProgressIndicator(),
    if (error != null) SelectableText(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
    const SizedBox(height:12),
    for (final line in output) Card(child:Padding(padding:const EdgeInsets.all(12),child:SelectableText(line.isEmpty?'Нет вывода':line))),
  ]);
}
