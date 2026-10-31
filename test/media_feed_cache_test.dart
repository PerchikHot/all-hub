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

  test('invalid cache budgets are rejected', () {
    expect(() => MediaFeedMemoryCache(maxEntries: 0), throwsArgumentError);
    expect(() => MediaFeedMemoryCache(ttl: Duration.zero), throwsArgumentError);
  });
}
