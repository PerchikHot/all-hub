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
    DateTime Function()? clock,
  }) : _client = client ?? http.Client(),
       _wait = wait ?? ((duration) => Future<void>.delayed(duration)),
       _clock = clock ?? DateTime.now {
    if (maxResponseBytes < 1 || maxAttempts < 1 || maxAttempts > 3) {
      throw ArgumentError('Invalid feed request budget');
    }
  }

  final http.Client _client;
  final int maxResponseBytes;
  final int maxAttempts;
  final Future<void> Function(Duration) _wait;
  final DateTime Function() _clock;
  DateTime? _rateLimitUntil;
  int? _rateLimitStatus;

  Future<List<Map<String, dynamic>>> fetch(Uri uri) async {
    // Do not allow a future caller to use this HTTP client as an arbitrary
    // authenticated proxy. This feed only needs one public JSON endpoint.
    if (uri.scheme != 'https' || uri.host != 'danbooru.donmai.us' ||
        uri.path != '/posts.json' || uri.userInfo.isNotEmpty ||
        uri.hasFragment || uri.hasPort) {
      throw ArgumentError('Unsupported media feed endpoint');
    }
    // The provider's rate limit applies across pages. While cooling down,
    // return a clear error immediately so the UI can show its cached GIFs
    // instead of sending another request for every scroll or filter change.
    final until = _rateLimitUntil;
    if (until != null && _clock().isBefore(until)) {
      throw MediaFeedRequestException(_rateLimitStatus ?? 429);
    }
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        // A timeout while reading the body is as recoverable as a timeout
        // while connecting. Retry the same page without caching a partial JSON.
        // The source is public, but redirects can leak search tags to
        // unrelated domains and return an unrelated page as feed JSON.
        final request = http.Request('GET', uri)
          ..followRedirects = false
          // Public API providers can reject generic Dart clients as bots.
          // Identify this app, request JSON only, and never attach credentials.
          ..headers['User-Agent'] = 'AllHub/0.7.8 (public media browser; github.com/PerchikHot/all-hub)'
          ..headers['Accept'] = 'application/json';
        final response = await _client.send(request)
            .timeout(const Duration(seconds: 18));
        if (response.statusCode >= 500 && attempt + 1 < maxAttempts) {
          // Do not leave an unread response attached to the connection.
          await response.stream.drain<void>()
              .timeout(const Duration(seconds: 5));
          await _wait(Duration(milliseconds: 250 * (attempt + 1)));
          continue;
        }
        if (response.statusCode != 200) {
          // Stop consuming a rejected response instead of leaving its stream
          // attached to a pooled connection. Never decode an HTML error page.
          try {
            await response.stream.drain<void>()
                .timeout(const Duration(seconds: 2));
          } catch (_) {
            // Preserve the HTTP status, not a secondary drain error.
          }
          // Retry-After supports both delta-seconds and RFC 7231 HTTP dates.
          // Bound even an extreme future date to two minutes.
          if (response.statusCode == 429 || response.statusCode == 403) {
            final raw = response.headers['retry-after']?.trim() ?? '';
            var seconds = int.tryParse(raw);
            if (seconds == null && raw.isNotEmpty) {
              try {
                seconds = HttpDate.parse(raw).difference(_clock()).inSeconds;
              } on FormatException {
                // Malformed headers use the safe default cooldown.
              } on HttpException {
                // HttpDate.parse may report an invalid HTTP date this way.
              }
            }
            final delay = response.statusCode == 403 ? 60 :
                (seconds == null ? 30 : seconds.clamp(1, 120).toInt());
            _rateLimitUntil = _clock().add(Duration(seconds: delay));
            _rateLimitStatus = response.statusCode;
          }
          throw MediaFeedRequestException(response.statusCode);
        }
        _rateLimitUntil = null;
        _rateLimitStatus = null;
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
