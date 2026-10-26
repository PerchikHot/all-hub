import 'dart:ffi';
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
