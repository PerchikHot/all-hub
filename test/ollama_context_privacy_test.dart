import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/ollama_context_privacy.dart';

void main() {
  test('loopback endpoints may use local memory', () {
    for (final endpoint in [
      'http://127.0.0.1:11434',
      'http://localhost:11434/',
      'http://[::1]:11434',
      'HTTPS://LOCALHOST:11434',
    ]) {
      expect(isLocalOllamaEndpoint(endpoint), isTrue, reason: endpoint);
      expect(maySendOllamaPersonalContext(endpoint, remoteOptIn: false), isTrue);
    }
  });

  test('LAN and public Ollama endpoints require opt-in', () {
    for (final endpoint in [
      'http://192.168.1.5:11434',
      'http://10.0.0.3:11434',
      'https://ollama.example.com',
      'http://8.8.8.8:11434',
      'ftp://localhost:11434',
      'not-a-url',
    ]) {
      expect(isLocalOllamaEndpoint(endpoint), isFalse, reason: endpoint);
      expect(maySendOllamaPersonalContext(endpoint, remoteOptIn: false), isFalse);
      expect(maySendOllamaPersonalContext(endpoint, remoteOptIn: true), isTrue);
    }
  });
  test('remote memory grant is bound to the approved server', () {
    const approved = 'http://192.168.1.5:11434';
    expect(remoteOllamaContextApproved(approved, approved), isTrue);
    expect(remoteOllamaContextApproved('$approved/', approved), isTrue);
    for (final changed in [
      'http://192.168.1.6:11434',
      'http://192.168.1.5:11435',
      'https://192.168.1.5:11434',
      'http://other.example:11434',
      'http://192.168.1.5:11434/another',
    ]) {
      expect(remoteOllamaContextApproved(changed, approved), isFalse,
          reason: changed);
    }
    expect(remoteOllamaContextApproved(approved, null), isFalse);
    expect(remoteOllamaContextApproved('http://127.0.0.1:11434', approved), isFalse);
    expect(remoteOllamaContextApproved('ftp://192.168.1.5:11434', approved), isFalse);
  });

}
