import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/chatgpt_export_parser.dart';

Map<String, dynamic> node(String? parent, String role, String text) => {
  'parent': parent,
  'message': {
    'author': {'role': role},
    'content': {'content_type': 'text', 'parts': [text]},
  },
};

void main() {
  test('imports only active branch in chronological order', () {
    final export = [{
      'current_node': 'final',
      'mapping': {
        'root': node(null, 'user', 'Первое сообщение пользователя'),
        'old': node('root', 'assistant', 'Старый ответ был отброшен'),
        'new': node('root', 'assistant', 'Актуальный ответ помощника'),
        'final': node('new', 'user', 'Продолжение нашего диалога'),
      },
    }];
    expect(extractChatGptExcerpts(export), [
      'Первое сообщение пользователя',
      'Актуальный ответ помощника',
      'Продолжение нашего диалога',
    ]);
  });

  test('skips exports without current node and non-text/system content', () {
    final export = [
      {'mapping': {'a': node(null, 'user', 'Неактивная ветка переписки')}},
      {
        'current_node': 'assistant',
        'mapping': {
          'system': node(null, 'system', 'Скрытая системная инструкция'),
          'assistant': node('system', 'assistant', 'Обычный ответ помощника'),
        },
      },
    ];
    expect(extractChatGptExcerpts(export), ['Обычный ответ помощника']);
  });

  test('terminates cyclic parent references safely', () {
    final export = [{
      'current_node': 'b',
      'mapping': {
        'a': node('b', 'user', 'Сообщение пользователя один'),
        'b': node('a', 'assistant', 'Сообщение помощника два'),
      },
    }];
    expect(extractChatGptExcerpts(export), [
      'Сообщение пользователя один',
      'Сообщение помощника два',
    ]);
  });

  test('deduplicates excerpts across conversations without changing order', () {
    final export = [
      {
        'current_node': 'b',
        'mapping': {
          'a': node(null, 'user', 'Повторяющийся текст из переписки'),
          'b': node('a', 'assistant', 'Уникальный ответ помощника'),
        },
      },
      {
        'current_node': 'c',
        'mapping': {
          'c': node(null, 'user', 'Повторяющийся текст из переписки'),
        },
      },
    ];
    expect(extractChatGptExcerpts(export), [
      'Повторяющийся текст из переписки',
      'Уникальный ответ помощника',
    ]);
  });

  test('rejects malformed top-level export', () {
    expect(() => extractChatGptExcerpts({'mapping': {}}), throwsFormatException);
  });
}
