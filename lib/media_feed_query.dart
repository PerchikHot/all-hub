/// Small, testable Danbooru feed filters shared by image and GIF results.
/// Never force an explicit-only rating: many tagged posts have other ratings.
String buildMediaFeedTags(String category, String query) {
  // Normalize pasted multiline searches before sending tags to the API.
  // Preserve tag operators and underscores; only collapse whitespace.
  final cleaned = query.trim().replaceAll(RegExp(r'\s+'), ' ');
  final base = category.trim().replaceAll(RegExp(r'\s+'), ' ');
  // An empty category should not add a leading space to a custom search.
  if (base.isEmpty) return cleaned;
  return cleaned.isEmpty ? base : '$base $cleaned';
}


/// Danbooru's anonymous API accepts only two search tags. GIF queries used
/// to omit filetype:gif whenever a character was entered, so eight pages of
/// still images could be scanned without finding a single animation.
/// Put the file type and the most selective user tag on the server; check
/// category and any remaining terms locally before showing a result.
String buildMediaFeedRequestTags(String category, String query, String kind) {
  final terms = query.trim().split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty).toList();
  if (kind == 'gif') {
    final first = terms.where((term) =>
        term.toLowerCase() != 'filetype:gif').firstOrNull;
    return buildMediaFeedTags(first ?? category, 'filetype:gif');
  }
  return buildMediaFeedTags(category, terms.isEmpty ? '' : terms.first);
}

/// Apply the complete search locally when the server tag budget is exhausted.
/// Never display a result that fails a positive/negative tag, rating or type
/// requested by the user. The API may still return fewer matches for very
/// restrictive searches, but it will not return misleading matches.
bool matchesMediaFeedQuery(Map<String, dynamic> post, String query) {
  final tags = (post['tag_string'] ?? '').toString()
      .toLowerCase().split(RegExp(r'\s+')).toSet();
  final rating = (post['rating'] ?? '').toString().toLowerCase();
  final extension = (post['file_ext'] ?? '').toString().toLowerCase();
  for (final raw in query.toLowerCase().split(RegExp(r'\s+'))) {
    if (raw.isEmpty) continue;
    final excluded = raw.startsWith('-');
    final term = excluded ? raw.substring(1) : raw;
    if (term.isEmpty) continue;
    final found = term.startsWith('rating:')
        ? rating == term.substring(7)
        : term.startsWith('filetype:')
            ? extension == term.substring(9)
            : tags.contains(term);
    if (excluded ? found : !found) return false;
  }
  return true;
}

/// Validate URLs, tag membership and duplicate IDs before rendering.
/// Rating is intentionally not restricted: the adult-confirmation gate lives
/// in MediaSearchPage, while an explicit-only filter hid valid results.
bool isVisibleFeedPost(
  Map<String, dynamic> post, {
  required String selectedTag,
  required String kind,
  required Set<String> seenIds,
  String query = '',
}) {
  if (!matchesMediaFeedQuery(post, query)) return false;
  if (mediaFeedImageUrl(post, highQuality: false) == null) return false;
  final id = (post['id'] ?? '').toString();
  if (id.isEmpty || seenIds.contains(id)) return false;
  // API tag strings may contain repeated spaces, tabs or newlines.
  // Split on all whitespace instead of rejecting otherwise valid posts.
  final tags = (post['tag_string'] ?? '').toString().split(RegExp(r'\s+'));
  if (!tags.contains(selectedTag)) return false;
  if (kind == 'gif') {
    // Do not fill the animated gallery with static JPG thumbnails.
    return mediaFeedAnimatedUrl(post) != null;
  }
  return true;
}

/// Continue checking the other enabled category before declaring an empty feed.
/// Stop after a bounded number of empty filtered pages (especially for GIFs).
bool shouldContinueMediaFeed({
  required int fetched,
  required int pageSize,
  required int categoryCount,
  required int requestedPage,
  required int emptyRetries,
  required bool hasPosts,
}) {
  if (hasPosts) return fetched >= pageSize;
  if (emptyRetries >= 8) return false;
  return fetched >= pageSize || requestedPage < categoryCount;
}

/// CachedNetworkImage disk resizing may transcode an animated GIF into a
/// single still frame. Keep the original GIF bytes in the disk cache.
bool isAnimatedFeedAssetUrl(String url) {
  final uri = Uri.tryParse(url);
  return uri != null && uri.scheme == 'https' &&
      uri.path.toLowerCase().endsWith('.gif');
}

