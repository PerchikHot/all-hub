/// Small, testable Danbooru feed filters shared by image and GIF results.
/// Never force an explicit-only rating: many tagged posts have other ratings.
String buildMediaFeedTags(String category, String query) {
  // Normalize pasted multiline searches before sending tags to the API.
  // Preserve tag operators and underscores; only collapse whitespace.
  final cleaned = query.trim().replaceAll(RegExp(r'\s+'), ' ');
  final base = category.trim();
  return cleaned.isEmpty ? base : '$base $cleaned';
}

/// Validate URLs, tag membership and duplicate IDs before rendering.
/// Rating is intentionally not restricted: the adult-confirmation gate lives
/// in MediaSearchPage, while an explicit-only filter hid valid results.
bool isVisibleFeedPost(
  Map<String, dynamic> post, {
  required String selectedTag,
  required String kind,
  required Set<String> seenIds,
}) {
  if (mediaFeedImageUrl(post, highQuality: false) == null) return false;
  final id = (post['id'] ?? '').toString();
  if (id.isEmpty || seenIds.contains(id)) return false;
  // API tag strings may contain repeated spaces, tabs or newlines.
  // Split on all whitespace instead of rejecting otherwise valid posts.
  final tags = (post['tag_string'] ?? '').toString().split(RegExp(r'\s+'));
  if (!tags.contains(selectedTag)) return false;
  if (kind == 'gif') {
    return (post['file_ext'] ?? '').toString().toLowerCase() == 'gif';
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

/// Select the first usable HTTPS URL; an invalid preferred URL must not hide
/// a valid fallback image or create a broken thumbnail.
String? mediaFeedImageUrl(Map<String, dynamic> post, {required bool highQuality}) {
  final keys = highQuality
      ? ['large_file_url', 'file_url', 'preview_file_url']
      : ['preview_file_url', 'large_file_url', 'file_url'];
  for (final key in keys) {
    final value = post[key];
    if (value is! String) continue;
    final uri = Uri.tryParse(value);
    if (uri != null && uri.scheme == 'https' && uri.host.isNotEmpty && uri.userInfo.isEmpty) {
      return value;
    }
  }
  return null;
}

/// Remove duplicate IDs within a single API response as well as across pages.
/// This function does not mutate the caller's seen set; the UI commits IDs
/// only after confirming the response still belongs to the active search.
List<Map<String, dynamic>> filterNewMediaFeedPosts(
  Iterable<Map<String, dynamic>> candidates, {
  required String selectedTag,
  required String kind,
  required Set<String> seenIds,
}) {
  final pageSeen = <String>{...seenIds};
  final result = <Map<String, dynamic>>[];
  for (final post in candidates) {
    if (!isVisibleFeedPost(post, selectedTag: selectedTag,
        kind: kind, seenIds: pageSeen)) {
      continue;
    }
    pageSeen.add((post['id'] ?? '').toString());
    result.add(post);
  }
  return result;
}
