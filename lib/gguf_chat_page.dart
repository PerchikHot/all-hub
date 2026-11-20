import 'hub_liquid_progress.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'eyra_chat_backup.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'native_llama_runtime.dart';
import 'gguf_prompt_builder.dart';

class GgufChatPage extends StatefulWidget {
  const GgufChatPage({super.key, required this.modelPath});
  final String modelPath;
  @override
  State<GgufChatPage> createState() => _GgufChatPageState();
}

class _GgufChatPageState extends State<GgufChatPage> {
  final input = TextEditingController();
  final messages = <(bool, String)>[];
  bool generating = false;
  bool restoring = true;
  bool transferring = false;
  String? generationError;
  DateTime? generationStarted;
  Timer? elapsedTimer;
  int elapsedSeconds = 0;
  String generationStatus = '';
  int maxTokens = 128;

  String get storageKey => 'gguf_chat_${base64Url.encode(utf8.encode(widget.modelPath))}';

  @override
  void initState() {
    super.initState();
    restoreChat();
  }

  Future<void> restoreChat() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw) as List<dynamic>;
      final restored = decoded.map((item) {
        final row = item as Map<String, dynamic>;
        return (row['user'] == true, row['text'] as String);
      }).toList();
      if (mounted) setState(() {
        if (messages.isEmpty) messages.addAll(restored.takeLast(100));
        restoring = false;
      });
    } catch (_) {
      // A storage failure must not permanently disable the chat input.
    } finally {
      if (mounted && restoring) setState(() => restoring = false);
    }
  }

  Future<void> saveChat() async {
    final prefs = await SharedPreferences.getInstance();
    final rows = messages.takeLast(100).map((m) => {
      'user': m.$1, 'text': m.$2,
    }).toList();
    await prefs.setString(storageKey, jsonEncode(rows));
  }

  Future<void> clearChat() async {
    if (generating || restoring || transferring) return;
    final approved = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Удалить переписку GGUF?'),
      content: const Text('Все сообщения этой модели на данном устройстве будут удалены. Отменить это действие нельзя.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
      ],
    ));
    if (approved != true || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
    if (mounted) setState(() { messages.clear(); generationError = null; });
  }


  // The same portable text format is used by Ollama and GGUF. No model
  // paths or private files are exported, and imports are always explicit.
  Future<void> exportHistory() async {
    if (generating || restoring || transferring) return;
    setState(() => transferring = true);
    try {
      final data = EyraChatBackup.encode(messages.map((m) =>
        <String, String>{'role': m.$1 ? 'user' : 'assistant',
          'content': m.$2}).toList(), DateTime.now());
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить текстовую переписку GGUF',
        fileName: 'eyra-gguf-chat.json', type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: Uint8List.fromList(utf8.encode(data)));
      if (path != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Текстовая переписка экспортирована')));
      }
    } catch (e) {
      if (mounted) setState(() => generationError = 'Ошибка экспорта: $e');
    } finally {
      if (mounted) setState(() => transferring = false);
    }
  }

  Future<void> importHistory() async {
    if (generating || restoring || transferring) return;
    setState(() => transferring = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['json'], withData: false);
      if (picked == null || picked.files.isEmpty) return;
      final path = picked.files.single.path;
      if (path == null) throw const FormatException('Файл недоступен');
      final file = File(path);
      if (await file.length() > EyraChatBackup.maxBytes) {
        throw const FormatException('Файл превышает лимит 2 МиБ');
      }
      final incoming = EyraChatBackup.decode(await file.readAsString());
      if (!mounted) return;
      final choice = await showDialog<String>(context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Импортировать переписку?'),
          content: Text('Найдено ${incoming.length} сообщений. '
            'Поддерживаются копии Ollama и GGUF. '
            'Личные файлы и изображения не переносятся.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена')),
            OutlinedButton(onPressed: () => Navigator.pop(ctx, 'replace'),
              child: const Text('Заменить')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'merge'),
              child: const Text('Объединить')),
          ]));
      if (choice == null || !mounted) return;
      final imported = incoming.map((m) =>
        (m['role'] == 'user', m['content']!)).toList();
      final next = choice == 'merge'
          ? <(bool, String)>[...messages, ...imported] : imported;
      final trimmed = next.length > 100 ? next.sublist(next.length - 100) : next;
      // Persist first; never erase the visible conversation on failed writes.
      final prefs = await SharedPreferences.getInstance();
      final rows = trimmed.map((m) => {'user': m.$1, 'text': m.$2}).toList();
      if (!await prefs.setString(storageKey, jsonEncode(rows))) {
        throw const FileSystemException('Не удалось сохранить импорт');
      }
      if (mounted) {
        setState(() { messages..clear()..addAll(trimmed); generationError = null; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Переписка импортирована')));
      }
    } catch (e) {
      if (mounted) setState(() => generationError = 'Ошибка импорта: $e');
    } finally {
      if (mounted) setState(() => transferring = false);
    }
  }

  @override
  void dispose() { elapsedTimer?.cancel(); input.dispose(); super.dispose(); }

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty || generating || restoring || transferring) return;
    input.clear();
    elapsedTimer?.cancel();
    generationStarted = DateTime.now();
    elapsedSeconds = 0;
    setState(() {
      messages.add((true, text));
      generating = true;
      generationError = null;
      generationStatus = 'Загрузка модели / генерация на CPU';
    });
    elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => elapsedSeconds = DateTime.now().difference(generationStarted!).inSeconds);
    });
    try {
      // Saving is best-effort: disabled/full storage must never prevent
      // inference or leave the send button stuck in a busy state.
      try {
        await saveChat();
      } catch (_) {
        if (mounted) setState(() =>
          generationStatus = 'Генерация (историю пока не удалось сохранить)');
      }
      final prompt = buildGgufChatPrompt(messages
          .map((m) => (user: m.$1, text: m.$2)).toList());
      final reply = await generateNativeGguf(
          widget.modelPath, prompt, maxTokens: maxTokens);
      final duration = DateTime.now().difference(generationStarted!).inMilliseconds / 1000;
      if (mounted) setState(() {
        messages.add((false, reply.isEmpty ? '(Пустой ответ)' : reply));
        generationStatus = 'Ответ за ${duration.toStringAsFixed(1)} с';
      });
    } catch (e) {
      if (mounted) setState(() {
        generationError = 'Ошибка генерации: $e';
        generationStatus = 'Не удалось получить ответ';
      });
    } finally {
      elapsedTimer?.cancel();
      try {
        await saveChat();
      } catch (_) {
        if (mounted) setState(() {
          generationError = generationError == null
              ? 'Не удалось сохранить переписку на устройстве. Сообщения пока доступны только в открытом чате.'
              : '$generationError\\nНе удалось сохранить переписку на устройстве.';
        });
      } finally {
        if (mounted) setState(() => generating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('GGUF • офлайн-чат'),
      actions: [
        IconButton(tooltip: 'Экспорт переписки (JSON)',
          onPressed: generating || restoring || transferring ? null : exportHistory,
          icon: const Icon(Icons.save_alt_outlined)),
        IconButton(tooltip: 'Импорт переписки (JSON)',
          onPressed: generating || restoring || transferring ? null : importHistory,
          icon: const Icon(Icons.upload_file_outlined)),
        PopupMenuButton<int>(
          tooltip: 'Максимальная длина ответа',
          initialValue: maxTokens,
          onSelected: (value) => setState(() => maxTokens = value),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 64, child: Text('Коротко · 64 токена')),
            PopupMenuItem(value: 128, child: Text('Обычно · 128 токенов')),
            PopupMenuItem(value: 256, child: Text('Подробно · 256 токенов')),
          ],
        ),
        IconButton(
          tooltip: 'Выгрузить модель из памяти',
          onPressed: generating ? null : () async {
            try {
              final ok = await unloadNativeGguf();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(ok ? 'Модель выгружена из оперативной памяти' : 'Не удалось выгрузить модель'),
              ));
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка выгрузки: $e')));
            }
          },
          icon: const Icon(Icons.memory_outlined),
        ),
        IconButton(
          tooltip: 'Очистить переписку',
          onPressed: generating || restoring || transferring || messages.isEmpty ? null : clearChat,
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    ),
    body: Column(children: [
      Expanded(child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: messages.length,
        itemBuilder: (context, i) => Align(
          alignment: messages[i].$1 ? Alignment.centerRight : Alignment.centerLeft,
          child: Card(child: Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(messages[i].$2),
          )),
        ),
      )),
      if (generationError != null) Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(children: [
          Expanded(child: Text(generationError!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          TextButton(onPressed: generating ? null : () => setState(() => generationError = null), child: const Text('Закрыть')),
        ]),
      ),
      if (generating) ...[
        const HubLiquidProgress(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(children: [
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Expanded(child: Text('$generationStatus · ${elapsedSeconds} с', style: Theme.of(context).textTheme.bodySmall)),
          ]),
        ),
      ] else if (generationStatus.isNotEmpty)
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Align(alignment: Alignment.centerLeft, child: Text(generationStatus, style: Theme.of(context).textTheme.bodySmall))),
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Expanded(child: TextField(
          controller: input,
          maxLines: 3, minLines: 1,
          decoration: const InputDecoration(hintText: 'Сообщение модели', border: OutlineInputBorder()),
          onSubmitted: (_) => send(),
        )),
        IconButton(onPressed: generating || restoring || transferring ? null : send, icon: const Icon(Icons.send)),
      ])),
    ]),
  );
}

extension _TakeLast<T> on List<T> {
  Iterable<T> takeLast(int count) => skip(length > count ? length - count : 0);
}
