/// Small, testable Danbooru feed filters shared by image and GIF results.
/// Never force an explicit-only rating: many tagged posts have other ratings.
String buildMediaFeedTags(String category, String query) {
  final cleaned = query.trim();
  return cleaned.isEmpty ? category : '$category $cleaned';
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
  final preview = post['preview_file_url'] ??
      post['large_file_url'] ?? post['file_url'];
  if (preview is! String || !preview.startsWith('https://')) return false;
  final id = (post['id'] ?? '').toString();
  if (id.isEmpty || seenIds.contains(id)) return false;
  final tags = (post['tag_string'] ?? '').toString().split(' ');
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
