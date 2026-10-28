import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/project_launcher.dart';

void main() {
  test('Windows installation IDs allow known project slugs', () {
    for (final id in ['all-hub', 'kopilka', 'eclipse-arena', 'shadow-rp']) {
      expect(ProjectLauncher.isValidProjectId(id), isTrue, reason: id);
    }
  });

  test('Windows installation IDs cannot contain path traversal or separators', () {
    for (final id in [
      '', '.', '..', '../outside', 'kopilka/../other', 'all-hub/../../',
      'kopilka\\\\other', 'project..', '-project', 'project-', 'a--b',
      'project name', 'C:temp', '/tmp',
    ]) {
      expect(ProjectLauncher.isValidProjectId(id), isFalse, reason: id);
    }
  });
}
