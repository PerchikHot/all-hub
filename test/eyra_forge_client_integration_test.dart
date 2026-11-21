import 'dart:convert';
import 'dart:typed_data';

import 'package:all_hub/eyra_forge_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _png = Uint8List.fromList(<int>[137, 80, 78, 71, 13, 10, 26, 10, 0]);

void main() {
  test('lists models from local Forge and uses the expected API route', () async {
    final paths = <String>[];
    final client = EyraForgeClient(
      Uri.parse('http://127.0.0.1:7860'),
      client: MockClient((request) async {
        paths.add(request.url.path);
        return http.Response(jsonEncode([
          {'title': 'model A'}, {'title': ''}, {'other': 'ignored'}
        ]), 200);
      }),
    );
    expect(await client.models(), ['model A']);
    expect(paths, ['/sdapi/v1/sd-models']);
    client.close();
  });

  test('txt2img sends a bounded single image request without saving remotely', () async {
    final client = EyraForgeClient(
      Uri.parse('http://127.0.0.1:7860'),
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/sdapi/v1/txt2img');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['prompt'], 'mountains');
        expect(body['batch_size'], 1);
        expect(body['n_iter'], 1);
        expect(body['save_images'], false);
        expect(body['override_settings'], {'sd_model_checkpoint': 'safe model'});
        return http.Response(jsonEncode({'images': [base64Encode(_png)]}), 200);
      }),
    );
    expect(await client.generate(prompt: ' mountains ', checkpoint: 'safe model'), _png);
    client.close();
  });

  test('img2img transmits only the explicitly selected image', () async {
    final client = EyraForgeClient(
      Uri.parse('http://127.0.0.1:7860'),
      client: MockClient((request) async {
        expect(request.url.path, '/sdapi/v1/img2img');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(base64Decode((body['init_images'] as List).single as String), _png);
        expect(body['denoising_strength'], 0.35);
        expect(body['save_images'], false);
        return http.Response(jsonEncode({'images': [base64Encode(_png)]}), 200);
      }),
    );
    expect(await client.edit(source: _png, prompt: 'enhance', denoisingStrength: 0.35), _png);
    client.close();
  });

  test('invalid prompt and image fail before any network request', () async {
    var calls = 0;
    final client = EyraForgeClient(
      Uri.parse('http://127.0.0.1:7860'),
      client: MockClient((request) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(client.generate(prompt: ''), throwsArgumentError);
    await expectLater(client.generate(prompt: 'a', width: 513), throwsArgumentError);
    await expectLater(client.edit(source: Uint8List(12), prompt: 'a'), throwsFormatException);
    await expectLater(client.edit(source: _png, prompt: 'a', denoisingStrength: 2), throwsArgumentError);
    expect(calls, 0);
    client.close();
  });

  test('bad Forge response is rejected rather than displayed as an image', () async {
    final client = EyraForgeClient(
      Uri.parse('http://127.0.0.1:7860'),
      client: MockClient((request) async =>
        http.Response(jsonEncode({'images': [base64Encode(utf8.encode('not an image'))]}), 200)),
    );
    await expectLater(client.generate(prompt: 'a'), throwsFormatException);
    client.close();
  });

  test('server errors and malformed model lists are reported', () async {
    final unavailable = EyraForgeClient(
      Uri.parse('http://127.0.0.1:7860'),
      client: MockClient((request) async => http.Response('unavailable', 503)),
    );
    await expectLater(unavailable.generate(prompt: 'a'), throwsStateError);
    unavailable.close();
    final malformed = EyraForgeClient(
      Uri.parse('http://127.0.0.1:7860'),
      client: MockClient((request) async => http.Response('{}', 200)),
    );
    await expectLater(malformed.models(), throwsFormatException);
    malformed.close();
  });

  test('credentials and query parameters in Forge URL are refused', () {
    for (final endpoint in [
      'http://user:secret@localhost:7860',
      'http://localhost:7860/?token=private',
      'file:///tmp/forge',
    ]) {
      final client = EyraForgeClient(Uri.parse(endpoint),
        client: MockClient((request) async => http.Response('{}', 200)));
      expect(() => client.url('/sdapi/v1/txt2img'), throwsFormatException);
      client.close();
    }
  });
}
