import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/eyra_memory_backup.dart';

void main() {
  test('portable memory round-trip preserves Russian text', () {
    final original = EyraMemoryBackup(
      personality: 'Говори по-русски',
      notes: ['Люблю краткие ответы'],
      excerpts: ['История разговора'],
      exportedAt: DateTime.utc(2026, 11, 19),
    );
    final restored = EyraMemoryBackup.decode(original.encode());
    expect(restored.personality, original.personality);
    expect(restored.notes, original.notes);
    expect(restored.excerpts, original.excerpts);
    expect(restored.exportedAt, original.exportedAt);
  });

  test('rejects unsupported backup versions', () {
    expect(() => EyraMemoryBackup.decode(
      '{"format":"all-hub-eyra-memory","version":2}'),
      throwsFormatException);
  });

  test('rejects oversized or malformed records', () {
    final backup = EyraMemoryBackup(
      personality: '', notes: ['ok'], excerpts: [],
      exportedAt: DateTime.utc(2026),
    ).encode();
    expect(() => EyraMemoryBackup.decode(
      backup.replaceFirst('"notes": [', '"notes": ["${'x' * 501}",')),
      throwsFormatException);
    expect(() => EyraMemoryBackup.decode('x' * (4 * 1024 * 1024 + 1)),
      throwsFormatException);
  });
  test('merge preserves local character, deduplicates and keeps order', () {
    final local = EyraMemoryBackup(
      personality: 'Мой характер', notes: ['А', 'Б'],
      excerpts: ['Первый', 'Повтор'],
      exportedAt: DateTime.utc(2026),
    );
    final incoming = EyraMemoryBackup(
      personality: 'Чужой характер', notes: ['Б', 'В'],
      excerpts: ['Повтор', 'Новый'],
      exportedAt: DateTime.utc(2026, 11),
    );
    final merged = local.mergeWith(incoming);
    expect(merged.personality, 'Мой характер');
    expect(merged.notes, ['А', 'Б', 'В']);
    expect(merged.excerpts, ['Первый', 'Повтор', 'Новый']);
    expect(EyraMemoryBackup.decode(merged.encode()).notes, merged.notes);
    expect(local.notes, ['А', 'Б']);
    expect(local.mergeWith(incoming, useImportedPersonality: true).personality,
      'Чужой характер');
  });

  test('merge rejects overflow without mutating local records', () {
    final local = EyraMemoryBackup(
      personality: '', notes: List.generate(100, (i) => 'n$i'),
      excerpts: [], exportedAt: DateTime.utc(2026),
    );
    final incoming = EyraMemoryBackup(
      personality: '', notes: ['new'], excerpts: [],
      exportedAt: DateTime.utc(2026),
    );
    expect(() => local.mergeWith(incoming), throwsFormatException);
    expect(local.notes.length, 100);
    expect(local.notes.last, 'n99');
  });

}
