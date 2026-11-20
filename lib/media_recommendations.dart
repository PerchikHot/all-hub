/// Local, explainable recommendation ranking based only on explicit likes.
/// Never infer preferences from browsing history or transmit likes to a server.
const _ignoredRecommendationTags = <String>{
  'futanari', 'transgender', 'solo', '1girl', '1boy', '2girls',
  'rating:explicit', 'rating:questionable', 'rating:safe',
};

Map<String, int> mediaLikedTagWeights(Iterable<Map<String, dynamic>> likes) {
  final weights = <String, int>{};
  for (final like in likes) {
    final raw = like['tag_string'];
    if (raw is! String || raw.length > 4096) continue;
    final unique = raw.split(RegExp(r'\s+')).where((tag) =>
      tag.length >= 3 && tag.length <= 80 &&
      RegExp(r'^[a-z0-9_():.\\-]+$').hasMatch(tag) &&
      !_ignoredRecommendationTags.contains(tag)).toSet();
    for (final tag in unique) {
      weights[tag] = (weights[tag] ?? 0) + 1;
    }
  }
  return weights;
}

int mediaRecommendationScore(Map<String, dynamic> post, Map<String, int> weights) {
  final raw = post['tag_string'];
  if (raw is! String || raw.length > 4096 || weights.isEmpty) return 0;
  return raw.split(RegExp(r'\s+')).toSet().fold<int>(
    0, (score, tag) => score + (weights[tag] ?? 0));
}

/// Stable order for equal scores; no network requests and no hidden profiling.
List<Map<String, dynamic>> rankMediaByLikes(
  List<Map<String, dynamic>> posts,
  Iterable<Map<String, dynamic>> likes,
) {
  final weights = mediaLikedTagWeights(likes);
  final indexed = posts.asMap().entries.toList();
  indexed.sort((a, b) {
    final byScore = mediaRecommendationScore(b.value, weights)
        .compareTo(mediaRecommendationScore(a.value, weights));
    return byScore != 0 ? byScore : a.key.compareTo(b.key);
  });
  return indexed.map((entry) => entry.value).toList();
}

/// Append only newly fetched posts. Existing visible tiles keep their position
/// even if the new batch scores higher or likes change while browsing.
void appendStableMediaRecommendations(
  List<Map<String, dynamic>> destination,
  List<Map<String, dynamic>> newPosts,
  Iterable<Map<String, dynamic>> likes,
) {
  destination.addAll(rankMediaByLikes(newPosts, likes));
}
