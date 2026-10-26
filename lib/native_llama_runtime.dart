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
