import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:all_hub/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('All Hub opens with catalog and navigation', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const AllHub());
    await tester.pump();
    expect(find.text('ALL HUB'), findsWidgets);
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Проекты'), findsOneWidget);
  });

  testWidgets('Returning from Android installer refreshes the catalog safely',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const AllHub());
    await tester.pump();
    // The OS may return without installing anything. Refresh must not
    // assume success, remove cards or crash.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('ALL HUB'), findsWidgets);
    expect(find.text('Проекты'), findsOneWidget);
  });
}
