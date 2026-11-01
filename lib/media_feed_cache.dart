import 'dart:convert';

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
    final entry = _pages[key];
    if (entry == null) return null;
    final age = _clock().difference(entry.createdAt);
    if (age.isNegative || age >= ttl) return null;
    // Moving a fresh hit to the end gives deterministic LRU eviction.
    _pages.remove(key);
    _pages[key] = entry;
    // Deep copies are necessary: Danbooru posts can contain nested tags,
    // metadata and lists which a shallow Map.from would still share.
    return entry.posts.map(_copyJsonPost).toList(growable: false);
  }

  /// An expired page may be used only after a failed network request.
  /// This never extends the normal TTL or writes the user's feed to disk.
  /// Keep a strict two-hour ceiling to avoid showing arbitrarily old media.
  List<Map<String, dynamic>>? readStale(Uri request, {
    Duration maxAge = const Duration(hours: 2),
  }) {
    if (maxAge < ttl) return null;
    final entry = _pages[request.toString()];
    if (entry == null) return null;
    final age = _clock().difference(entry.createdAt);
    if (age.isNegative || age > maxAge) return null;
    return entry.posts.map(_copyJsonPost).toList(growable: false);
  }

  void store(Uri request, Iterable<Map<String, dynamic>> posts) {
    final key = request.toString();
    // One API page may repeat the same post ID. Deduplicate before the
    // 40-card limit so repeated GIFs do not crowd out unique artwork.
    // Bound traversal as well as storage to keep a hostile feed finite.
    final snapshot = <Map<String, dynamic>>[];
    final seenIds = <String>{};
    for (final post in posts.take(200)) {
      final id = post['id'];
      if (id is int || id is String) {
        if (!seenIds.add(id.toString())) continue;
      }
      snapshot.add(_copyJsonPost(post));
      if (snapshot.length == 40) break;
    }
    _pages.remove(key);
    _pages[key] = _MediaFeedPage(_clock(), snapshot);
    while (_pages.length > maxEntries) {
      _pages.remove(_pages.keys.first);
    }
  }

  void clear() => _pages.clear();
}

Map<String, dynamic> _copyJsonPost(Map<String, dynamic> post) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(post)) as Map);

class _MediaFeedPage {
  const _MediaFeedPage(this.createdAt, this.posts);
  final DateTime createdAt;
  final List<Map<String, dynamic>> posts;
}
