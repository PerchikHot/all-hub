import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/media_browser_page.dart';

void main() {
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
