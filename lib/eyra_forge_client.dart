import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// Stable Diffusion WebUI Forge API client. No model weights or private
/// images are stored in the repository.
class EyraForgeClient {
  EyraForgeClient(this.endpoint, {http.Client? client})
      : _client = client ?? http.Client(), _ownsClient = client == null;
  final Uri endpoint;
  final http.Client _client;
  final bool _ownsClient;

  Uri _url(String path) {
    if (endpoint.scheme != 'http' && endpoint.scheme != 'https') {
      throw const FormatException('Forge: требуется адрес http(s)');
    }
    return endpoint.replace(path: path, query: null, fragment: null);
  }

  Future<bool> checkConnection() async {
    final response = await _client.get(_url('/sdapi/v1/sd-models'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw StateError('Forge HTTP ${response.statusCode}');
    }
    return jsonDecode(response.body) is List;
  }

  Future<List<String>> models() async {
    final response = await _client.get(_url('/sdapi/v1/sd-models'))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError('Forge HTTP ${response.statusCode}');
    }
    return (jsonDecode(response.body) as List)
        .whereType<Map>().map((m) => m['title']?.toString() ?? '')
        .where((s) => s.isNotEmpty).toList();
  }

  Future<Uint8List> generate({
    required String prompt,
    String negativePrompt = '',
    int width = 512,
    int height = 512,
    int steps = 20,
    int seed = -1,
  }) async {
    if (prompt.trim().isEmpty) throw ArgumentError('Пустой промпт');
    if (width < 256 || width > 2048 || height < 256 || height > 2048 ||
        width % 8 != 0 || height % 8 != 0 || steps < 1 || steps > 100) {
      throw ArgumentError('Некорректные параметры генерации');
    }
    final response = await _client.post(
      _url('/sdapi/v1/txt2img'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'prompt': prompt.trim(),
        'negative_prompt': negativePrompt,
        'width': width,
        'height': height,
        'steps': steps,
        'seed': seed,
        'batch_size': 1,
        'n_iter': 1,
        'save_images': false,
      }),
    ).timeout(const Duration(minutes: 10));
    if (response.statusCode != 200) {
      throw StateError('Forge HTTP ${response.statusCode}: ${response.body.length > 300 ? response.body.substring(0, 300) : response.body}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final images = decoded['images'];
    if (images is! List || images.isEmpty || images.first is! String) {
      throw const FormatException('Forge не вернул изображение');
    }
    final encoded = (images.first as String).split(',').last;
    return base64Decode(encoded);
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
