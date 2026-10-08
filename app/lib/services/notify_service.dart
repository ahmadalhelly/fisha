// Native notifications: an Android foreground service (flutter_foreground_task + flutter_local_notifications)
// on the phone; a no-op on the web build, where neither plugin exists.
export 'notify_service_io.dart' if (dart.library.js_interop) 'notify_service_web.dart';
