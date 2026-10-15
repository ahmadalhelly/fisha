import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android only: keeps Fisha running (foreground service + progress notification) while an update
/// downloads or uploads, so leaving the app for another one doesn't cut it.
class UpdateKeepAlive {
  static const _ch = MethodChannel('fisha/keepalive');
  static bool get _on => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> start(String title, String text) async {
    if (!_on) return;
    _last = -1;
    try {
      await _ch.invokeMethod('start', {'title': title, 'text': text});
    } catch (_) {}
  }

  static int _last = -1;

  static Future<void> progress(String title, String text, double p) async {
    if (!_on) return;
    final pct = (p * 100).round().clamp(0, 100);
    if (pct == _last) return;
    _last = pct;
    try {
      await _ch.invokeMethod('progress', {'title': title, 'text': text, 'pct': pct});
    } catch (_) {}
  }

  static Future<void> stop() async {
    if (!_on) return;
    try {
      await _ch.invokeMethod('stop');
    } catch (_) {}
  }

  /// The installer can't be opened from the background: a notification does it on tap.
  static Future<void> installReady(String path, String title, String text) async {
    if (!_on) return;
    try {
      await _ch.invokeMethod('installReady', {'path': path, 'title': title, 'text': text});
    } catch (_) {}
  }
}
