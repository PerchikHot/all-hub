import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/external_screenshots.dart';

void main() {
  test('screenshots accept matching signatures and reject oversized files', () {
    final png = [137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 0];
    expect(ExternalScreenshots.acceptsHeader(png, 'png', 1024), isTrue);
    expect(ExternalScreenshots.acceptsHeader(png, 'jpg', 1024), isFalse);
    expect(ExternalScreenshots.acceptsHeader(png, 'png', 11), isFalse);
    expect(ExternalScreenshots.acceptsHeader(
      png, 'png', ExternalScreenshots.maxBytes + 1), isFalse);
    expect(ExternalScreenshots.acceptsHeader(
      [71, 73, 70, 56, 57, 97, 0, 0, 0, 0, 0, 0], 'gif', 200), isTrue);
    expect(ExternalScreenshots.acceptsHeader(
      [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], 'webp', 200), isFalse);
  });
}
