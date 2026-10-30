import 'dart:convert';
import 'media_feed_query.dart';

/// Only explicit user bookmarks are stored, never browsing history or queries.
/// Keep the local index bounded and validate every URL before displaying it.
const int maxMediaFavorites = 150;

Map<String, dynamic>? safeMediaFavorite(Map<String, dynamic> source) {
  final id = (source['id'] ?? '').toString();
  if (!RegExp(r'^\\d{1,16}$').hasMatch(id)) return null;
  final result = <String, dynamic>{'id': id};
  for (final key in [
    'preview_file_url', 'sample_url', 'large_file_url', 'file_url'
  ]) {
    final value = source[key];
    if (value is String && value.length <= 2048) {
      final uri = Uri.tryParse(value);
      if (uri != null && uri.scheme == 'https' && uri.host.isNotEmpty &&
          uri.userInfo.isEmpty) {
        result[key] = value;
      }
    }
  }
  if (mediaFeedImageUrl(result, highQuality: false) == null) return null;
  for (final key in ['image_width', 'image_height']) {
    final value = source[key];
    if (value is num && value.isFinite && value > 0 && value <= 100000) {
      result[key] = value;
    }
  }
  if (source['file_ext'] == 'gif') result['file_ext'] = 'gif';
  return result;
}

List<Map<String, dynamic>> readMediaFavorites(String? raw) {
  if (raw == null || raw.length > 256 * 1024) return [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    final ids = <String>{};
    final result = <Map<String, dynamic>>[];
    for (final value in decoded.take(maxMediaFavorites)) {
      if (value is! Map<String, dynamic>) continue;
      final post = safeMediaFavorite(value);
      if (post == null || !ids.add(post['id'] as String)) continue;
      result.add(post);
    }
    return result;
  } catch (_) {
    return [];
  }
}

String writeMediaFavorites(Iterable<Map<String, dynamic>> posts) {
  final ids = <String>{};
  final result = <Map<String, dynamic>>[];
  for (final source in posts) {
    final post = safeMediaFavorite(source);
    if (post == null || !ids.add(post['id'] as String)) continue;
    result.add(post);
    if (result.length == maxMediaFavorites) break;
  }
  return jsonEncode(result);
}
