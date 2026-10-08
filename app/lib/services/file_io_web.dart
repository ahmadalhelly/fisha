import 'dart:typed_data';

/// Web build: the browser download already holds the bytes; there is no file system to write to.
Future<void> writeFileIfEmpty(String path, Uint8List bytes) async {}

Future<Uint8List> readFileBytes(String path) async => throw UnsupportedError('no file system on the web');
