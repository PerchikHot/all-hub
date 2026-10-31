import 'dart:convert';
import 'package:all_hub/media_feed_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final url = Uri.https('danbooru.donmai.us', '/posts.json', {
    'tags': 'transgender filetype:gif', 'limit': '40', 'page': '1',
  });

  test('accepts bounded JSON and preserves post metadata', () async {
    final client = MediaFeedClient(client: MockClient((_) async =>
        http.Response(jsonEncode([{'id': 7, 'file_ext': 'gif'}]), 200)));
    expect((await client.fetch(url)).single['id'], 7);
    client.close();
  });

  test('HTTP 403 and 429 are reported, never cached as empty pages', () async {
    for (final status in [403, 429]) {
      var calls = 0;
      final client = MediaFeedClient(client: MockClient((_) async {
        calls++;
        return http.Response('error', status);
      }));
      await expectLater(client.fetch(url),
          throwsA(isA<MediaFeedRequestException>().having(
              (e) => e.statusCode, 'status', status)));
      expect(calls, 1);
      client.close();
    }
  });

  test('transient 5xx retries once, then returns the next valid page', () async {
    var calls = 0;
    final client = MediaFeedClient(client: MockClient((_) async {
      calls++;
      return calls == 1
          ? http.Response('temporary', 503)
          : http.Response('[{"id":42}]', 200);
    }));
    expect((await client.fetch(url)).single['id'], 42);
    expect(calls, 2);
    client.close();
  });

  test('rejects oversized, malformed and non-object responses', () async {
    for (final payload in ['not json', '[1,2]', '[null]',
        List.filled(101, <String, dynamic>{}).toString()]) {
      final client = MediaFeedClient(client: MockClient((_) async =>
          http.Response(payload, 200)));
      await expectLater(client.fetch(url), throwsFormatException);
      client.close();
    }
    final client = MediaFeedClient(maxResponseBytes: 8,
        client: MockClient((_) async => http.Response('[{"id":42}]', 200)));
    await expectLater(client.fetch(url), throwsFormatException);
    client.close();
  });

  test('rejects non-feed URLs and invalid budgets', () async {
    final client = MediaFeedClient(client: MockClient((_) async =>
        http.Response('[]', 200)));
    await expectLater(client.fetch(Uri.parse('https://example.org/posts.json')),
        throwsArgumentError);
    client.close();
    expect(() => MediaFeedClient(maxResponseBytes: 0), throwsArgumentError);
  });
}
