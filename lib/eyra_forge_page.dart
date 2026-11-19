import 'hub_wait_indicator.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'eyra_forge_client.dart';

/// Manual-only Forge workflow; no background jobs or automatic file writes.
class EyraForgePage extends StatefulWidget {
  const EyraForgePage({super.key});
  @override
  State<EyraForgePage> createState() => _EyraForgePageState();
}

class _EyraForgePageState extends State<EyraForgePage> {
  final endpoint = TextEditingController(text: 'http://127.0.0.1:7860');
  final prompt = TextEditingController();
  final negative = TextEditingController();
  bool busy = false;
  String status = 'Forge должен быть запущен с параметром --api.';
  List<String> models = [];
  Uint8List? image;
  int steps = 20;

  @override
  void initState() { super.initState(); restore(); }
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() {
      endpoint.text = prefs.getString('eyra_forge_endpoint') ?? endpoint.text;
    });
  }

  Future<void> run({required bool generate}) async {
    if (busy) return;
    setState(() { busy = true; status = 'Подключаемся…'; });
    EyraForgeClient? client;
    try {
      client = EyraForgeClient(Uri.parse(endpoint.text.trim()));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('eyra_forge_endpoint', endpoint.text.trim());
      if (generate) {
        final bytes = await client.generate(
          prompt: prompt.text, negativePrompt: negative.text, steps: steps);
        if (mounted) setState(() {
          image = bytes;
          status = 'Изображение получено. Оно пока только в памяти приложения.';
        });
      } else {
        final available = await client.models();
        if (mounted) setState(() {
          models = available;
          status = available.isEmpty ? 'Forge доступен, но моделей нет' :
              'Forge доступен. Моделей: ${available.length}';
        });
      }
    } catch (e) {
      if (mounted) setState(() => status = 'Ошибка: $e');
    } finally {
      client?.close();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    endpoint.dispose(); prompt.dispose(); negative.dispose(); super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Эйра · Forge')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Генерация через ваш Stable Diffusion WebUI Forge. Запустите Forge с --api. На Android адрес 127.0.0.1 означает телефон; для Forge на ПК укажите IP компьютера в локальной сети. Промпт отправляется только при нажатии «Создать». Не открывайте Forge API в публичный интернет.'),
      const SizedBox(height: 12),
      TextField(controller: endpoint, enabled: !busy,
        decoration: const InputDecoration(labelText: 'Адрес Forge API', border: OutlineInputBorder())),
      const SizedBox(height: 8),
      OutlinedButton.icon(onPressed: busy ? null : () => run(generate: false),
        icon: const Icon(Icons.wifi_tethering), label: const Text('Проверить подключение и модели')),
      if (models.isNotEmpty) Text('Модели: ${models.take(5).join(', ')}'),
      const SizedBox(height: 12),
      TextField(controller: prompt, enabled: !busy, minLines: 2, maxLines: 4,
        decoration: const InputDecoration(labelText: 'Описание изображения', border: OutlineInputBorder())),
      const SizedBox(height: 8),
      TextField(controller: negative, enabled: !busy,
        decoration: const InputDecoration(labelText: 'Что исключить (необязательно)', border: OutlineInputBorder())),
      const SizedBox(height: 8),
      Text('Шаги: $steps'),
      Slider(value: steps.toDouble(), min: 5, max: 40, divisions: 7,
        onChanged: busy ? null : (v) => setState(() => steps = v.round())),
      FilledButton.icon(onPressed: busy ? null : () => run(generate: true),
        icon: const Icon(Icons.auto_awesome), label: const Text('Создать изображение')),
      if (busy) const HubWaitIndicator(),
      const SizedBox(height: 8),
      Text(status),
      if (image != null) ...[
        const SizedBox(height: 12),
        Image.memory(image!, fit: BoxFit.contain, errorBuilder: (_, __, ___) =>
          const Text('Не удалось отобразить полученное изображение')),
      ],
    ]),
  );
}
