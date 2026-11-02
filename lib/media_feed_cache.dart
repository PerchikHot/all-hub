import 'dart:convert';
import 'media_feed_query.dart';

/// A failed pull-to-refresh must restore pagination and deduplication too.
/// Restoring only cards made the next retry re-fetch page one and duplicate
/// everything already visible. This snapshot stays in memory, never on disk.
class MediaFeedRefreshSnapshot {
  MediaFeedRefreshSnapshot({
    required Iterable<Map<String, dynamic>> posts,
    required this.nextPage,
    required Iterable<String> seenIds,
    required Iterable<String> seenUrls,
    required Iterable<String> exhaustedTags,
  })  : posts = List.unmodifiable(posts.map(_copyJsonPost)),
        seenIds = Set.unmodifiable(seenIds),
        seenUrls = Set.unmodifiable(seenUrls),
        exhaustedTags = Set.unmodifiable(exhaustedTags) {
    if (nextPage < 1) throw ArgumentError('Invalid pagination cursor');
  }

  final List<Map<String, dynamic>> posts;
  final int nextPage;
  final Set<String> seenIds;
  final Set<String> seenUrls;
  final Set<String> exhaustedTags;
}

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
    // This fallback must never exceed two hours, even if a caller supplies
    // a larger duration. A stale page is not an offline archive.
    if (maxAge < ttl || maxAge > const Duration(hours: 2)) return null;
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
    final seenMediaUrls = <String>{};
    for (final post in posts.take(200)) {
      final id = post['id'];
      final idKey = id is int || id is String ? id.toString() : null;
      // A mirrored upload may have a new post ID but the exact same image
      // or GIF URL. Keep one card per actual media file in the cached page.
      // A post can expose an original GIF, a resized image and a preview.
      // Comparing only the first URL missed duplicates when mirrored posts
      // provided those fields in a different order or omitted one variant.
      final mediaUrls = mediaFeedIdentityKeys(post);
      if (idKey != null && seenIds.contains(idKey)) continue;
      if (mediaUrls.any(seenMediaUrls.contains)) continue;
      if (idKey != null) seenIds.add(idKey);
      seenMediaUrls.addAll(mediaUrls);
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
