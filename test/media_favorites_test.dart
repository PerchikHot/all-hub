import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/media_favorites.dart';

void main() {
  Map<String, dynamic> post(int id) => {
    'id': id,
    'preview_file_url': 'https://cdn.example.com/$id.jpg',
    'image_width': 800,
    'image_height': 1200,
  };

  test('favorites persist in order without duplicate IDs', () {
    final json = writeMediaFavorites([post(3), post(3), post(5)]);
    final saved = readMediaFavorites(json);
    expect(saved.map((p) => p['id']), ['3', '5']);
    expect(saved.first['image_width'], 800);
    expect(saved.first.containsKey('tag_string'), isFalse);
  });

  test('invalid URLs and corrupt JSON never become bookmarks', () {
    expect(readMediaFavorites('not-json'), isEmpty);
    expect(readMediaFavorites('{}'), isEmpty);
    expect(safeMediaFavorite({'id': 'abc', 'file_url': 'https://a.test/a.jpg'}), isNull);
    expect(safeMediaFavorite({'id': 3, 'file_url': 'http://a.test/a.jpg'}), isNull);
    expect(safeMediaFavorite({'id': 3, 'file_url': 'https://user@a.test/a.jpg'}), isNull);
    expect(safeMediaFavorite(post(1))?['id'], '1');
  });

  test('local index is capped and excludes remote query metadata', () {
    final saved = readMediaFavorites(writeMediaFavorites([
      for (var i = 1; i <= maxMediaFavorites + 30; i++)
        {...post(i), 'tag_string': 'private search text'},
    ]));
    expect(saved.length, maxMediaFavorites);
    expect(saved.first['id'], '1');
    expect(saved.last['id'], '$maxMediaFavorites');
    expect(saved.every((p) => !p.containsKey('tag_string')), isTrue);
  });
}
