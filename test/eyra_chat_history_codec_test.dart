import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/eyra_chat_history_codec.dart';

void main() {
  test('Forge-only messages have a stable offline key', () {
    expect(EyraChatHistoryCodec.key(null), 'eyra_chat_history_offline');
    expect(EyraChatHistoryCodec.key('qwen'), 'ollama_chat_history_model_qwen');
  });

  test('offline image history survives encode/decode', () {
    final original = <Map<String, String>>[
      {'role': 'user', 'content': 'Нарисуй кота'},
      {'role': 'assistant', 'content': 'Готово', 'imagePath': '/private/1_0.png'},
    ];
    expect(EyraChatHistoryCodec.decode(EyraChatHistoryCodec.encode(original)),
        original);
  });

  test('malformed cache is harmless and unknown roles are ignored', () {
    expect(EyraChatHistoryCodec.decode('{broken'), isEmpty);
    expect(EyraChatHistoryCodec.decode('{"messages":[]}'), isEmpty);
    expect(EyraChatHistoryCodec.decode(
        '[{"role":"system","content":"secret"},'
        '{"role":"assistant","content":"ok","imagePath":123}]'),
        [{'role': 'assistant', 'content': 'ok'}]);
  });

  test('history is capped at the most recent 100 entries', () {
    final history = List.generate(105,
        (i) => <String, String>{'role': 'user', 'content': '$i'});
    final restored = EyraChatHistoryCodec.decode(
        EyraChatHistoryCodec.encode(history));
    expect(restored, hasLength(100));
    expect(restored.first['content'], '5');
    expect(restored.last['content'], '104');
  });
}
