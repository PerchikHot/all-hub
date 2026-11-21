import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/eyra_forge_privacy.dart';

void main() {
  test('local Forge endpoints do not require remote consent', () {
    expect(forgeRequiresRemoteConsent('http://127.0.0.1:7860'), isFalse);
    expect(forgeRequiresRemoteConsent('http://localhost:7860'), isFalse);
    expect(forgeRequiresRemoteConsent('http://[::1]:7860'), isFalse);
  });

  test('LAN, internet and malformed endpoints require consent', () {
    expect(forgeRequiresRemoteConsent('http://192.168.1.25:7860'), isTrue);
    expect(forgeRequiresRemoteConsent('https://forge.example.com'), isTrue);
    expect(forgeRequiresRemoteConsent('not an endpoint'), isTrue);
    expect(forgeRequiresRemoteConsent('http://user:pass@localhost:7860'), isTrue);
  });
}
