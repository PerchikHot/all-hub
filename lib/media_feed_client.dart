import 'dart:convert';
import 'package:http/http.dart' as http;

/// A bounded reader for the public media feed. A CDN error or malformed
/// response must never consume unlimited memory or poison the page cache.
class MediaFeedRequestException implements Exception {
  const MediaFeedRequestException(this.statusCode);
  final int statusCode;

  @override
  String toString() => 'Media feed HTTP $statusCode';
}

class MediaFeedClient {
  MediaFeedClient({
    http.Client? client,
    this.maxResponseBytes = 2 * 1024 * 1024,
    this.maxAttempts = 2,
  }) : _client = client ?? http.Client() {
    if (maxResponseBytes < 1 || maxAttempts < 1 || maxAttempts > 3) {
      throw ArgumentError('Invalid feed request budget');
    }
  }

  final http.Client _client;
  final int maxResponseBytes;
  final int maxAttempts;

  Future<List<Map<String, dynamic>>> fetch(Uri uri) async {
    // Do not allow a future caller to use this HTTP client as an arbitrary
    // authenticated proxy. This feed only needs one public JSON endpoint.
    if (uri.scheme != 'https' || uri.host != 'danbooru.donmai.us' ||
        uri.path != '/posts.json' || uri.userInfo.isNotEmpty ||
        uri.hasFragment || uri.hasPort) {
      throw ArgumentError('Unsupported media feed endpoint');
    }
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final response = await _client.send(http.Request('GET', uri))
          .timeout(const Duration(seconds: 18));
      if (response.statusCode >= 500 && attempt + 1 < maxAttempts) {
        await response.stream.drain<void>();
        await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
        continue;
      }
      if (response.statusCode != 200) {
        throw MediaFeedRequestException(response.statusCode);
      }
      if (response.contentLength != null &&
          response.contentLength! > maxResponseBytes) {
        throw const FormatException('Feed response exceeds size limit');
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
          const Duration(seconds: 18))) {
        if (chunk.length > maxResponseBytes - bytes.length) {
          throw const FormatException('Feed response exceeds size limit');
        }
        bytes.addAll(chunk);
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! List || decoded.length > 100 ||
          decoded.any((item) => item is! Map<String, dynamic>)) {
        throw const FormatException('Invalid media feed JSON');
      }
      return decoded.cast<Map<String, dynamic>>();
    }
    throw StateError('Feed retries exhausted');
  }

  void close() => _client.close();
}
