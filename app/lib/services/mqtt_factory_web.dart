import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_client.dart';

/// EMQX Cloud: MQTT over secure WebSockets is served on this port, path /mqtt.
const int webMqttPort = 8084;

/// Web: a browser has no raw TCP sockets, so MQTT runs over wss://[host]:8084/mqtt.
/// [port] (the TLS port in the settings, 8883) does not apply here and is ignored.
MqttClient createMqttClient(String host, String clientId, int port) {
  final c = MqttBrowserClient.withPort('wss://$host/mqtt', clientId, webMqttPort);
  c.websocketProtocols = const <String>['mqtt'];
  return c;
}
