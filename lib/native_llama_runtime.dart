import 'dart:ffi';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';

/// Native runtime detection for the future llama.cpp integration.
/// A shared library alone is not proof that a model can be loaded.
class NativeLlamaRuntime {
  static const libraryName = 'liballhub_llama.so';

  static String get availability {
    if (!Platform.isAndroid) {
      return 'Нативный GGUF-движок для этой платформы пока не подключён';
    }
    try {
      final library = DynamicLibrary.open(libraryName);
      // A versioned bridge symbol is required to avoid accidentally calling
      // an incompatible upstream llama.cpp ABI.
      final version = library.lookupFunction<Int32 Function(), int Function()>(
        'allhub_llama_bridge_version',
      );
      if (version() != 1) {
        return 'Найден несовместимый нативный движок';
      }
      final ready = library.lookupFunction<Int32 Function(), int Function()>(
        'allhub_llama_inference_ready',
      );
      if (ready() == 1) {
        return 'Нативный мост сообщает о готовности к инференсу';
      }
      try {
        final llama = DynamicLibrary.open('libllama.so');
        llama.lookup<NativeFunction<Void Function()>>('llama_backend_init');
        return 'llama.cpp найден в APK; загрузка GGUF и генерация ещё не подключены';
      } on Object catch (_) {
        return 'Нативный мост найден, но библиотека llama.cpp недоступна';
      }
    } on ArgumentError {
      return 'Нативный GGUF-движок не установлен в APK';
    } on Object catch (_) {
      return 'Не удалось проверить нативный GGUF-движок';
    }
  }
}


/// Loads and releases the model in a worker isolate; this does not generate text.
/// This may take time and consume as much RAM as the model itself.
Future<bool> verifyNativeGgufLoad(String path) {
  return Isolate.run(() => _verifyNativeGgufLoad(path));
}

bool _verifyNativeGgufLoad(String path) {
  if (!Platform.isAndroid) return false;
  final bytes = utf8.encode(path);
  final libc = DynamicLibrary.open('libc.so');
  final malloc = libc.lookupFunction<Pointer<Void> Function(IntPtr), Pointer<Void> Function(int)>('malloc');
  final free = libc.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('free');
  final pointer = malloc(bytes.length + 1);
  if (pointer == nullptr) return false;
  try {
    final buffer = pointer.cast<Uint8>().asTypedList(bytes.length + 1);
    buffer.setRange(0, bytes.length, bytes);
    buffer[bytes.length] = 0;
    final bridge = DynamicLibrary.open(NativeLlamaRuntime.libraryName);
    final load = bridge.lookupFunction<Int32 Function(Pointer<Uint8>), int Function(Pointer<Uint8>)>(
      'allhub_llama_try_load_model',
    );
    return load(pointer.cast<Uint8>()) == 1;
  } finally {
    free(pointer);
  }
}

typedef _GenerateNative = Int32 Function(
  Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>, Int32, Int32);
typedef _GenerateDart = int Function(
  Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>, int, int);

/// Generate a short response in a worker isolate to keep the UI responsive.
Future<String> generateNativeGguf(String path, String prompt, {int maxTokens = 128}) =>
    Isolate.run(() => _generateNativeGguf(path, prompt, maxTokens));

String _generateNativeGguf(String path, String prompt, int maxTokens) {
  if (!Platform.isAndroid) throw UnsupportedError('Only Android ARM64 is supported');
  final libc = DynamicLibrary.open('libc.so');
  final malloc = libc.lookupFunction<Pointer<Void> Function(IntPtr), Pointer<Void> Function(int)>('malloc');
  final free = libc.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('free');
  Pointer<Uint8> allocateUtf8(String value) {
    final bytes = utf8.encode(value);
    final ptr = malloc(bytes.length + 1).cast<Uint8>();
    if (ptr == nullptr) throw StateError('Out of memory');
    ptr.asTypedList(bytes.length + 1)
      ..setRange(0, bytes.length, bytes)
      ..[bytes.length] = 0;
    return ptr;
  }
  final model = allocateUtf8(path);
  Pointer<Uint8>? input;
  Pointer<Uint8>? output;
  try {
    input = allocateUtf8(prompt);
    output = malloc(32768).cast<Uint8>();
    if (output == nullptr) throw StateError('Out of memory');
    final bridge = DynamicLibrary.open(NativeLlamaRuntime.libraryName);
    final generate = bridge.lookupFunction<_GenerateNative, _GenerateDart>('allhub_llama_generate');
    final length = generate(model, input, output, 32768, maxTokens);
    if (length < 0) throw StateError('llama.cpp error $length');
    return utf8.decode(output.asTypedList(length), allowMalformed: true);
  } finally {
    free(model);
    if (input != null) free(input);
    if (output != null) free(output);
  }
}
