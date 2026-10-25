import 'dart:convert';
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
  String? error;
  @override
  void initState() { super.initState(); restore(); }
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    address.text = prefs.getString('ollama_endpoint') ?? 'http://127.0.0.1:11434';
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
      if (mounted) { setState(() { models = []; selected = null; error = 'Нет подключения к Ollama: $e'; });
    }
  }
  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty || sending || selected == null) return;
    input.clear();
    setState(() { messages.add({'role':'user','content':text}); sending = true; error = null; });
    try {
      final base = address.text.trim().replaceAll(RegExp(r'/$'), '');
      final response = await http.post(Uri.parse('$base/api/chat'),
        headers: {'Content-Type':'application/json'},
        body: jsonEncode({'model':selected,'stream':false,'messages':messages}))
        .timeout(const Duration(minutes: 5));
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}: ${response.body}');
      final result = jsonDecode(response.body) as Map<String, dynamic>;
      final message = result['message'] as Map<String, dynamic>;
      if (mounted) { setState(() => messages.add({'role':'assistant','content':message['content'].toString()})); }
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
      ]),
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
