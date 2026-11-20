import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/gguf_import_integrity.dart';

void main() {
  test('picker paths cannot escape the model directory', () {
    expect(safeGgufFilename(r'..\\folder\\qwen.gguf'), 'qwen.gguf');
    expect(safeGgufFilename('../../model.gguf'), 'model.gguf');
    expect(safeGgufFilename('Qwen 4B.gguf'), 'Qwen_4B.gguf');
    expect(() => safeGgufFilename('../.gguf'), throwsFormatException);
    expect(() => safeGgufFilename('model.zip'), throwsFormatException);
  });

  test('streaming copy verification detects equal-length corruption', () async {
    final dir = await Directory.systemTemp.createTemp('allhub-gguf-test-');
    try {
      final source = File('${dir.path}/source.gguf');
      final copy = File('${dir.path}/copy.gguf');
      await source.writeAsBytes([0x47, 0x47, 0x55, 0x46, 1, 2, 3, 4]);
      await copy.writeAsBytes(await source.readAsBytes());
      expect(await ggufCopiesMatch(source, copy), isTrue);
      await copy.writeAsBytes([0x47, 0x47, 0x55, 0x46, 1, 2, 3, 5]);
      expect(await ggufCopiesMatch(source, copy), isFalse);
      await copy.delete();
      expect(await ggufCopiesMatch(source, copy), isFalse);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
