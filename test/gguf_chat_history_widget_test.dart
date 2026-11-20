import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:all_hub/gguf_chat_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('GGUF history survives opening and canceling delete', (tester) async {
    const path = '/test/eyra.gguf';
    final key = 'gguf_chat_${base64Url.encode(utf8.encode(path))}';
    SharedPreferences.setMockInitialValues({
      key: jsonEncode([{'user': true, 'text': 'Сохранённый вопрос'}]),
    });
    await tester.pumpWidget(const MaterialApp(home: GgufChatPage(modelPath: path)));
    await tester.pumpAndSettle();
    expect(find.text('Сохранённый вопрос'), findsOneWidget);
    await tester.tap(find.byTooltip('Очистить переписку'));
    await tester.pumpAndSettle();
    expect(find.text('Удалить переписку GGUF?'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(find.text('Сохранённый вопрос'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(key), isNotNull);
  });

  testWidgets('GGUF history is deleted only after confirmation', (tester) async {
    const path = '/test/other.gguf';
    final key = 'gguf_chat_${base64Url.encode(utf8.encode(path))}';
    SharedPreferences.setMockInitialValues({
      key: jsonEncode([{'user': false, 'text': 'Старый ответ'}]),
    });
    await tester.pumpWidget(const MaterialApp(home: GgufChatPage(modelPath: path)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Очистить переписку'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();
    expect(find.text('Старый ответ'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(key), isNull);
  });
}
