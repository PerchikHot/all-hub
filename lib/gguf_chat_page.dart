import 'package:flutter/material.dart';
import 'native_llama_runtime.dart';

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
  int maxTokens = 128;

  @override
  void dispose() { input.dispose(); super.dispose(); }

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty || generating) return;
    input.clear();
    setState(() { messages.add((true, text)); generating = true; });
    // Limit conversation length to avoid exceeding the native 2048-token context.
    final recent = messages.takeLast(8).toList();
    var remaining = 3000;
    final clipped = <(bool, String)>[];
    for (final message in recent.reversed) {
      if (remaining <= 0) break;
      final value = message.$2.length > remaining
          ? message.$2.substring(message.$2.length - remaining)
          : message.$2;
      clipped.insert(0, (message.$1, value));
      remaining -= value.length;
    }
    final history = clipped.map((m) =>
      '<|im_start|>${m.$1 ? "user" : "assistant"}\n${m.$2}\n<|im_end|>').join('\n');
    final prompt = '<|im_start|>system\nТы полезный ассистент. Отвечай по-русски.\n<|im_end|>\n'
        '$history\n<|im_start|>assistant\n';
    try {
      final reply = await generateNativeGguf(widget.modelPath, prompt, maxTokens: maxTokens);
      if (mounted) setState(() => messages.add((false, reply.isEmpty ? '(Пустой ответ)' : reply)));
    } catch (e) {
      if (mounted) {
        setState(() => messages.add((false, 'Ошибка генерации: $e')));
      }
    } finally {
      if (mounted) setState(() => generating = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('GGUF • офлайн-чат'),
      actions: [
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
          tooltip: 'Очистить переписку',
          onPressed: generating ? null : () => setState(messages.clear),
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
      if (generating) const LinearProgressIndicator(),
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Expanded(child: TextField(
          controller: input,
          maxLines: 3, minLines: 1,
          decoration: const InputDecoration(hintText: 'Сообщение модели', border: OutlineInputBorder()),
          onSubmitted: (_) => send(),
        )),
        IconButton(onPressed: generating ? null : send, icon: const Icon(Icons.send)),
      ])),
    ]),
  );
}

extension _TakeLast<T> on List<T> {
  Iterable<T> takeLast(int count) => skip(length > count ? length - count : 0);
}
