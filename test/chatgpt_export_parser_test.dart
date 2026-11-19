import 'dart:convert';
import 'dart:io';
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
  test('repeat imports retain previous unique excerpts', () {
    expect(mergeChatGptExcerpts(['старый текст', 'общий текст'],
        ['новый текст', 'общий текст']),
        ['новый текст', 'общий текст', 'старый текст']);
  });

  test('new imports take priority when storage is full', () {
    expect(mergeChatGptExcerpts(['старый 1', 'старый 2'],
        ['новый 1', 'новый 2'], maxExcerpts: 3),
        ['новый 1', 'новый 2', 'старый 1']);
  });

  test('empty entries and duplicates do not waste storage', () {
    expect(mergeChatGptExcerpts([' запись ', 'другая'],
        ['', 'запись', ' запись '], maxExcerpts: 2),
        ['запись', 'другая']);
  });

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

  test('prioritizes recent conversations even if export is oldest first', () {
    final export = [
      {
        'update_time': 100,
        'current_node': 'old',
        'mapping': {'old': node(null, 'user', 'Старое сообщение из архива')},
      },
      {
        'update_time': 200,
        'current_node': 'new',
        'mapping': {'new': node(null, 'user', 'Новое сообщение из архива')},
      },
    ];
    expect(extractChatGptExcerpts(export), [
      'Новое сообщение из архива',
      'Старое сообщение из архива',
    ]);
  });

  test('rejects malformed top-level export', () {
    expect(() => extractChatGptExcerpts({'mapping': {}}), throwsFormatException);
  });
  test('file importer reads a valid export without persisting raw data', () async {
    final dir = await Directory.systemTemp.createTemp('allhub-import-test-');
    try {
      final source = File('${dir.path}/conversations.json');
      await source.writeAsString(jsonEncode([{
        'current_node': 'last',
        'mapping': {
          'last': node(null, 'user', 'Сохранить только текст диалога'),
        },
      }]));
      expect(await extractChatGptExcerptsFromFile(source.path),
          ['Сохранить только текст диалога']);
      expect(await source.exists(), isTrue);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('file importer rejects oversized exports before JSON parsing', () async {
    final dir = await Directory.systemTemp.createTemp('allhub-import-limit-');
    try {
      final source = File('${dir.path}/conversations.json');
      await source.writeAsString('not-json-and-over-limit');
      await expectLater(
        extractChatGptExcerptsFromFile(source.path, maxBytes: 5),
        throwsFormatException,
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('file importer reports malformed JSON', () async {
    final dir = await Directory.systemTemp.createTemp('allhub-import-invalid-');
    try {
      final source = File('${dir.path}/conversations.json');
      await source.writeAsString('invalid json');
      await expectLater(
        extractChatGptExcerptsFromFile(source.path),
        throwsFormatException,
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });

}
