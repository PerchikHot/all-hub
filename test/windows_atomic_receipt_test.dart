import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/project_launcher.dart';

void main() {
  const digest = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  test('atomic receipt returns the committed version', () {
    expect(ProjectLauncher.verifiedWindowsReceiptVersion('1.2.3|$digest', digest), '1.2.3');
    expect(ProjectLauncher.verifiedWindowsReceiptVersion('1.2.3+44|$digest', digest), '1.2.3+44');
  });

  test('atomic receipt rejects corrupted or mismatched data', () {
    expect(ProjectLauncher.verifiedWindowsReceiptVersion('1.2.3|$digest', 'b' * 64), isNull);
    expect(ProjectLauncher.verifiedWindowsReceiptVersion('1.2.3|bad', digest), isNull);
    expect(ProjectLauncher.verifiedWindowsReceiptVersion('rolling|$digest', digest), isNull);
    expect(ProjectLauncher.verifiedWindowsReceiptVersion('1.2.3', digest), isNull);
    expect(ProjectLauncher.verifiedWindowsReceiptVersion(null, digest), isNull);
  });
}
