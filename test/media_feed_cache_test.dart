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
    now = now.add(const Duration(hours: 3));
    expect(cache.readStale(request), isNull);
  });

  test('invalid cache budgets are rejected', () {
    expect(() => MediaFeedMemoryCache(maxEntries: 0), throwsArgumentError);
    expect(() => MediaFeedMemoryCache(ttl: Duration.zero), throwsArgumentError);
  });
}
