import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/media_download_policy.dart';

void main() {
  test('response MIME overrides misleading or absent file extension', () {
    expect(mediaDownloadFileName(Uri.parse('https://cdn.example/loop.jpg'),
        'image/gif; charset=binary'), 'loop.gif');
    expect(mediaDownloadFileName(Uri.parse('https://cdn.example/file'),
        'video/mp4'), 'file.mp4');
    expect(mediaDownloadFileName(Uri.parse('https://cdn.example/photo.webp'),
        'image/jpeg'), 'photo.jpg');
  });

  test('unknown downloads are rejected rather than saved as executable blobs', () {
    expect(mediaDownloadFileName(Uri.parse('https://cdn.example/tool.exe'),
        'application/octet-stream'), isNull);
    expect(mediaDownloadFileName(Uri.parse('https://cdn.example/a.jpg'),
        'text/html'), isNull);
    expect(mediaDownloadFileName(Uri.parse('https://cdn.example/a.gif'),
        'application/octet-stream'), 'a.gif');
    expect(mediaDownloadFileName(Uri.parse('file:///secret/a.gif'),
        'image/gif'), isNull);
  });

  test('incomplete media responses are rejected before publishing', () {
    expect(isCompleteMediaDownload(4096, 4096), isTrue);
    expect(isCompleteMediaDownload(4095, 4096), isFalse);
    expect(isCompleteMediaDownload(4097, 4096), isFalse);
    expect(isCompleteMediaDownload(4096, null), isTrue);
    expect(isCompleteMediaDownload(-1, null), isFalse);
    expect(isCompleteMediaDownload(100, -1), isFalse);
  });

  test('remote filenames are sanitized and bounded', () {
    expect(mediaDownloadFileName(Uri.parse('https://cdn.example/%3Cbad%3E.gif'),
        'image/gif'), '_bad_.gif');
    final longName = 'a' * 250;
    final name = mediaDownloadFileName(
        Uri.parse('https://cdn.example/$longName.jpg'), 'image/jpeg');
    expect(name, isNotNull);
    expect(name!.length, lessThanOrEqualTo(84));
  });
  test('downloaded media must match its actual binary format', () {
    expect(hasMediaFileSignature('loop.gif', [71, 73, 70, 56, 57, 97]), isTrue);
    expect(hasMediaFileSignature('loop.gif', [71, 73, 70, 56, 55, 97]), isTrue);
    expect(hasMediaFileSignature('photo.jpg', [0xff, 0xd8, 0xff]), isTrue);
    expect(hasMediaFileSignature('photo.png',
        [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), isTrue);
    expect(hasMediaFileSignature('photo.webp',
        [82, 73, 70, 70, 0, 0, 0, 0, 87, 69, 66, 80]), isTrue);
    expect(hasMediaFileSignature('clip.mp4',
        [0, 0, 0, 24, 102, 116, 121, 112]), isTrue);
    expect(hasMediaFileSignature('clip.webm', [0x1a, 0x45, 0xdf, 0xa3]), isTrue);
    expect(hasMediaFileSignature('clip.mov',
        [0, 0, 0, 24, 109, 111, 111, 118]), isTrue);
    for (final name in ['photo.jpg', 'loop.gif', 'clip.mp4', 'clip.webm']) {
      expect(hasMediaFileSignature(name, '<html>blocked</html>'.codeUnits), isFalse);
      expect(hasMediaFileSignature(name, []), isFalse);
    }
    expect(hasMediaFileSignature('photo.gif', [0xff, 0xd8, 0xff]), isFalse);
  });

}
