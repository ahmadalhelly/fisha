import 'dart:io';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

/// Phone: MQTT over TLS straight to [host]:[port] (8883 by default).
MqttClient createMqttClient(String host, String clientId, int port) {
  final c = MqttServerClient.withPort(host, clientId, port);
  c.secure = true;
  c.securityContext = SecurityContext.defaultContext;
  return c;
}
