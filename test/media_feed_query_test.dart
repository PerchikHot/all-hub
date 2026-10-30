import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/media_feed_query.dart';

void main() {
  test('feed searches category without silently forcing explicit rating', () {
    expect(buildMediaFeedTags('transgender', ''), 'transgender');
    expect(buildMediaFeedTags('futanari', '  erza_scarlet  '),
        'futanari erza_scarlet');
  });

  test('pasted multiline tags are normalized without changing operators', () {
    expect(buildMediaFeedTags(' futanari ', '  erza_scarlet\n  -animated\t rating:s  '),
        'futanari erza_scarlet -animated rating:s');
    expect(buildMediaFeedTags(' transgender ', '  \n  '), 'transgender');
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

  test('invalid preferred image URL falls back to a valid HTTPS sample', () {
    final post = <String, dynamic>{
      'id': 101,
      'tag_string': 'transgender solo',
      'preview_file_url': 'http://insecure.example/preview.jpg',
      'large_file_url': 'https://example.org/large.jpg',
      'file_url': 'https://example.org/original.jpg',
    };
    expect(isVisibleFeedPost(post, selectedTag: 'transgender',
        kind: 'all', seenIds: <String>{}), isTrue);
    expect(mediaFeedImageUrl(post, highQuality: false),
        'https://example.org/large.jpg');
    expect(mediaFeedImageUrl(post, highQuality: true),
        'https://example.org/large.jpg');
    expect(mediaFeedImageUrl({...post, 'large_file_url': 'invalid'},
        highQuality: true), 'https://example.org/original.jpg');
    expect(mediaFeedImageUrl({...post, 'large_file_url': 'https:///no-host',
        'file_url': null}, highQuality: false), isNull);
  });

  test('image URL credentials are rejected without hiding safe fallback', () {
    final post = <String, dynamic>{
      'preview_file_url': 'https://user:pass@example.org/unsafe.jpg',
      'large_file_url': 'https://example.org/safe.jpg',
    };
    expect(mediaFeedImageUrl(post, highQuality: false),
        'https://example.org/safe.jpg');
    expect(mediaFeedImageUrl({...post, 'large_file_url': null},
        highQuality: false), isNull);
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
  test('tag membership tolerates multiline API tag strings', () {
    final post = <String, dynamic>{
      'id': 57, 'tag_string': 'solo\ntransgender\tanimated',
      'preview_file_url': 'https://example.org/57.jpg', 'file_ext': 'jpg',
    };
    expect(isVisibleFeedPost(post, selectedTag: 'transgender',
        kind: 'all', seenIds: <String>{}), isTrue);
    expect(isVisibleFeedPost(post, selectedTag: 'futanari',
        kind: 'all', seenIds: <String>{}), isFalse);
  });

  test('same-page duplicate IDs are removed without mutating seen state', () {
    final first = <String, dynamic>{
      'id': 42, 'tag_string': 'transgender solo',
      'preview_file_url': 'https://example.org/42.jpg', 'file_ext': 'jpg',
    };
    final second = <String, dynamic>{
      'id': 43, 'tag_string': 'transgender solo',
      'preview_file_url': 'https://example.org/43.jpg', 'file_ext': 'jpg',
    };
    final seen = <String>{'41'};
    final filtered = filterNewMediaFeedPosts(
      [first, {...first}, {...first, 'id': 41}, second,
       {...second, 'tag_string': 'unrelated'}],
      selectedTag: 'transgender', kind: 'all', seenIds: seen,
    );
    expect(filtered.map((p) => p['id']).toList(), [42, 43]);
    expect(seen, <String>{'41'});
    expect(filterNewMediaFeedPosts([first, second], selectedTag: 'transgender',
        kind: 'all', seenIds: <String>{'42', '43'}), isEmpty);
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

  test('sample thumbnail fallback loads posts with missing preview URLs', () {
    final post = <String, dynamic>{
      'id': 91, 'tag_string': 'transgender solo',
      'sample_url': 'https://example.org/sample.jpg',
      'file_ext': 'jpg',
    };
    expect(mediaFeedImageUrl(post, highQuality: false),
        'https://example.org/sample.jpg');
    expect(isVisibleFeedPost(post, selectedTag: 'transgender',
        kind: 'all', seenIds: <String>{}), isTrue);
  });

  test('same-page repeated image URL is displayed once across post IDs', () {
    final first = <String, dynamic>{
      'id': 90, 'tag_string': 'transgender solo',
      'preview_file_url': 'https://example.org/reused.jpg',
      'file_ext': 'jpg',
    };
    final posts = filterNewMediaFeedPosts(
      [first, {...first, 'id': 91}, {...first, 'id': 92,
          'preview_file_url': 'https://example.org/different.jpg'}],
      selectedTag: 'transgender', kind: 'all', seenIds: <String>{},
    );
    expect(posts.map((p) => p['id']).toList(), [90, 92]);
  });

  test('different post IDs sharing a thumbnail across pages are not repeated', () {
    final first = <String, dynamic>{
      'id': 100, 'tag_string': 'transgender solo',
      'preview_file_url': 'https://example.org/same.jpg', 'file_ext': 'jpg',
    };
    final seenUrls = <String>{'https://example.org/same.jpg'};
    final filtered = filterNewMediaFeedPosts(
      [first, {...first, 'id': 101,
          'preview_file_url': 'https://example.org/new.jpg'}],
      selectedTag: 'transgender', kind: 'all',
      seenIds: <String>{}, seenUrls: seenUrls,
    );
    expect(filtered.map((post) => post['id']).toList(), [101]);
    expect(seenUrls, <String>{'https://example.org/same.jpg'});
  });

}
