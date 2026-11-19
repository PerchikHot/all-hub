import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/eyra_file_inspector.dart';

void main() {
  test('selected file is hashed without modification', () async {
    final dir = await Directory.systemTemp.createTemp('eyra-inspect-');
    try {
      final file = File('${dir.path}/sample.txt');
      await file.writeAsString('abc');
      final result = await EyraFileInspector.inspect(file);
      expect(result.bytes, 3);
      expect(result.sha256,
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      expect(await file.readAsString(), 'abc');
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('directories are rejected', () async {
    final dir = await Directory.systemTemp.createTemp('eyra-inspect-');
    try {
      await expectLater(EyraFileInspector.inspect(File(dir.path)),
          throwsA(isA<FormatException>()));
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('missing files fail without creating anything', () async {
    final dir = await Directory.systemTemp.createTemp('eyra-inspect-');
    try {
      final missing = File('${dir.path}/missing');
      await expectLater(EyraFileInspector.inspect(missing), throwsA(isA<FormatException>()));
      expect(await missing.exists(), false);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
