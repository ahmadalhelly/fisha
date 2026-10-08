// MQTT client per platform: MqttServerClient (dart:io, TLS socket) on the phone,
// MqttBrowserClient (secure WebSocket) on the web build. Neither platform imports the other's library.
export 'mqtt_factory_io.dart' if (dart.library.js_interop) 'mqtt_factory_web.dart';
