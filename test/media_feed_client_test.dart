import 'dart:async';
import 'dart:convert';
import 'package:all_hub/media_feed_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final url = Uri.https('danbooru.donmai.us', '/posts.json', {
    'tags': 'transgender filetype:gif', 'limit': '40', 'page': '1',
  });

  test('concurrent identical feed pages share one request, then can refresh', () async {
    var calls = 0;
    final gate = Completer<http.Response>();
    final client = MediaFeedClient(client: MockClient((_) {
      calls++;
      if (calls == 1) return gate.future;
      return Future.value(http.Response('[{"id":22}]', 200));
    }));
    final first = client.fetch(url);
    final second = client.fetch(url);
    expect(identical(first, second), isTrue);
    gate.complete(http.Response('[{"id":21}]', 200));
    expect((await first).single['id'], 21);
    expect((await second).single['id'], 21);
    await Future<void>.delayed(Duration.zero);
    expect((await client.fetch(url)).single['id'], 22);
    expect(calls, 2);
    client.close();
  });

  test('failed coalesced request is evicted for the next attempt', () async {
    var calls = 0;
    final client = MediaFeedClient(client: MockClient((_) async {
      calls++;
      return calls == 1 ? http.Response('forbidden', 403)
          : http.Response('[{"id":23}]', 200);
    }), clock: () => DateTime.utc(2026, 11, 2));
    final first = client.fetch(url);
    final second = client.fetch(url);
    await expectLater(first, throwsA(isA<MediaFeedRequestException>()));
    await expectLater(second, throwsA(isA<MediaFeedRequestException>()));
    // A cooldown still protects the provider, even though the failed
    // in-flight future itself is no longer retained.
    await expectLater(client.fetch(url), throwsA(isA<MediaFeedRequestException>()));
    expect(calls, 1);
    client.close();
  });

  test('accepts bounded JSON and preserves post metadata', () async {
    final client = MediaFeedClient(client: MockClient((_) async =>
        http.Response(jsonEncode([{'id': 7, 'file_ext': 'gif'}]), 200)));
    expect((await client.fetch(url)).single['id'], 7);
    client.close();
  });

  test('does not follow CDN redirects or leak media search tags', () async {
    var calls = 0;
    final client = MediaFeedClient(client: MockClient((request) async {
      calls++;
      expect(request.followRedirects, isFalse);
      expect(request.headers['User-Agent'], contains('AllHub/'));
      expect(request.headers['Accept'], 'application/json');
      expect(request.headers.containsKey('Authorization'), isFalse);
      expect(request.url.host, 'danbooru.donmai.us');
      return http.Response('', 302, headers: {
        'location': 'https://untrusted.example/collect',
      });
    }));
    await expectLater(client.fetch(url),
        throwsA(isA<MediaFeedRequestException>().having(
            (e) => e.statusCode, 'status', 302)));
    expect(calls, 1);
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

  test('HTTP 503 Retry-After stops retries and cools down feed requests', () async {
    var now = DateTime.utc(2026, 11, 2);
    var calls = 0;
    final client = MediaFeedClient(
      clock: () => now,
      client: MockClient((_) async {
        calls++;
        return calls == 1
            ? http.Response('maintenance', 503, headers: {'retry-after': '45'})
            : http.Response('[{"id":51}]', 200);
      }),
    );
    await expectLater(client.fetch(url), throwsA(isA<MediaFeedRequestException>()
        .having((e) => e.statusCode, 'status', 503)));
    await expectLater(client.fetch(url), throwsA(isA<MediaFeedRequestException>()));
    expect(calls, 1, reason: 'Do not hammer a provider during maintenance');
    now = now.add(const Duration(seconds: 46));
    expect((await client.fetch(url)).single['id'], 51);
    expect(calls, 2);
    client.close();
  });

  test('temporary connection failure retries without caching a blank page', () async {
    var calls = 0;
    final delays = <Duration>[];
    final client = MediaFeedClient(
      wait: (delay) async { delays.add(delay); },
      client: MockClient((_) async {
        calls++;
        if (calls == 1) throw http.ClientException('temporary disconnect');
        return http.Response('[{"id":19,"file_ext":"gif"}]', 200);
      }),
    );
    expect((await client.fetch(url)).single['id'], 19);
    expect(calls, 2);
    expect(delays, [const Duration(milliseconds: 250)]);
    client.close();
  });

  test('timeout retries, but repeated timeouts eventually surface', () async {
    var calls = 0;
    final client = MediaFeedClient(
      wait: (_) async {},
      client: MockClient((_) async {
        calls++;
        throw TimeoutException('offline');
      }),
    );
    await expectLater(client.fetch(url), throwsA(isA<TimeoutException>()));
    expect(calls, 2);
    client.close();
  });

  test('rate-limit cooldown avoids repeated requests while scrolling', () async {
    var now = DateTime.utc(2026, 11, 1);
    var calls = 0;
    final client = MediaFeedClient(
      clock: () => now,
      client: MockClient((_) async {
        calls++;
        if (calls == 1) {
          return http.Response('limited', 429, headers: {'retry-after': '90'});
        }
        return http.Response('[{"id":9}]', 200);
      }),
    );
    await expectLater(client.fetch(url), throwsA(isA<MediaFeedRequestException>()));
    await expectLater(client.fetch(url.replace(queryParameters: {'page': '2'})),
        throwsA(isA<MediaFeedRequestException>()));
    expect(calls, 1, reason: 'Do not hammer a rate-limited media API');
    now = now.add(const Duration(seconds: 91));
    expect((await client.fetch(url)).single['id'], 9);
    expect(calls, 2);
    client.close();
  });

  test('HTTP-date Retry-After cools down the entire media feed', () async {
    var now = DateTime.utc(2026, 11, 2, 1, 0, 0);
    var calls = 0;
    final client = MediaFeedClient(
      clock: () => now,
      client: MockClient((_) async {
        calls++;
        return calls == 1
            ? http.Response('slow down', 429, headers: {
                'retry-after': 'Mon, 02 Nov 2026 01:01:30 GMT',
              })
            : http.Response('[{"id":27}]', 200);
      }),
    );
    await expectLater(client.fetch(url), throwsA(isA<MediaFeedRequestException>()));
    now = now.add(const Duration(seconds: 89));
    await expectLater(client.fetch(url), throwsA(isA<MediaFeedRequestException>()));
    expect(calls, 1);
    now = now.add(const Duration(seconds: 2));
    expect((await client.fetch(url)).single['id'], 27);
    expect(calls, 2);
    client.close();
  });

  test('HTTP 429 is not retried even when more attempts are allowed', () async {
    var calls = 0;
    final client = MediaFeedClient(maxAttempts: 3,
      wait: (_) async {},
      client: MockClient((_) async {
        calls++;
        return http.Response('rate limited', 429);
      }),
    );
    await expectLater(client.fetch(url),
      throwsA(isA<MediaFeedRequestException>().having(
        (e) => e.statusCode, 'status', 429)));
    expect(calls, 1);
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
