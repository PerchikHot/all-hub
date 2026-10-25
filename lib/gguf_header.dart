import 'dart:io';
import 'dart:typed_data';

/// GGUF container header only. This does not load tensors or run inference.
class GgufHeader {
  const GgufHeader({required this.version, required this.tensorCount, required this.metadataCount, required this.bytes});
  final int version;
  final int tensorCount;
  final int metadataCount;
  final int bytes;

  static Future<GgufHeader?> read(String path) async {
    RandomAccessFile? file;
    try {
      file = await File(path).open();
      final size = await file.length();
      if (size < 24) return null;
      final data = await file.read(24);
      if (data.length != 24 || data[0] != 0x47 || data[1] != 0x47 ||
          data[2] != 0x55 || data[3] != 0x46) {
        return null;
      }
      final view = ByteData.sublistView(Uint8List.fromList(data));
      final version = view.getUint32(4, Endian.little);
      if (version < 2 || version > 3) return null;
      final tensorCount = view.getUint64(8, Endian.little);
      final metadataCount = view.getUint64(16, Endian.little);
      if (tensorCount == 0 || tensorCount > 10000000 || metadataCount > 1000000) return null;
      return GgufHeader(version: version, tensorCount: tensorCount, metadataCount: metadataCount, bytes: size);
    } catch (_) {
      return null;
    } finally {
      await file?.close();
    }
  }
}
