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
  Future<void> saveMessages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ollama_chat_history', jsonEncode(messages));
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
    try {
      final saved = prefs.getString('ollama_chat_history');
      if (saved != null) {
        final decoded = jsonDecode(saved) as List<dynamic>;
        if (mounted) setState(() {
          messages.addAll(decoded.whereType<Map>().map((m) => {
            'role': m['role']?.toString() ?? 'user',
            'content': m['content']?.toString() ?? '',
          }).where((m) => m['role'] == 'user' || m['role'] == 'assistant'));
        });
      }
    } catch (_) { /* Ignore corrupted local history. */ }
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
      if (mounted) { setState(() {
        models = names;
        selected = names.contains(selected) ? selected : (names.isEmpty ? null : names.first);
        error = names.isEmpty ? 'В Ollama пока нет доступных моделей' : null;
      }); }
    } catch (e) {
      if (mounted) { setState(() { models = []; selected = null; error = 'Нет подключения к Ollama: $e'; }); }
    }
  }
  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty || sending || selected == null) return;
    input.clear();
    setState(() { messages.add({'role':'user','content':text}); sending = true; error = null; });
    await saveMessages();
    try {
      final base = address.text.trim().replaceAll(RegExp(r'/$'), '');
      final response = await http.post(Uri.parse('$base/api/chat'),
        headers: {'Content-Type':'application/json'},
        body: jsonEncode({'model':selected,'stream':false,'messages':messages}))
        .timeout(const Duration(minutes: 5));
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}: ${response.body}');
      final result = jsonDecode(response.body) as Map<String, dynamic>;
      final message = result['message'] as Map<String, dynamic>;
      if (mounted) {
        setState(() => messages.add({'role':'assistant','content':message['content'].toString()}));
        await saveMessages();
      }
    } catch (e) {
      if (mounted) { setState(() => error = 'Ошибка ответа: $e'); }
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
        Expanded(child: DropdownButton<String>(isExpanded:true, value:selected,
          hint: const Text('Выбери модель'), items: models.map((m) => DropdownMenuItem(value:m,child:Text(m,overflow:TextOverflow.ellipsis))).toList(),
          onChanged: (v) => setState(() => selected=v))),
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
      IconButton(onPressed:sending?null:send,icon:const Icon(Icons.send)),
    ]))),
  ]);
}
