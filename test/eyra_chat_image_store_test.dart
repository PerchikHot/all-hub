import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/eyra_chat_image_store.dart';

void main() {
  late Directory root;
  late EyraChatImageStore store;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('eyra-images-');
    store = EyraChatImageStore(Directory('${root.path}/images'));
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });
  test('stores and restores a PNG in private storage', () async {
    final bytes = Uint8List.fromList([137,80,78,71,13,10,26,10,1,2,3]);
    final path = await store.save(bytes);
    expect(store.owns(path), isTrue);
    expect(await File(path).readAsBytes(), bytes);
    await store.delete(path);
    expect(await File(path).exists(), isFalse);
  });
  test('rejects invalid image without writing a file', () async {
    expect(() => store.save(Uint8List.fromList([1,2,3])), throwsFormatException);
  });
  test('cannot delete external files or traversed paths', () async {
    final external = File('${root.path}/important.txt');
    await external.writeAsString('keep');
    expect(store.owns(external.path), isFalse);
    expect(store.owns('${root.path}/images/../important.txt'), isFalse);
    await store.delete(external.path);
    expect(await external.readAsString(), 'keep');
  });
  test('only store-generated top-level image names are owned', () async {
    final image = await store.save(Uint8List.fromList(
        [137,80,78,71,13,10,26,10,1,2,3]));
    expect(store.owns(image), isTrue);
    expect(store.owns('${root.path}/images/manual.png'), isFalse);
    expect(store.owns('${root.path}/images/nested/123_0.png'), isFalse);
    expect(store.owns('${root.path}/images/../images/manual.png'), isFalse);
    expect(store.owns(''), isFalse);
  });

  test('cannot delete a symbolic link to a file outside private storage', () async {
    final external = File('${root.path}/important.png');
    await external.writeAsString('keep');
    await store.save(Uint8List.fromList([137,80,78,71,13,10,26,10,1]));
    final link = Link('${root.path}/images/123_0.png');
    try {
      await link.create(external.path);
    } on FileSystemException {
      // Creating symlinks can require privileges on Windows runners.
      return;
    }
    expect(store.owns(link.path), isTrue);
    await store.delete(link.path);
    expect(await external.readAsString(), 'keep');
    expect(await link.exists(), isTrue);
  });

}
