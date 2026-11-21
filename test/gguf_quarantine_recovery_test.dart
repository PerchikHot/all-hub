import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/gguf_quarantine_recovery.dart';

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('gguf-recover-'));
  tearDown(() async => dir.delete(recursive: true));

  test('restores registered model after interrupted removal', () async {
    final original = File('${dir.path}/model.gguf');
    final quarantined = File('${original.path}.deleting-123');
    await quarantined.writeAsBytes([1, 2, 3]);
    expect(await recoverQuarantinedGguf(dir, [original.path]), 1);
    expect(await original.readAsBytes(), [1, 2, 3]);
    expect(await quarantined.exists(), false);
  });

  test('does not destroy unregistered quarantine', () async {
    final quarantined = File('${dir.path}/model.gguf.deleting-123');
    await quarantined.writeAsBytes([1]);
    expect(await recoverQuarantinedGguf(dir, []), 0);
    expect(await quarantined.exists(), true);
  });

  test('never overwrites an existing model', () async {
    final original = File('${dir.path}/model.gguf');
    final quarantined = File('${original.path}.deleting-123');
    await original.writeAsBytes([7]);
    await quarantined.writeAsBytes([8]);
    expect(await recoverQuarantinedGguf(dir, [original.path]), 0);
    expect(await original.readAsBytes(), [7]);
    expect(await quarantined.readAsBytes(), [8]);
  });

  test('ignores unrelated files', () async {
    final unrelated = File('${dir.path}/notes.txt.deleting-123');
    await unrelated.writeAsString('keep');
    expect(await recoverQuarantinedGguf(dir, [unrelated.path]), 0);
    expect(await unrelated.exists(), true);
  });
}
