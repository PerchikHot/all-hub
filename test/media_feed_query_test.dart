import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/media_feed_query.dart';

void main() {
  test('feed searches category without silently forcing explicit rating', () {
    expect(buildMediaFeedTags('transgender', ''), 'transgender');
    expect(buildMediaFeedTags('futanari', '  erza_scarlet  '),
        'futanari erza_scarlet');
  });

  test('valid tagged images survive any rating and duplicates are rejected', () {
    final safe = <String, dynamic>{
      'id': 42,
      'preview_file_url': 'https://example.org/preview.jpg',
      'tag_string': 'transgender solo',
      'rating': 's',
      'file_ext': 'jpg',
    };
    expect(isVisibleFeedPost(safe, selectedTag: 'transgender',
        kind: 'all', seenIds: <String>{}), isTrue);
    expect(isVisibleFeedPost(safe, selectedTag: 'transgender',
        kind: 'all', seenIds: <String>{'42'}), isFalse);
    expect(isVisibleFeedPost(safe, selectedTag: 'futanari',
        kind: 'all', seenIds: <String>{}), isFalse);
    expect(isVisibleFeedPost(safe, selectedTag: 'transgender',
        kind: 'gif', seenIds: <String>{}), isFalse);
  });

  test('GIFs need a real HTTPS thumbnail and stable ID', () {
    final gif = <String, dynamic>{
      'id': 11,
      'large_file_url': 'https://example.org/11.gif',
      'tag_string': 'futanari animated',
      'file_ext': 'GIF',
    };
    expect(isVisibleFeedPost(gif, selectedTag: 'futanari',
        kind: 'gif', seenIds: <String>{}), isTrue);
    expect(isVisibleFeedPost({...gif, 'id': null},
        selectedTag: 'futanari', kind: 'gif', seenIds: <String>{}), isFalse);
    expect(isVisibleFeedPost({...gif, 'large_file_url': 'http://example.org/x'},
        selectedTag: 'futanari', kind: 'gif', seenIds: <String>{}), isFalse);
  });
  test('empty first category tries the other; bounded GIF scan terminates', () {
    expect(shouldContinueMediaFeed(fetched: 0, pageSize: 24,
        categoryCount: 2, requestedPage: 1, emptyRetries: 1,
        hasPosts: false), isTrue);
    expect(shouldContinueMediaFeed(fetched: 0, pageSize: 24,
        categoryCount: 2, requestedPage: 2, emptyRetries: 2,
        hasPosts: false), isFalse);
    expect(shouldContinueMediaFeed(fetched: 24, pageSize: 24,
        categoryCount: 2, requestedPage: 8, emptyRetries: 8,
        hasPosts: false), isFalse);
    expect(shouldContinueMediaFeed(fetched: 24, pageSize: 24,
        categoryCount: 1, requestedPage: 1, emptyRetries: 0,
        hasPosts: true), isTrue);
  });

}
