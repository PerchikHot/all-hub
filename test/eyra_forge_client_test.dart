import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:all_hub/eyra_forge_client.dart';

void main() {
  test('Forge model discovery uses the expected endpoint', () async {
    final client = EyraForgeClient(Uri.parse('http://127.0.0.1:7860'),
      client: MockClient((request) async {
        expect(request.url.path, '/sdapi/v1/sd-models');
        return http.Response('[{"title":"model-a"}]', 200);
      }));
    expect(await client.models(), ['model-a']);
    client.close();
  });

  test('Forge rejects invalid addresses before network requests', () async {
    final client = EyraForgeClient(Uri.parse('file:///tmp/forge'),
      client: MockClient((_) async => throw StateError('network should not run')));
    await expectLater(client.models(), throwsFormatException);
  });

  test('Forge rejects invalid dimensions before network requests', () async {
    final client = EyraForgeClient(Uri.parse('http://localhost:7860'),
      client: MockClient((_) async => throw StateError('network should not run')));
    await expectLater(client.generate(prompt: 'cat', width: 1025),
      throwsArgumentError);
  });

  test('Forge sends one batch and validates image bytes', () async {
    final png = <int>[137, 80, 78, 71, 13, 10, 26, 10, 0];
    final client = EyraForgeClient(Uri.parse('http://localhost:7860'),
      client: MockClient((request) async {
        expect(request.url.path, '/sdapi/v1/txt2img');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['prompt'], 'cat');
        expect(body['batch_size'], 1);
        expect(body['save_images'], false);
        return http.Response(jsonEncode({'images': [base64Encode(png)]}), 200);
      }));
    expect(await client.generate(prompt: 'cat'), png);
  });

  test('Forge rejects malformed generation responses', () async {
    final client = EyraForgeClient(Uri.parse('http://localhost:7860'),
      client: MockClient((_) async => http.Response('{"images":[]}', 200)));
    await expectLater(client.generate(prompt: 'cat'), throwsFormatException);
  });
  test('Forge rejects invalid prompts and oversized steps before connecting', () async {
    var calls = 0;
    final client = EyraForgeClient(Uri.parse('http://localhost:7860'),
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }));
    await expectLater(client.generate(prompt: '  '), throwsArgumentError);
    await expectLater(client.generate(prompt: 'cat', steps: 51), throwsArgumentError);
    await expectLater(client.generate(prompt: 'cat', width: 513), throwsArgumentError);
    expect(calls, 0);
  });

  test('Forge returns useful errors for unavailable API and invalid images', () async {
    final offline = EyraForgeClient(Uri.parse('http://localhost:7860'),
      client: MockClient((_) async => http.Response('unavailable', 503)));
    await expectLater(offline.models(), throwsStateError);
    await expectLater(offline.generate(prompt: 'cat'), throwsStateError);
    final invalid = EyraForgeClient(Uri.parse('http://localhost:7860'),
      client: MockClient((_) async => http.Response(
        jsonEncode({'images': [base64Encode([1, 2, 3, 4, 5, 6, 7, 8])]}), 200)));
    await expectLater(invalid.generate(prompt: 'cat'), throwsFormatException);
  });

  test('Forge img2img sends selected image only on explicit edit', () async {
    final png = <int>[137, 80, 78, 71, 13, 10, 26, 10, 0];
    var requests = 0;
    final client = EyraForgeClient(Uri.parse('http://localhost:7860'),
      client: MockClient((request) async {
        requests++;
        expect(request.url.path, '/sdapi/v1/img2img');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['init_images'], [base64Encode(png)]);
        expect(body['denoising_strength'], 0.4);
        expect(body['save_images'], false);
        expect(body['prompt'], 'new outfit');
        return http.Response(jsonEncode({'images': [base64Encode(png)]}), 200);
      }));
    expect(requests, 0);
    expect(await client.edit(source: Uint8List.fromList(png),
      prompt: 'new outfit', denoisingStrength: 0.4), png);
    expect(requests, 1);
  });

  test('Forge img2img rejects invalid input without uploading', () async {
    var requests = 0;
    final client = EyraForgeClient(Uri.parse('http://localhost:7860'),
      client: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }));
    final png = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 0]);
    await expectLater(client.edit(source: Uint8List.fromList([1, 2, 3]),
      prompt: 'test'), throwsFormatException);
    await expectLater(client.edit(source: png, prompt: 'test',
      denoisingStrength: 1.5), throwsArgumentError);
    await expectLater(client.edit(source: png, prompt: ' '),
      throwsArgumentError);
    expect(requests, 0);
  });

  test('Forge checkpoint override is scoped to both generation modes', () async {
    final png = <int>[137, 80, 78, 71, 13, 10, 26, 10, 0];
    final overrides = <dynamic>[];
    final client = EyraForgeClient(Uri.parse('http://localhost:7860'),
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        overrides.add(body['override_settings']);
        return http.Response(jsonEncode({'images': [base64Encode(png)]}), 200);
      }));
    await client.generate(prompt: 'cat', checkpoint: 'Model A [abc]');
    await client.edit(source: Uint8List.fromList(png), prompt: 'cat',
      checkpoint: 'Model B [def]');
    await client.generate(prompt: 'cat');
    expect(overrides, [
      {'sd_model_checkpoint': 'Model A [abc]'},
      {'sd_model_checkpoint': 'Model B [def]'},
      null,
    ]);
    client.close();
  });

  test('Forge rejects malformed checkpoint before making a request', () async {
    var requests = 0;
    final client = EyraForgeClient(Uri.parse('http://localhost:7860'),
      client: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }));
    await expectLater(client.generate(prompt: 'cat', checkpoint: ''),
      throwsArgumentError);
    await expectLater(client.generate(prompt: 'cat', checkpoint: 'bad\\nmodel'),
      throwsArgumentError);
    expect(requests, 0);
    client.close();
  });
}
