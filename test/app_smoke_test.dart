import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/main.dart';

void main() {
  testWidgets('All Hub launches and displays its title', (tester) async {
    await tester.pumpWidget(const AllHub());
    expect(find.text('ALL HUB'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
