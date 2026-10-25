import 'dart:io';
import 'dart:typed_data';

import 'package:all_hub/gguf_header.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('all_hub_gguf_test_');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Future<String> writeHeader({
    int version = 3,
    int tensors = 2,
    int metadata = 5,
    bool validMagic = true,
    int length = 24,
  }) async {
    final bytes = Uint8List(length);
    if (length >= 24) {
      bytes.setRange(0, 4, validMagic ? [71, 71, 85, 70] : [0, 0, 0, 0]);
      final view = ByteData.sublistView(bytes);
      view.setUint32(4, version, Endian.little);
      view.setUint64(8, tensors, Endian.little);
      view.setUint64(16, metadata, Endian.little);
    }
    final file = File('${directory.path}/model.gguf');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  test('reads supported GGUF v3 header', () async {
    final header = await GgufHeader.read(await writeHeader());
    expect(header, isNotNull);
    expect(header!.version, 3);
    expect(header.tensorCount, 2);
    expect(header.metadataCount, 5);
    expect(header.bytes, 24);
  });

  test('accepts supported GGUF v2', () async {
    expect((await GgufHeader.read(await writeHeader(version: 2)))?.version, 2);
  });

  test('rejects malformed and unsupported headers', () async {
    expect(await GgufHeader.read(await writeHeader(length: 8)), isNull);
    expect(await GgufHeader.read(await writeHeader(validMagic: false)), isNull);
    expect(await GgufHeader.read(await writeHeader(version: 4)), isNull);
    expect(await GgufHeader.read(await writeHeader(tensors: 0)), isNull);
    expect(await GgufHeader.read(await writeHeader(metadata: 1000001)), isNull);
  });

  test('missing file returns null', () async {
    expect(await GgufHeader.read('${directory.path}/missing.gguf'), isNull);
  });
}
