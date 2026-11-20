import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/eyra_chat_backup.dart';

void main() {
  test('portable backup roundtrips Cyrillic and excludes local image paths', () {
    final data = EyraChatBackup.encode([
      {'role': 'user', 'content': 'Привет'},
      {'role': 'assistant', 'content': 'Готово', 'imagePath': '/private/photo.png'},
    ], DateTime.utc(2026, 11, 20));
    expect(data, isNot(contains('/private/photo.png')));
    expect(EyraChatBackup.decode(data), [
      {'role': 'user', 'content': 'Привет'},
      {'role': 'assistant', 'content': 'Готово'},
    ]);
  });

  test('rejects unknown format, malformed roles, and oversized imports', () {
    expect(() => EyraChatBackup.decode('{}'), throwsFormatException);
    expect(() => EyraChatBackup.decode(
      '{"format":"eyra-chat-text","version":1,"messages":[{"role":"system","content":"x"}]}'),
      throwsFormatException);
    expect(() => EyraChatBackup.decode('x' * (EyraChatBackup.maxBytes + 1)),
      throwsFormatException);
  });

  test('rejects more than 100 messages and excessively long text', () {
    final many = '{"format":"eyra-chat-text","version":1,"messages":['
      '${List.filled(101, '{"role":"user","content":"x"}').join(',')}]}';
    expect(() => EyraChatBackup.decode(many), throwsFormatException);
    expect(() => EyraChatBackup.encode([
      {'role': 'user', 'content': 'x' * 13000},
    ], DateTime.utc(2026)), returnsNormally);
  });
}
