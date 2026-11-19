import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:all_hub/eyra_access_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('all sensitive capabilities default to disabled', () async {
    for (final id in EyraAccessPolicy.capabilities.keys) {
      expect(await EyraAccessPolicy.enabled(id), isFalse);
    }
  });

  test('explicit consent can be revoked and is audited', () async {
    expect(await EyraAccessPolicy.set('notifications', true), isTrue);
    expect(await EyraAccessPolicy.enabled('notifications'), isTrue);
    expect(await EyraAccessPolicy.set('notifications', false), isTrue);
    expect(await EyraAccessPolicy.enabled('notifications'), isFalse);
    final prefs = await SharedPreferences.getInstance();
    final log = prefs.getStringList('eyra_access_v1_audit')!;
    expect(log, hasLength(2));
    expect(log.last, contains('отозвано'));
  });

  testWidgets('diagnostics requires consent and separate confirmation', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: EyraAccessPage()));
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('eyra-run-diagnostics'));
    expect(button, findsOneWidget);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);

    await EyraAccessPolicy.set('diagnostics', true);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const MaterialApp(home: EyraAccessPage()));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Проверить устройство сейчас?'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Платформа:'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('eyra_access_v1_audit')!.length, 1);
  });

  test('unknown capability cannot be enabled', () async {
    expect(await EyraAccessPolicy.set('arbitrary_remote_command', true), isFalse);
    expect(await EyraAccessPolicy.enabled('arbitrary_remote_command'), isFalse);
  });
}
