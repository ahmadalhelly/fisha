// Biometric confirmation: local_auth on the phone; skipped (treated as passed) on the web build.
export 'bio_auth_io.dart' if (dart.library.js_interop) 'bio_auth_web.dart';
