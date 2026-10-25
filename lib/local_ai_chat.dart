import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class LocalAiChat extends StatefulWidget {
  const LocalAiChat({super.key});
  @override
  State<LocalAiChat> createState() => _LocalAiChatState();
}
class _LocalAiChatState extends State<LocalAiChat> {
  final address = TextEditingController(text: 'http://127.0.0.1:11434');
  final input = TextEditingController();
  final messages = <Map<String, String>>[];
  List<String> models = [];
  String? selected;
  bool sending = false;
  bool restoring = true;
  String historyKey(String model) => 'ollama_chat_history_model_$model';
  Future<void> selectModel(String? model) async {
    if (sending || model == null || model == selected) return;
    await saveMessages();
    final prefs = await SharedPreferences.getInstance();
    var saved = prefs.getString(historyKey(model));
    // One-time migration from the older shared Ollama history.
    if (saved == null) {
      final legacy = prefs.getString('ollama_chat_history');
      if (legacy != null) {
        saved = legacy;
        await prefs.setString(historyKey(model), legacy);
        await prefs.remove('ollama_chat_history');
      }
    }
    final loaded = <Map<String, String>>[];
    if (saved != null) {
      try {
        final decoded = jsonDecode(saved) as List<dynamic>;
        loaded.addAll(decoded.whereType<Map>().map((m) => {
          'role': m['role']?.toString() ?? '',
          'content': m['content']?.toString() ?? '',
        }).where((m) => m['role'] == 'user' || m['role'] == 'assistant'));
      } catch (_) {}
    }
    if (mounted) setState(() { selected = model; messages..clear()..addAll(loaded); });
    await prefs.setString('ollama_selected_model', model);
  }
  Future<void> saveMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final model = selected;
    if (model == null) return;
    await prefs.setString(historyKey(model), jsonEncode(messages.length > 100
        ? messages.sublist(messages.length - 100) : messages));
  }
  Future<void> clearMessages() async {
    if (sending) return;
    setState(() { messages.clear(); error = null; });
    await saveMessages();
  }
  String? error;
  @override
  void initState() { super.initState(); restore(); }
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    address.text = prefs.getString('ollama_endpoint') ?? 'http://127.0.0.1:11434';
    final preferred = prefs.getString('ollama_selected_model');
    if (preferred != null && preferred.isNotEmpty) await selectModel(preferred);
    if (mounted) setState(() => restoring = false);
    await fetchModels();
  }
  Future<void> fetchModels() async {
    try {
      final base = address.text.trim().replaceAll(RegExp(r'/$'), '');
      final response = await http.get(Uri.parse('$base/api/tags')).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final names = (decoded['models'] as List<dynamic>? ?? [])
          .map((e) => (e as Map<String, dynamic>)['name'].toString()).toList();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ollama_endpoint', base);
      if (mounted) setState(() {
        models = names;
        error = names.isEmpty ? 'В Ollama пока нет доступных моделей' : null;
      });
      if (names.isNotEmpty && mounted) {
        final preferred = prefs.getString('ollama_selected_model');
        final next = names.contains(selected) ? selected! :
            names.contains(preferred) ? preferred! : names.first;
        await selectModel(next);
      }
    } catch (e) {
      if (mounted) { setState(() { models = []; error = 'Нет подключения к Ollama: $e. Сохранённая переписка доступна офлайн.'; }); }
    }
  }
  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty || sending || selected == null || restoring || !models.contains(selected)) return;
    input.clear();
    setState(() { messages.add({'role':'user','content':text}); sending = true; error = null; });
    await saveMessages();
    try {
      final base = address.text.trim().replaceAll(RegExp(r'/$'), '');
      final recent = messages.length > 40 ? messages.sublist(messages.length - 40) : messages;
      final response = await http.post(Uri.parse('$base/api/chat'),
        headers: {'Content-Type':'application/json'},
        body: jsonEncode({'model':selected,'stream':false,'messages':recent}))
        .timeout(const Duration(minutes: 5));
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}: ${response.body}');
      final result = jsonDecode(response.body) as Map<String, dynamic>;
      final message = result['message'] as Map<String, dynamic>;
      if (mounted) {
        setState(() => messages.add({'role':'assistant','content':message['content'].toString()}));
        await saveMessages();
      }
    } catch (e) {
      if (mounted) { setState(() => error = 'Ошибка ответа: $e. Сообщение сохранено в истории.'); }
    } finally {
      if (mounted) { setState(() => sending = false); }
    }
  }
  @override
  void dispose() { address.dispose(); input.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(padding: const EdgeInsets.all(12), child: Column(children: [
      TextField(controller: address, decoration: const InputDecoration(labelText: 'Адрес Ollama (ПК или локальный сервер)', isDense:true)),
      Row(children: [
        Expanded(child: DropdownButton<String>(isExpanded:true, value:models.contains(selected) ? selected : null,
          hint: const Text('Выбери модель'), items: models.map((m) => DropdownMenuItem(value:m,child:Text(m,overflow:TextOverflow.ellipsis))).toList(),
          onChanged: sending ? null : selectModel)),
        IconButton(onPressed:fetchModels,icon:const Icon(Icons.refresh),tooltip:'Найти модели'),
        IconButton(onPressed:sending || restoring || messages.isEmpty ? null : () async {
          final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
            title: const Text('Очистить переписку?'),
            content: const Text('История Ollama будет удалена только из All Hub.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Очистить')),
            ],
          ));
          if (confirmed == true) await clearMessages();
        }, icon: const Icon(Icons.delete_outline), tooltip: 'Очистить историю'),
      ]),
      if (Platform.isAndroid) const Padding(padding: EdgeInsets.only(top:8), child: Text('На телефоне 127.0.0.1 означает сам телефон, а не компьютер. Чтобы подключить Ollama на ПК, укажи адрес компьютера в одной Wi-Fi сети, например http://192.168.1.10:11434. Ollama на ПК должна разрешать подключения из локальной сети.')),
      if (error != null) Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
    ])),
    Expanded(child: ListView.builder(padding:const EdgeInsets.all(12),itemCount:messages.length,itemBuilder:(context,index) {
      final m=messages[index]; final mine=m['role']=='user';
      return Align(alignment:mine?Alignment.centerRight:Alignment.centerLeft,child:Card(
        child:Padding(padding:const EdgeInsets.all(12),child:Text(m['content']??''))));
    })),
    if (sending) const LinearProgressIndicator(),
    SafeArea(top:false,child:Padding(padding:const EdgeInsets.all(12),child:Row(children:[
      Expanded(child:TextField(controller:input, maxLines:3,minLines:1,
        onSubmitted:(_) => send(),decoration:const InputDecoration(hintText:'Напиши сообщение…',border:OutlineInputBorder()))),
      IconButton(onPressed:sending || !models.contains(selected) ? null : send,icon:const Icon(Icons.send)),
    ]))),
  ]);
}
