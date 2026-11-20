import 'dart:convert';
import 'package:all_hub/gguf_chat_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('GGUF chat recovers from malformed saved history', (tester) async {
    const modelPath = '/models/test.gguf';
    final key = 'gguf_chat_${base64Url.encode(utf8.encode(modelPath))}';
    SharedPreferences.setMockInitialValues({key: '{invalid-json'});
    await tester.pumpWidget(const MaterialApp(
      home: GgufChatPage(modelPath: modelPath),
    ));
    await tester.pumpAndSettle();
    expect(find.text('GGUF • офлайн-чат'), findsOneWidget);
    expect(find.byIcon(Icons.send), findsOneWidget);
    final send = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send));
    expect(send.onPressed, isNotNull);
  });

  testWidgets('GGUF chat restores local messages', (tester) async {
    const modelPath = '/models/second.gguf';
    final key = 'gguf_chat_${base64Url.encode(utf8.encode(modelPath))}';
    SharedPreferences.setMockInitialValues({
      key: jsonEncode([
        {'user': true, 'text': 'Привет, Эйра'},
        {'user': false, 'text': 'Привет!'},
      ]),
    });
    await tester.pumpWidget(const MaterialApp(
      home: GgufChatPage(modelPath: modelPath),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Привет, Эйра'), findsOneWidget);
    expect(find.text('Привет!'), findsOneWidget);
  });
}
