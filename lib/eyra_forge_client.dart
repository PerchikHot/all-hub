import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// A deliberately bounded client for the user's own Forge WebUI API.
/// Never sends prompts or images until generate() is explicitly called.
class EyraForgeClient {
  EyraForgeClient(Uri endpoint, {http.Client? client})
      : endpoint = endpoint,
        _client = client ?? http.Client(),
        _ownsClient = client == null;
  final Uri endpoint;
  final http.Client _client;
  final bool _ownsClient;

  Uri url(String path) {
    if (!['http', 'https'].contains(endpoint.scheme) ||
        endpoint.host.isEmpty || endpoint.userInfo.isNotEmpty ||
        endpoint.query.isNotEmpty || endpoint.fragment.isNotEmpty) {
      throw const FormatException('Укажите адрес Forge http(s) без логина, параметров и фрагмента');
    }
    return endpoint.replace(path: path, query: null, fragment: null);
  }

  Future<List<String>> models() async {
    final response = await _client.get(url('/sdapi/v1/sd-models'))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw StateError('Forge: HTTP ${response.statusCode}');
    }
    final body = jsonDecode(response.body);
    if (body is! List) throw const FormatException('Forge вернул неверный список моделей');
    return body.whereType<Map>().map((item) => item['title'])
        .whereType<String>().where((name) => name.isNotEmpty).toList();
  }

  Future<Uint8List> generate({
    required String prompt,
    String negativePrompt = '',
    int width = 512,
    int height = 512,
    int steps = 20,
    String? checkpoint,
  }) async {
    _validateParameters(prompt, negativePrompt, width, height, steps);
    _validateCheckpoint(checkpoint);
    final response = await _client.post(url('/sdapi/v1/txt2img'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'prompt': prompt.trim(),
        'negative_prompt': negativePrompt,
        'width': width, 'height': height, 'steps': steps,
        'batch_size': 1, 'n_iter': 1, 'save_images': false,
        if (checkpoint != null) 'override_settings': {'sd_model_checkpoint': checkpoint},
      }),
    ).timeout(const Duration(minutes: 8));
    return _decodeImageResponse(response);
  }

  /// Edit a user-selected PNG/JPEG. The source is never uploaded until called.
  Future<Uint8List> edit({
    required Uint8List source,
    required String prompt,
    String negativePrompt = '',
    int width = 512,
    int height = 512,
    int steps = 20,
    double denoisingStrength = 0.5,
    String? checkpoint,
  }) async {
    if (source.length < 8 || source.length > 12 * 1024 * 1024 ||
        !(_isPng(source) || _isJpeg(source))) {
      throw const FormatException('Выберите PNG/JPEG до 12 МиБ');
    }
    if (denoisingStrength < 0.05 || denoisingStrength > 1 ||
        !denoisingStrength.isFinite) {
      throw ArgumentError('Сила изменения должна быть от 0.05 до 1');
    }
    _validateParameters(prompt, negativePrompt, width, height, steps);
    _validateCheckpoint(checkpoint);
    final response = await _client.post(url('/sdapi/v1/img2img'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'init_images': [base64Encode(source)],
        'prompt': prompt.trim(), 'negative_prompt': negativePrompt,
        'width': width, 'height': height, 'steps': steps,
        'denoising_strength': denoisingStrength,
        'batch_size': 1, 'n_iter': 1, 'save_images': false,
        if (checkpoint != null) 'override_settings': {'sd_model_checkpoint': checkpoint},
      }),
    ).timeout(const Duration(minutes: 8));
    return _decodeImageResponse(response);
  }

  static void _validateCheckpoint(String? checkpoint) {
    if (checkpoint != null && (checkpoint.trim().isEmpty ||
        checkpoint.length > 300 || checkpoint.contains(RegExp(r'[\\r\\n\\x00]')))) {
      throw ArgumentError('Некорректная модель Forge');
    }
  }

  static bool _isPng(List<int> bytes) => bytes.length >= 8 &&
    bytes[0] == 137 && bytes[1] == 80 && bytes[2] == 78 &&
    bytes[3] == 71 && bytes[4] == 13 && bytes[5] == 10 &&
    bytes[6] == 26 && bytes[7] == 10;
  static bool _isJpeg(List<int> bytes) => bytes.length >= 4 &&
    bytes[0] == 255 && bytes[1] == 216 &&
    bytes[bytes.length - 2] == 255 && bytes.last == 217;

  static void _validateParameters(String prompt, String negativePrompt,
      int width, int height, int steps) {
    if (prompt.trim().isEmpty || prompt.length > 4000 ||
        negativePrompt.length > 4000) {
      throw ArgumentError('Промпт должен содержать от 1 до 4000 символов');
    }
    if (width < 256 || width > 1024 || height < 256 || height > 1024 ||
        width % 8 != 0 || height % 8 != 0 || steps < 1 || steps > 50) {
      throw ArgumentError('Размер 256–1024 (кратно 8), шаги 1–50');
    }
  }

  static Uint8List _decodeImageResponse(http.Response response) {
    if (response.statusCode != 200) {
      throw StateError('Forge: HTTP ${response.statusCode}');
    }
    if (response.bodyBytes.length > 24 * 1024 * 1024) {
      throw const FormatException('Ответ Forge превышает 24 МиБ');
    }
    final data = jsonDecode(response.body);
    if (data is! Map || data['images'] is! List ||
        (data['images'] as List).isEmpty ||
        (data['images'] as List).first is! String) {
      throw const FormatException('Forge не вернул изображение');
    }
    final encoded = ((data['images'] as List).first as String).split(',').last;
    if (encoded.length > 24 * 1024 * 1024) {
      throw const FormatException('Изображение слишком большое');
    }
    final bytes = base64Decode(encoded);
    if (!_isPng(bytes) && !_isJpeg(bytes)) {
      throw const FormatException('Forge вернул неподдерживаемое изображение');
    }
    return bytes;
  }

  void close() { if (_ownsClient) _client.close(); }
}
