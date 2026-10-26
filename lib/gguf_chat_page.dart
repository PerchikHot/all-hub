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

  @override
  void dispose() { input.dispose(); super.dispose(); }

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty || generating) return;
    input.clear();
    setState(() { messages.add((true, text)); generating = true; });
    final history = messages.takeLast(8).map((m) =>
      '<|im_start|>${m.$1 ? "user" : "assistant"}\\n${m.$2}\\n<|im_end|>').join('\\n');
    final prompt = '<|im_start|>system\\nТы полезный ассистент. Отвечай по-русски.\\n<|im_end|>\\n'
        '$history\\n<|im_start|>assistant\\n';
    try {
      final reply = await generateNativeGguf(widget.modelPath, prompt);
      if (mounted) setState(() => messages.add((false, reply.isEmpty ? '(Пустой ответ)' : reply)));
    } catch (e) {
      if (mounted) setState(() => messages.add((false, 'Ошибка генерации: $e')));
    } finally {
      if (mounted) setState(() => generating = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('GGUF • офлайн-чат')),
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
