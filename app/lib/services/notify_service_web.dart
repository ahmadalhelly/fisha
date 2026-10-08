/// Web build: no background service and no native notifications (see WEB.md). Same API as notify_service_io.dart.
class NotifyService {
  static void initPort() {}

  static Future<bool> isEnabled() async => false;

  static Future<void> resume() async {}

  static Future<bool> enable() async => false;

  static Future<void> disable() async {}
}
