import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
    Future<void> Function(Duration)? wait,
  }) : _client = client ?? http.Client(),
       _wait = wait ?? ((duration) => Future<void>.delayed(duration)) {
    if (maxResponseBytes < 1 || maxAttempts < 1 || maxAttempts > 3) {
      throw ArgumentError('Invalid feed request budget');
    }
  }

  final http.Client _client;
  final int maxResponseBytes;
  final int maxAttempts;
  final Future<void> Function(Duration) _wait;

  Future<List<Map<String, dynamic>>> fetch(Uri uri) async {
    // Do not allow a future caller to use this HTTP client as an arbitrary
    // authenticated proxy. This feed only needs one public JSON endpoint.
    if (uri.scheme != 'https' || uri.host != 'danbooru.donmai.us' ||
        uri.path != '/posts.json' || uri.userInfo.isNotEmpty ||
        uri.hasFragment || uri.hasPort) {
      throw ArgumentError('Unsupported media feed endpoint');
    }
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        // A timeout while reading the body is as recoverable as a timeout
        // while connecting. Retry the same page without caching a partial JSON.
        final response = await _client.send(http.Request('GET', uri))
            .timeout(const Duration(seconds: 18));
        if (response.statusCode >= 500 && attempt + 1 < maxAttempts) {
          // Do not leave an unread response attached to the connection.
          await response.stream.drain<void>()
              .timeout(const Duration(seconds: 5));
          await _wait(Duration(milliseconds: 250 * (attempt + 1)));
          continue;
        }
        if (response.statusCode != 200) {
          // In particular, do not hammer the source when it returns 429.
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
      } catch (error) {
        // Network failures should not permanently blank the Pinterest feed.
        // Invalid JSON, HTTP 403/429 and oversized bodies are not retried.
        final transient = error is TimeoutException ||
            error is SocketException || error is http.ClientException;
        if (!transient || attempt + 1 == maxAttempts) rethrow;
        await _wait(Duration(milliseconds: 250 * (attempt + 1)));
      }
    }
    throw StateError('Feed retries exhausted');
  }

  void close() => _client.close();
}
