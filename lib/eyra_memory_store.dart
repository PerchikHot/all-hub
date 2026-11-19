import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Versioned, model-independent memory. Private data never belongs in git.
class EyraMemoryStore {
  EyraMemoryStore._(this.file);
  final File file;

  static Future<EyraMemoryStore> open() async {
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/eyra');
    await dir.create(recursive: true);
    return EyraMemoryStore._(File('${dir.path}/memory.json'));
  }

  Future<Map<String, dynamic>> read() async {
    if (!await file.exists()) return {'schemaVersion': 1, 'entries': <dynamic>[]};
    final raw = jsonDecode(await file.readAsString());
    return validate(raw);
  }

  static Map<String, dynamic> validate(dynamic value) {
    if (value is! Map || value['schemaVersion'] != 1 || value['entries'] is! List) {
      throw const FormatException('Неподдерживаемый формат памяти Эйры');
    }
    final entries = <Map<String, dynamic>>[];
    for (final item in value['entries'] as List) {
      if (item is! Map || item['id'] is! String ||
          item['text'] is! String || item['createdAt'] is! String ||
          item['source'] is! String) {
        throw const FormatException('Повреждённая запись памяти');
      }
      entries.add({
        'id': item['id'],
        'text': item['text'],
        'createdAt': item['createdAt'],
        'source': item['source'],
      });
    }
    return {'schemaVersion': 1, 'entries': entries};
  }

  Future<void> write(Map<String, dynamic> data) async {
    final valid = validate(data);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(valid), flush: true);
    if (await file.exists()) {
      final backup = File('${file.path}.bak');
      await file.copy(backup.path);
    }
    // Rename inside the same directory to avoid partially written JSON.
    if (Platform.isWindows && await file.exists()) await file.delete();
    await temp.rename(file.path);
  }

  Future<void> add(String text, {String source = 'user'}) async {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return;
    final data = await read();
    final entries = (data['entries'] as List).cast<Map<String, dynamic>>();
    final now = DateTime.now().toUtc();
    entries.add({
      'id': '${now.microsecondsSinceEpoch}-${entries.length}',
      'text': cleaned,
      'createdAt': now.toIso8601String(),
      'source': source,
    });
    await write(data);
  }

  Future<void> importJson(String raw, {bool merge = true}) async {
    final imported = validate(jsonDecode(raw));
    if (!merge) {
      await write(imported);
      return;
    }
    final existing = await read();
    final entries = (existing['entries'] as List).cast<Map<String, dynamic>>();
    final seen = entries.map((e) => e['id']).toSet();
    for (final entry in (imported['entries'] as List).cast<Map<String, dynamic>>()) {
      if (seen.add(entry['id'])) entries.add(entry);
    }
    await write(existing);
  }

  Future<String> exportJson() async =>
      const JsonEncoder.withIndent('  ').convert(await read());

  Future<List<Map<String, dynamic>>> search(String query, {int limit = 8}) async {
    final terms = query.toLowerCase().split(RegExp(r'\s+'))
        .where((s) => s.length > 2).toSet();
    if (terms.isEmpty) return [];
    final data = await read();
    final scored = (data['entries'] as List).cast<Map<String, dynamic>>()
        .map((e) {
          final text = (e['text'] as String).toLowerCase();
          final score = terms.where(text.contains).length;
          return (entry: e, score: score);
        })
        .where((e) => e.score > 0).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).map((e) => e.entry).toList();
  }
}
