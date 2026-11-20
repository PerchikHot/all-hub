import 'dart:convert';

/// Shared persistence format for Ollama-specific and Forge-only chat history.
class EyraChatHistoryCodec {
  static String key(String? model) => model == null
      ? 'eyra_chat_history_offline'
      : 'ollama_chat_history_model_$model';

  static List<Map<String, String>> decode(String? raw) {
    if (raw == null) return [];
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! List) return [];
      return parsed.whereType<Map>().map((entry) => <String, String>{
        'role': entry['role']?.toString() ?? '',
        'content': entry['content']?.toString() ?? '',
        if (entry['imagePath'] is String)
          'imagePath': entry['imagePath'] as String,
      }).where((entry) =>
          entry['role'] == 'user' || entry['role'] == 'assistant').toList();
    } catch (_) {
      return [];
    }
  }

  static String encode(List<Map<String, String>> messages) =>
      jsonEncode(messages.length > 100
          ? messages.sublist(messages.length - 100)
          : messages);
}
