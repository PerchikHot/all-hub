import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/eyra_chat_backup.dart';

void main() {
  test('GGUF text history is portable to Ollama and back', () {
    final source = <Map<String, String>>[
      {'role': 'user', 'content': 'Привет, Эйра'},
      {'role': 'assistant', 'content': 'Привет!'},
    ];
    final encoded = EyraChatBackup.encode(source, DateTime.utc(2026, 11, 20));
    expect(EyraChatBackup.decode(encoded), source);
  });

  test('backup rejects unexpected formats and oversized messages', () {
    expect(() => EyraChatBackup.decode('{"messages":[]}'), throwsFormatException);
    expect(() => EyraChatBackup.decode('x' * (EyraChatBackup.maxBytes + 1)),
      throwsFormatException);
    expect(() => EyraChatBackup.decode(EyraChatBackup.encode([
      {'role': 'user', 'content': 'ok'}
    ], DateTime.utc(2026))), isNotEmpty);
  });

  test('backup keeps last 100 messages without private file paths', () {
    final source = List.generate(105, (i) => <String, String>{
      'role': i.isEven ? 'user' : 'assistant', 'content': 'Message $i',
      'imagePath': '/private/photo.png',
    });
    final json = EyraChatBackup.encode(source, DateTime.utc(2026));
    final restored = EyraChatBackup.decode(json);
    expect(restored.length, 100);
    expect(restored.first['content'], 'Message 5');
    expect(json.contains('/private/photo.png'), isFalse);
  });
}
