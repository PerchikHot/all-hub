import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

/// Decode exports away from the UI isolate. A large conversations.json can
/// otherwise block scrolling, buttons and Android's main-thread watchdog.
/// The limit is checked before reading to avoid accidentally loading a
/// multi-gigabyte archive into memory. Only extracted text leaves the isolate.
Future<List<String>> extractChatGptExcerptsFromFile(String path,
    {int maxBytes = 64 * 1024 * 1024}) async {
  if (maxBytes <= 0) throw const FormatException('Неверный лимит импорта');
  final source = File(path);
  final size = await source.length();
  if (size > maxBytes) {
    throw FormatException(
      'Экспорт больше ${maxBytes ~/ (1024 * 1024)} МБ. '
      'Выбери меньший conversations.json; исходный файл не изменён.');
  }
  return Isolate.run(() async {
    // Recheck the size in the worker in case the selected file changed.
    if (await source.length() > maxBytes) {
      throw const FormatException('Размер файла изменился во время импорта');
    }
    final decoded = jsonDecode(await source.readAsString());
    return extractChatGptExcerpts(decoded);
  });
}

// Parses only the active branch of each ChatGPT conversation.
// No source identifiers or metadata are persisted.
List<String> extractChatGptExcerpts(dynamic data) {
  if (data is! List) throw const FormatException('Ожидался массив conversations.json');
  final excerpts = <String>[];
  // Repeated text across conversations should not consume the limited local
  // excerpt budget or crowd out other relevant memories.
  final seen = <String>{};
  // Prefer recently updated conversations when the local excerpt budget fills.
  // Missing timestamps retain the original export order.
  final ordered = data.asMap().entries.toList()..sort((a, b) {
    num timestamp(dynamic item) {
      if (item is! Map) return 0;
      final value = item['update_time'] ?? item['create_time'];
      return value is num && value.isFinite ? value : 0;
    }
    final comparison = timestamp(b.value).compareTo(timestamp(a.value));
    return comparison != 0 ? comparison : a.key.compareTo(b.key);
  });
  for (final entry in ordered) {
    final conversation = entry.value;
    if (conversation is! Map) continue;
    final mapping = conversation['mapping'];
    if (mapping is! Map) continue;
    // Follow only the visible conversation branch. Export mappings also
    // contain abandoned regenerations and edited-message alternatives.
    final currentNode = conversation['current_node'];
    if (currentNode is! String || !mapping.containsKey(currentNode)) continue;
    final branch = <Map>[];
    final visited = <String>{};
    String? cursor = currentNode;
    while (cursor != null && visited.add(cursor)) {
      final node = mapping[cursor];
      if (node is! Map) break;
      branch.add(node);
      final parent = node['parent'];
      cursor = parent is String ? parent : null;
    }
    for (final node in branch.reversed) {
      if (node['message'] is! Map) continue;
      final message = node['message'] as Map;
      final author = message['author'];
      if (author is! Map || !['user', 'assistant'].contains(author['role'])) continue;
      final content = message['content'];
      if (content is! Map || content['content_type'] != 'text') continue;
      final parts = content['parts'];
      if (parts is! List) continue;
      for (final part in parts) {
        if (part is! String) continue;
        final cleaned = part.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (cleaned.length < 12) continue;
        final excerpt = cleaned.length > 500 ? cleaned.substring(0, 500) : cleaned;
        if (!seen.add(excerpt)) continue;
        excerpts.add(excerpt);
        if (excerpts.length >= 1000) return excerpts;
      }
    }
  }
  return excerpts;
}
