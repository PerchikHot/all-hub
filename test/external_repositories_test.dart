import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:all_hub/external_repositories.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('accepts exact public GitHub repository identifiers and URLs', () {
    final a = ExternalRepository.parse('Owner/Some.Repo');
    final b = ExternalRepository.parse('https://github.com/Owner/Some.Repo/');
    expect(a?.fullName, 'Owner/Some.Repo');
    expect(b?.fullName, 'Owner/Some.Repo');
    expect(a?.projectId, b?.projectId);
    expect(ExternalRepository.parse('a-b/c')?.projectId,
        isNot(ExternalRepository.parse('a/b-c')?.projectId));
  });

  test('rejects misleading links and unsafe repository names', () {
    for (final value in [
      '', 'https://evil.github.com/user/repo',
      'http://github.com/user/repo',
      'https://github.com@evil.example/user/repo',
      'https://github.com/user/repo/releases',
      'https://github.com/user/repo?tab=readme',
      'https://github.com/user/repo#readme',
      'https://github.com/user%2frepo/other',
      'https://github.com:443/user/repo',
      'user/..', 'user/.', 'user/repo/extra',
      'user\\repo', '../repo', '-owner/repo', 'owner-/repo',
    ]) {
      expect(ExternalRepository.parse(value), isNull, reason: value);
    }
  });

  test('public repository verification rejects private and missing repos', () async {
    final repo = ExternalRepository.parse('Example/Widget')!;
    final valid = MockClient((request) async {
      expect(request.url.toString(),
          'https://api.github.com/repos/Example/Widget');
      return http.Response('{"full_name":"Example/Widget","private":false,"archived":false}', 200);
    });
    await ExternalRepositoryStore.verifyPublic(repo, client: valid);

    final privateClient = MockClient((request) async =>
        http.Response('{"full_name":"Example/Widget","private":true}', 200));
    await expectLater(
        ExternalRepositoryStore.verifyPublic(repo, client: privateClient),
        throwsStateError);
    final missingClient = MockClient((request) async =>
        http.Response('{"message":"Not Found"}', 404));
    await expectLater(
        ExternalRepositoryStore.verifyPublic(repo, client: missingClient),
        throwsStateError);
  });

  test('local repository catalog is deduplicated, removable and bounded', () async {
    SharedPreferences.setMockInitialValues({
      ExternalRepositoryStore.storageKey: [
        'Owner/Repo', 'owner/repo', 'invalid/path/extra', 'Else/Other',
      ],
    });
    final loaded = await ExternalRepositoryStore.load();
    expect(loaded.map((e) => e.fullName).toList(),
        ['Owner/Repo', 'Else/Other']);
    expect(await ExternalRepositoryStore.add(
        ExternalRepository.parse('owner/REPO')!), isFalse);
    expect(await ExternalRepositoryStore.add(
        ExternalRepository.parse('New/Project')!), isTrue);
    await ExternalRepositoryStore.remove(
        ExternalRepository.parse('OWNER/repo')!);
    expect((await ExternalRepositoryStore.load()).map((e) => e.fullName),
        ['Else/Other', 'New/Project']);
  });
}
