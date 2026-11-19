import 'dart:convert';

/// Versioned, portable, local-only Eyra settings and memory snapshot.
/// Never includes credentials, device permissions, or remote endpoints.
class EyraMemoryBackup {
  final String personality;
  final List<String> notes;
  final List<String> excerpts;
  final DateTime exportedAt;

  const EyraMemoryBackup({
    required this.personality,
    required this.notes,
    required this.excerpts,
    required this.exportedAt,
  });


  /// Merge a portable snapshot without silently deleting local knowledge.
  /// Existing records retain their order; imported duplicates are ignored.
  /// Throws before writing anything if the combined storage limit is exceeded.
  EyraMemoryBackup mergeWith(EyraMemoryBackup incoming, {bool useImportedPersonality = false}) {
    List<String> combine(List<String> current, List<String> added, int limit) {
      final merged = <String>[...current];
      final seen = current.toSet();
      for (final entry in added) {
        if (seen.add(entry)) merged.add(entry);
      }
      if (merged.length > limit) {
        throw FormatException('Недостаточно места: максимум $limit записей. Удалите ненужные записи перед объединением.');
      }
      return merged;
    }
    return EyraMemoryBackup(
      personality: useImportedPersonality ? incoming.personality : personality,
      notes: combine(notes, incoming.notes, 100),
      excerpts: combine(excerpts, incoming.excerpts, 1000),
      exportedAt: DateTime.now().toUtc(),
    );
  }

  String encode() => const JsonEncoder.withIndent('  ').convert({
    'format': 'all-hub-eyra-memory',
    'version': 1,
    'exported_at': exportedAt.toUtc().toIso8601String(),
    'personality': personality,
    'notes': notes,
    'excerpts': excerpts,
  });

  static EyraMemoryBackup decode(String source) {
    if (source.length > 4 * 1024 * 1024) {
      throw const FormatException('Файл памяти больше 4 МБ');
    }
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != 'all-hub-eyra-memory' ||
        decoded['version'] != 1) {
      throw const FormatException('Неизвестный формат или версия резервной копии');
    }
    final personality = decoded['personality'];
    if (personality is! String || personality.length > 4000) {
      throw const FormatException('Некорректные настройки характера');
    }
    List<String> validate(dynamic value, int count, int length) {
      if (value is! List || value.length > count ||
          value.any((e) => e is! String || e.length > length)) {
        throw const FormatException('Некорректные записи памяти');
      }
      return List<String>.from(value);
    }
    final date = DateTime.tryParse(decoded['exported_at']?.toString() ?? '');
    if (date == null) throw const FormatException('Отсутствует дата резервной копии');
    return EyraMemoryBackup(
      personality: personality,
      notes: validate(decoded['notes'], 100, 500),
      excerpts: validate(decoded['excerpts'], 1000, 3000),
      exportedAt: date,
    );
  }
}
