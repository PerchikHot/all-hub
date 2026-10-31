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

  test('remote filenames are sanitized and bounded', () {
    expect(mediaDownloadFileName(Uri.parse('https://cdn.example/%3Cbad%3E.gif'),
        'image/gif'), '_bad_.gif');
    final longName = 'a' * 250;
    final name = mediaDownloadFileName(
        Uri.parse('https://cdn.example/$longName.jpg'), 'image/jpeg');
    expect(name, isNotNull);
    expect(name!.length, lessThanOrEqualTo(84));
  });
}