/// True only for a GIF that has a usable animated HTTPS asset. Danbooru
/// often returns a static JPG preview even when file_ext is GIF.
String? mediaFeedAnimatedUrl(Map<String, dynamic> post) {
  if ((post['file_ext'] ?? '').toString().toLowerCase() != 'gif') {
    return null;
  }
  final size = post['file_size'];
  // A malformed size must not bypass the limit when it is supplied.
  if (size != null && (size is! num || !size.isFinite ||
      size < 0 || size > 24 * 1024 * 1024)) {
    return null;
  }
  for (final key in ['file_url', 'large_file_url', 'sample_url']) {
    final value = post[key];
    if (value is! String) continue;
    final uri = Uri.tryParse(value);
    if (uri != null && uri.scheme == 'https' && uri.host.isNotEmpty &&
        uri.userInfo.isEmpty && !uri.hasFragment &&
        uri.path.toLowerCase().endsWith('.gif')) {
      return value;
    }
  }
  return null;
}

/// Ordered, unique HTTPS candidates. A CDN may return HTTP 403 for a
/// thumbnail while its sample or original remains available.
List<String> mediaFeedImageCandidates(Map<String, dynamic> post, {
  required bool highQuality,
}) {
  // For GIF posts the API usually supplies a static JPG preview. Prefer
  // the actual animated asset in both HD and compact views; otherwise the
  // GIF tab silently looks like a still-image gallery. Large originals are
  // not auto-played in the masonry feed to avoid unbounded memory/network use.
  final animated = mediaFeedAnimatedUrl(post);
  final keys = highQuality
      ? ['large_file_url', 'file_url', 'sample_url', 'preview_file_url']
      : ['preview_file_url', 'sample_url', 'large_file_url', 'file_url'];
  final urls = <String>[if (animated != null) animated];
  final seen = <String>{if (animated != null) animated};
  for (final key in keys) {
    final value = post[key];
    if (value is! String) continue;
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty || uri.hasFragment) {
      continue;
    }
    if (seen.add(value)) {
      urls.add(value);
    }
  }
  return urls;
}

/// Select the first usable HTTPS URL without hiding valid fallbacks.
String? mediaFeedImageUrl(Map<String, dynamic> post, {required bool highQuality}) {
  final urls = mediaFeedImageCandidates(post, highQuality: highQuality);
  return urls.isEmpty ? null : urls.first;
}

/// Remove duplicate IDs within a single API response as well as across pages.
/// This function does not mutate the caller's seen set; the UI commits IDs
/// only after confirming the response still belongs to the active search.
List<Map<String, dynamic>> filterNewMediaFeedPosts(
  Iterable<Map<String, dynamic>> candidates, {
  required String selectedTag,
  required String kind,
  required Set<String> seenIds,
  Set<String> seenUrls = const <String>{},
  String query = '',
}) {
  final pageSeen = <String>{...seenIds};
  // The API can return the same image under different post IDs. Avoid
  // showing identical thumbnail URLs twice on a single loaded page.
  final pageUrls = <String>{...seenUrls};
  final result = <Map<String, dynamic>>[];
  for (final post in candidates) {
    if (!isVisibleFeedPost(post, selectedTag: selectedTag,
        kind: kind, seenIds: pageSeen, query: query)) {
      continue;
    }
    final url = mediaFeedImageUrl(post, highQuality: false);
    if (url == null || !pageUrls.add(url)) continue;
    pageSeen.add((post['id'] ?? '').toString());
    result.add(post);
  }
  return result;
}


/// Clamp API-supplied image proportions so portrait and landscape posts can
/// coexist in a Pinterest-style masonry grid without enormous layout tiles.
double mediaFeedTileAspectRatio(Map<String, dynamic> post) {
  final width = post['image_width'];
  final height = post['image_height'];
  if (width is! num || height is! num ||
      !width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
    return 0.72;
  }
  return (width.toDouble() / height.toDouble()).clamp(0.55, 1.45).toDouble();
}

/// Find the next page for a category that has not reached the end of its API
/// results. Each category has its own page sequence in the interleaved feed.
/// Returning null prevents exhausted categories from starving the other one.
int? nextAvailableMediaFeedPage(
  int requestedPage, List<String> enabledTags, Set<String> exhaustedTags,
) {
  if (requestedPage < 1 || enabledTags.isEmpty) return null;
  for (var offset = 0; offset < enabledTags.length; offset++) {
    final candidate = requestedPage + offset;
    final tag = enabledTags[(candidate - 1) % enabledTags.length];
    if (!exhaustedTags.contains(tag)) return candidate;
  }
  return null;
}
