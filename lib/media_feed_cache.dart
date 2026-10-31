/// Bounded, in-memory cache for Danbooru feed pages.
///
/// Search terms and results are never written to preferences or disk by this
/// cache. Reopening a filter within the same session can reuse a recent page
/// without another API call, reducing rate limits and blank feed transitions.
class MediaFeedMemoryCache {
  MediaFeedMemoryCache({
    this.maxEntries = 12,
    this.ttl = const Duration(minutes: 10),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    if (maxEntries < 1 || ttl <= Duration.zero) {
      throw ArgumentError('Cache capacity and TTL must be positive');
    }
  }

  final int maxEntries;
  final Duration ttl;
  final DateTime Function() _clock;
  final Map<String, _MediaFeedPage> _pages = {};

  int get length => _pages.length;

  List<Map<String, dynamic>>? read(Uri request) {
    final key = request.toString();
    final entry = _pages.remove(key);
    if (entry == null) return null;
    final age = _clock().difference(entry.createdAt);
    if (age.isNegative || age >= ttl) return null;
    // Moving a hit to the end gives deterministic LRU eviction.
    _pages[key] = entry;
    // Return copies so UI mutations cannot corrupt the cached response.
    return entry.posts
        .map((post) => Map<String, dynamic>.from(post))
        .toList(growable: false);
  }

  void store(Uri request, Iterable<Map<String, dynamic>> posts) {
    final key = request.toString();
    final snapshot = posts
        .take(40)
        .map((post) => Map<String, dynamic>.from(post))
        .toList(growable: false);
    _pages.remove(key);
    _pages[key] = _MediaFeedPage(_clock(), snapshot);
    while (_pages.length > maxEntries) {
      _pages.remove(_pages.keys.first);
    }
  }

  void clear() => _pages.clear();
}

class _MediaFeedPage {
  const _MediaFeedPage(this.createdAt, this.posts);
  final DateTime createdAt;
  final List<Map<String, dynamic>> posts;
}
