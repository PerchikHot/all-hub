import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/external_artwork.dart';

void main() {
  test('local repository banners accept only matching image signatures', () {
    expect(ExternalArtwork.validImageHeader(
      [137, 80, 78, 71, 13, 10, 26, 10], 'png'), isTrue);
    expect(ExternalArtwork.validImageHeader([255, 216, 255, 0], 'jpg'), isTrue);
    expect(ExternalArtwork.validImageHeader(
      [71, 73, 70, 56, 57, 97], 'gif'), isTrue);
    expect(ExternalArtwork.validImageHeader(
      [82, 73, 70, 70, 0, 0, 0, 0, 87, 69, 66, 80], 'webp'), isTrue);
    expect(ExternalArtwork.validImageHeader(
      [255, 216, 255], 'png'), isFalse);
    expect(ExternalArtwork.validImageHeader(
      [137, 80, 78, 71, 13, 10, 26, 10], 'exe'), isFalse);
    expect(ExternalArtwork.validImageHeader([], 'jpg'), isFalse);
  });
}
