import 'dart:convert';

/// Portable, text-only chat backup. Image paths are deliberately omitted:
/// they refer to private files on the originating device.
class EyraChatBackup {
  static const version = 1;
  static const maxBytes = 2 * 1024 * 1024;
  static const maxMessages = 100;

  static String encode(List<Map<String, String>> messages, DateTime exportedAt) {
    final safe = messages.take(maxMessages).map((m) => {
      'role': m['role'],
      'content': m['content'] ?? '',
    }).where((m) => (m['role'] == 'user' || m['role'] == 'assistant') &&
        (m['content'] as String).length <= 12000).toList();
    final data = jsonEncode({
      'format': 'eyra-chat-text', 'version': version,
      'exportedAt': exportedAt.toUtc().toIso8601String(), 'messages': safe,
    });
    if (utf8.encode(data).length > maxBytes) {
      throw const FormatException('История слишком велика для экспорта');
    }
    return data;
  }

  static List<Map<String, String>> decode(String raw) {
    if (utf8.encode(raw).length > maxBytes) {
      throw const FormatException('Копия переписки превышает 2 МиБ');
    }
    final data = jsonDecode(raw);
    if (data is! Map || data['format'] != 'eyra-chat-text' ||
        data['version'] != version || data['messages'] is! List) {
      throw const FormatException('Неизвестный формат копии переписки');
    }
    final entries = data['messages'] as List;
    if (entries.length > maxMessages) {
      throw const FormatException('В копии больше 100 сообщений');
    }
    return entries.map((entry) {
      if (entry is! Map || (entry['role'] != 'user' &&
          entry['role'] != 'assistant') || entry['content'] is! String ||
          (entry['content'] as String).length > 12000) {
        throw const FormatException('Повреждённое сообщение в копии');
      }
      return <String, String>{
        'role': entry['role'] as String,
        'content': entry['content'] as String,
      };
    }).toList();
  }
}
