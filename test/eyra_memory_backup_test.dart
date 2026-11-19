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
}
