import 'package:all_hub/media_feed_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('revisiting a filter reuses a page without mutating cached results', () {
    final cache = MediaFeedMemoryCache();
    final request = Uri.https('danbooru.donmai.us', '/posts.json', {
      'tags': 'transgender filetype:gif', 'page': '1',
    });
    final original = <String, dynamic>{'id': 1, 'tag_string': 'transgender'};
    cache.store(request, [original]);
    original['id'] = 99;
    final first = cache.read(request)!;
    expect(first.single['id'], 1);
    first.single['id'] = 22;
    expect(cache.read(request)!.single['id'], 1);
  });

  test('nested GIF and image metadata cannot mutate a cached page', () {
    final cache = MediaFeedMemoryCache();
    final request = Uri.parse('https://example.org/nested');
    final original = <String, dynamic>{
      'id': 1,
      'media_asset': <String, dynamic>{
        'variants': <dynamic>[<String, dynamic>{'url': 'safe.gif'}],
      },
    };
    cache.store(request, [original]);
    ((original['media_asset'] as Map)['variants'] as List).clear();
    final first = cache.read(request)!.single;
    final media = first['media_asset'] as Map;
    expect((media['variants'] as List).single['url'], 'safe.gif');
    ((media['variants'] as List).single as Map)['url'] = 'mutated.gif';
    final second = cache.read(request)!.single;
    expect((((second['media_asset'] as Map)['variants'] as List).single
        as Map)['url'], 'safe.gif');
  });

  test('cache expires and never persists results between instances', () {
    var now = DateTime.utc(2026, 10, 31);
    final request = Uri.parse('https://example.org/page');
    final cache = MediaFeedMemoryCache(
      ttl: const Duration(minutes: 5), clock: () => now);
    cache.store(request, [{'id': 5}]);
    now = now.add(const Duration(minutes: 4));
    expect(cache.read(request), isNotNull);
    now = now.add(const Duration(minutes: 1));
    expect(cache.read(request), isNull);
    expect(MediaFeedMemoryCache().read(request), isNull);
  });

  test('least recently used pages are evicted, bounded to 40 posts', () {
    final cache = MediaFeedMemoryCache(maxEntries: 2);
    final a = Uri.parse('https://example.org/a');
    final b = Uri.parse('https://example.org/b');
    final c = Uri.parse('https://example.org/c');
    cache.store(a, List.generate(100, (i) => {'id': i}));
    expect(cache.read(a), hasLength(40));
    cache.store(b, [{'id': 2}]);
    cache.read(a);
    cache.store(c, [{'id': 3}]);
    expect(cache.length, 2);
    expect(cache.read(b), isNull);
    expect(cache.read(a), isNotNull);
    expect(cache.read(c), isNotNull);
  });

  test('expired feed is available only as a bounded offline fallback', () {
    var now = DateTime.utc(2026, 11, 1);
    final request = Uri.parse('https://example.org/offline');
    final cache = MediaFeedMemoryCache(
      ttl: const Duration(minutes: 5), clock: () => now);
    cache.store(request, [{'id': 9, 'tags': <String>['safe']}]);
    now = now.add(const Duration(minutes: 7));
    expect(cache.read(request), isNull);
    final fallback = cache.readStale(request)!;
    (fallback.single['tags'] as List).clear();
    expect((cache.readStale(request)!.single['tags'] as List), ['safe']);
    expect(cache.readStale(request,
        maxAge: const Duration(days: 7)), isNull);
    now = now.add(const Duration(hours: 3));
    expect(cache.readStale(request), isNull);
  });

  test('invalid cache budgets are rejected', () {
    expect(() => MediaFeedMemoryCache(maxEntries: 0), throwsArgumentError);
    expect(() => MediaFeedMemoryCache(ttl: Duration.zero), throwsArgumentError);
  });
  test('repeated post IDs do not consume the 40-card media budget', () {
    final cache = MediaFeedMemoryCache();
    final request = Uri.parse('https://example.org/repeated-gifs');
    cache.store(request, [
      for (var i = 0; i < 60; i++)
        {'id': i ~/ 2, 'file_url': 'https://example.org/$i.gif'},
    ]);
    final page = cache.read(request)!;
    expect(page, hasLength(30));
    expect(page.map((post) => post['id']).toSet(), hasLength(30));
    expect(page.first['file_url'], 'https://example.org/0.gif');
  });

  test('mirrored GIF URLs are not duplicated even with different post IDs', () {
    final cache = MediaFeedMemoryCache();
    final request = Uri.parse('https://example.org/mirrored-gifs');
    cache.store(request, [
      {'id': 11, 'file_url': 'https://cdn.example/one.gif'},
      {'id': 12, 'file_url': 'https://cdn.example/one.gif'},
      {'id': 13, 'file_url': 'https://cdn.example/two.gif'},
      {'id': 14, 'file_url': 'https://cdn.example/three.gif'},
      {'id': 15, 'preview_file_url': 'https://cdn.example/three.gif'},
      {'id': 16, 'file_url': 'https://cdn.example/four.gif'},
    ]);
    final posts = cache.read(request)!;
    expect(posts.map((post) => post['id']).toList(), [11, 13, 14, 16]);
  });

  test('failed refresh restores exact page cursor and deduplication', () {
    final posts = <Map<String, dynamic>>[
      {'id': 11, 'media_asset': {'variants': ['original.gif']}},
    ];
    final ids = <String>{'11'};
    final urls = <String>{'https://cdn.example/11.gif'};
    final exhausted = <String>{'futanari'};
    final backup = MediaFeedRefreshSnapshot(
      posts: posts, nextPage: 7, seenIds: ids,
      seenUrls: urls, exhaustedTags: exhausted,
    );
    posts.single['id'] = 99;
    ids.clear();
    urls.clear();
    exhausted.clear();
    expect(backup.posts.single['id'], 11);
    expect(backup.nextPage, 7);
    expect(backup.seenIds, {'11'});
    expect(backup.seenUrls, {'https://cdn.example/11.gif'});
    expect(backup.exhaustedTags, {'futanari'});
    expect(() => backup.seenIds.add('12'), throwsUnsupportedError);
    expect(() => MediaFeedRefreshSnapshot(
      posts: const [], nextPage: 0, seenIds: const [],
      seenUrls: const [], exhaustedTags: const [],
    ), throwsArgumentError);
  });


}
