import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/eyra_duplicate_scan.dart';

void main() {
  late Directory dir;
  setUp(() async { dir = await Directory.systemTemp.createTemp('eyra_dupes_'); });
  tearDown(() async { await dir.delete(recursive: true); });

  test('finds equal content and never changes source files', () async {
    final a = File('${dir.path}/a.txt')..writeAsStringSync('same');
    final b = File('${dir.path}/b.txt')..writeAsStringSync('same');
    final c = File('${dir.path}/c.txt')..writeAsStringSync('different');
    final result = await EyraDuplicateScan.scan([a, b, c]);
    expect(result, hasLength(1));
    expect(result.single.names, containsAll(['a.txt', 'b.txt']));
    expect(result.single.bytes, 4);
    expect(a.readAsStringSync(), 'same');
    expect(b.existsSync(), isTrue);
  });

  test('rejects duplicate selection', () async {
    final a = File('${dir.path}/a')..writeAsStringSync('x');
    await expectLater(EyraDuplicateScan.scan([a, a]), throwsFormatException);
  });

  test('stops when consent is revoked', () async {
    final a = File('${dir.path}/a')..writeAsStringSync('x');
    final b = File('${dir.path}/b')..writeAsStringSync('x');
    var checks = 0;
    await expectLater(
      EyraDuplicateScan.scan([a, b], stillAllowed: () async => ++checks < 2),
      throwsFormatException,
    );
  });

  test('rejects excessive selection', () async {
    final a = File('${dir.path}/a')..writeAsStringSync('x');
    await expectLater(EyraDuplicateScan.scan([a]), throwsFormatException);
  });
}
