import 'package:flutter_test/flutter_test.dart';
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

  test('unknown capability cannot be enabled', () async {
    expect(await EyraAccessPolicy.set('arbitrary_remote_command', true), isFalse);
    expect(await EyraAccessPolicy.enabled('arbitrary_remote_command'), isFalse);
  });
}
