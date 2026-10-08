import 'dart:io';
import 'dart:typed_data';

/// Writes [bytes] to [path] unless the file is already there and non-empty (some pickers save it themselves).
Future<void> writeFileIfEmpty(String path, Uint8List bytes) async {
  final file = File(path);
  if (!file.existsSync() || file.lengthSync() == 0) {
    await file.writeAsBytes(bytes);
  }
}

Future<Uint8List> readFileBytes(String path) => File(path).readAsBytes();
