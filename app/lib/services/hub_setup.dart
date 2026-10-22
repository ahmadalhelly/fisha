import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// sets a new hub up without leaving the app. Android joins the hub's own network (Fisha-Hub-XXXX) through
/// a native channel, the app sends Wi-Fi + address + owner to 192.168.4.1 in one request, then goes back home.
class HubSetup {
  static const _ch = MethodChannel('fisha/wifi');
  static const portal = 'http://192.168.4.1';

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Location (and nearby Wi-Fi on Android 13+) is what lets the app read the Wi-Fi name and see the hub's network.
  static Future<bool> permission({bool ask = false}) async {
    if (!supported) return false;
    try {
      return await _ch.invokeMethod<bool>('permission', {'ask': ask}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<String> currentSsid() async {
    if (!supported) return '';
    try {
      return await _ch.invokeMethod<String>('currentSsid') ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<List<String>> scanHubs() async {
    if (!supported) return const [];
    try {
      final l = await _ch.invokeMethod<List<dynamic>>('scanHubs');
      return [for (final x in l ?? const []) x.toString()];
    } catch (_) {
      return const [];
    }
  }

  /// 'ok' (this app now talks over the hub's network), 'fail', or 'manual' (older Android: join it in settings).
  static Future<String> joinHub(String ssid) async {
    if (!supported) return 'manual';
    try {
      return await _ch.invokeMethod<String>('joinHub', {'ssid': ssid}).timeout(const Duration(seconds: 70)) ?? 'fail';
    } catch (_) {
      return 'fail';
    }
  }

  static Future<void> releaseHub() async {
    if (!supported) return;
    try {
      await _ch.invokeMethod('releaseHub');
    } catch (_) {}
  }

  /// {hub, fw, claimed, claim_open, ip, gw} from a hub in setup mode, or null.
  static Future<Map<String, dynamic>?> info() async {
    for (var i = 0; i < 4; i++) {
      try {
        final r = await http.get(Uri.parse('$portal/api/setup/info')).timeout(const Duration(seconds: 4));
        final j = jsonDecode(r.body);
        if (j is Map && j['data'] is Map) return Map<String, dynamic>.from(j['data'] as Map);
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 1));
    }
    return null;
  }

  /// Returns ({key, hub, ip}) or an error code in [error].
  static Future<({String key, String hub, String ip, String? error})> send(Map<String, dynamic> body) async {
    try {
      final r = await http
          .post(Uri.parse('$portal/api/setup'), headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(const Duration(seconds: 10));
      final j = jsonDecode(r.body);
      if (j is Map && j['ok'] == true && j['data'] is Map) {
        final d = j['data'] as Map;
        return (key: (d['key'] ?? '').toString(), hub: (d['hub'] ?? '').toString(), ip: (d['ip'] ?? '').toString(), error: null);
      }
      return (key: '', hub: '', ip: '', error: (j is Map ? j['error'] : null)?.toString() ?? 'failed');
    } catch (_) {
      return (key: '', hub: '', ip: '', error: 'net');
    }
  }
}
