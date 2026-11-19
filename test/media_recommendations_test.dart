import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/media_recommendations.dart';

void main() {
  test('explicit likes rank matching character and drawing tags first', () {
    final likes = <Map<String, dynamic>>[
      {'tag_string': 'futanari character_alpha watercolor'},
      {'tag_string': 'futanari character_alpha watercolor'},
      {'tag_string': 'transgender ink_style'},
    ];
    final posts = <Map<String, dynamic>>[
      {'id': '1', 'tag_string': 'ink_style'},
      {'id': '2', 'tag_string': 'character_alpha watercolor'},
      {'id': '3', 'tag_string': 'other_style'},
    ];
    expect(rankMediaByLikes(posts, likes).map((p) => p['id']).toList(),
      ['2', '1', '3']);
  });

  test('no likes retains source order and does not infer a profile', () {
    final posts = <Map<String, dynamic>>[
      {'id': '4', 'tag_string': 'character_alpha'},
      {'id': '5', 'tag_string': 'character_beta'},
    ];
    expect(rankMediaByLikes(posts, const []).map((p) => p['id']).toList(),
      ['4', '5']);
  });

  test('missing or oversized tags do not break ranking', () {
    expect(mediaLikedTagWeights([
      {'tag_string': 'x' * 5000}, {'tag_string': null},
    ]), isEmpty);
  });
}
