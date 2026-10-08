// Reading/writing a file by path: dart:io on the phone; not available on the web build
// (there file_picker hands over bytes and downloads saved files itself).
export 'file_io_io.dart' if (dart.library.js_interop) 'file_io_web.dart';
