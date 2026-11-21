import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/project_launcher.dart';

void main() {
  group('Windows version receipt integrity', () {
    final digest = 'a' * 64;
    test('accepts only exact SHA-256 digest', () {
      expect(ProjectLauncher.matchesWindowsReceipt(digest, digest), isTrue);
      expect(ProjectLauncher.matchesWindowsReceipt(digest, 'b' * 64), isFalse);
    });
    test('rejects legacy, malformed and uppercase receipts', () {
      expect(ProjectLauncher.matchesWindowsReceipt(null, digest), isFalse);
      expect(ProjectLauncher.matchesWindowsReceipt('', digest), isFalse);
      expect(ProjectLauncher.matchesWindowsReceipt('a' * 63, digest), isFalse);
      expect(ProjectLauncher.matchesWindowsReceipt('G' * 64, digest), isFalse);
      expect(ProjectLauncher.matchesWindowsReceipt('A' * 64, digest), isFalse);
    });
  });
}
