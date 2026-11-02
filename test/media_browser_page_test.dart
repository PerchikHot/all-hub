import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/media_browser_page.dart';

void main() {
  test('media transfer progress is bounded and never fabricated', () {
    expect(mediaTransferProgress(0, 100), 0.0);
    expect(mediaTransferProgress(25, 100), 0.25);
    expect(mediaTransferProgress(150, 100), 1.0);
    expect(mediaTransferProgress(5, null), isNull);
    expect(mediaTransferProgress(5, 0), isNull);
    expect(mediaTransferProgress(-1, 100), isNull);
  });

  test('Windows media downloads reserve unique filenames without overwrite', () async {
    final folder = await Directory.systemTemp.createTemp('allhub-media-test-');
    try {
      final first = await reserveUniqueMediaFile(folder, 'animation.gif');
      await first.writeAsString('original GIF');
      final second = await reserveUniqueMediaFile(folder, 'animation.gif');
      expect(second.uri.pathSegments.last, 'animation (1).gif');
      expect(await first.readAsString(), 'original GIF');
      final third = await reserveUniqueMediaFile(folder, 'animation.gif');
      expect(third.uri.pathSegments.last, 'animation (2).gif');
      await expectLater(reserveUniqueMediaFile(folder, '../escape.gif'),
          throwsA(isA<FormatException>()));
    } finally {
      await folder.delete(recursive: true);
    }
  });

  test('direct GIFs and images use the internal viewer on Android and Windows', () {
    for (final name in ['image.jpg', 'frame.PNG', 'loop.GIF',
      'photo.webp', 'photo.jpeg', 'scan.bmp']) {
      expect(isDirectImageMediaUri(Uri.parse('https://cdn.example/$name?x=1')),
          isTrue, reason: name);
    }
    expect(isDirectImageMediaUri(Uri.parse('https://cdn.example/video.mp4')),
        isFalse);
    expect(isDirectImageMediaUri(Uri.parse('javascript:alert(1)')), isFalse);
    expect(isDirectImageMediaUri(Uri.parse('file:///private/photo.gif')),
        isFalse);
    expect(isDirectImageMediaUri(Uri.parse('https://cdn.example/notgif.gif.exe')),
        isFalse);
  });
}
