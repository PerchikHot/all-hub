import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/eyra_forge_privacy.dart';

void main() {
  test('loopback Forge does not require remote disclosure', () {
    expect(forgeRequiresRemoteConsent('http://127.0.0.1:7860'), isFalse);
    expect(forgeRequiresRemoteConsent('http://localhost:7860'), isFalse);
    expect(forgeRequiresRemoteConsent('http://[::1]:7860'), isFalse);
  });
  test('LAN, public, and malformed endpoints require disclosure', () {
    expect(forgeRequiresRemoteConsent('http://192.168.1.20:7860'), isTrue);
    expect(forgeRequiresRemoteConsent('https://forge.example.com'), isTrue);
    expect(forgeRequiresRemoteConsent('not a url'), isTrue);
    expect(forgeRequiresRemoteConsent('http://user:pass@localhost:7860'), isTrue);
  });
}
