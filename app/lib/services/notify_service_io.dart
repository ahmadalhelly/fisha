import 'dart:convert';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../i18n.dart';

/// Native phone notifications: a small Android foreground service keeps a connection to the
/// hub's server topic and turns every hub event into a real notification, even when Fisha is closed.
class NotifyService {
  static const _prefKey = 'nativeNotify';

  static void initPort() => FlutterForegroundTask.initCommunicationPort();

  static void _init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'fisha_service',
        channelName: 'Fisha background',
        channelDescription: 'Keeps Fisha listening for alerts from the hub',
        channelImportance: NotificationChannelImportance.MIN,
        priority: NotificationPriority.MIN,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false, playSound: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(60000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  static Future<bool> isEnabled() async => (await SharedPreferences.getInstance()).getBool(_prefKey) ?? false;

  /// Starts the service if the user turned native notifications on.
  static Future<void> resume() async {
    if (!await isEnabled()) return;
    _init();
    if (!await FlutterForegroundTask.isRunningService) await _start();
  }

  static Future<bool> enable() async {
    if (await FlutterForegroundTask.checkNotificationPermission() != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    if (await FlutterForegroundTask.checkNotificationPermission() != NotificationPermission.granted) return false;
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
    (await SharedPreferences.getInstance()).setBool(_prefKey, true);
    _init();
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.restartService();
    } else {
      await _start();
    }
    return true;
  }

  static Future<void> disable() async {
    (await SharedPreferences.getInstance()).setBool(_prefKey, false);
    if (await FlutterForegroundTask.isRunningService) await FlutterForegroundTask.stopService();
  }

  static Future<void> _start() => FlutterForegroundTask.startService(
        serviceId: 4711,
        notificationTitle: 'Fisha',
        notificationText: Tr.isAr ? 'بيستنى تنبيهات المشتركات' : 'Listening for strip alerts',
        callback: notifyCallback,
      );
}

@pragma('vm:entry-point')
void notifyCallback() {
  FlutterForegroundTask.setTaskHandler(_NotifyHandler());
}

class _NotifyHandler extends TaskHandler {
  static const _types = ['temp', 'load', 'auto_off', 'automation', 'schedule', 'missed', 'timer', 'cycle', 'lock', 'added', 'test',
      'button', 'remote', 'online', 'offline', 'voltage'];

  final _notes = FlutterLocalNotificationsPlugin();
  MqttServerClient? _client;
  String _base = '';
  Map<String, dynamic> _state = {};
  int _id = 1;
  DateTime _startedAt = DateTime.now();
  bool _connecting = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _startedAt = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    final lang = prefs.getInt('langPref') ?? 0;
    Tr.lang = lang == 2 ? 'en' : (lang == 1 ? 'ar' : (Platform.localeName.startsWith('en') ? 'en' : 'ar'));
    await _notes.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    await _connect();
  }

  Future<void> _connect() async {
    if (_connecting || (_client?.connectionStatus?.state == MqttConnectionState.connected)) return;
    _connecting = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('settings');
      if (raw == null) return;
      final s = jsonDecode(raw) as Map<String, dynamic>;
      final host = (s['brokerHost'] ?? '').toString(), user = (s['username'] ?? '').toString(), pass = (s['password'] ?? '').toString();
      final hub = (s['hubId'] ?? '').toString();
      if (host.isEmpty || user.isEmpty || pass.isEmpty || hub.isEmpty) return;
      _base = 'mttl/$hub';
      final id = 'bg-${DateTime.now().millisecondsSinceEpoch % 1000000000}';
      final c = MqttServerClient.withPort(host, id, (s['brokerPort'] as num?)?.toInt() ?? 8883);
      c.secure = true;
      c.securityContext = SecurityContext.defaultContext;
      c.keepAlivePeriod = 60;
      c.autoReconnect = true;
      c.logging(on: false);
      c.setProtocolV311();
      c.connectionMessage = MqttConnectMessage().withClientIdentifier(id).startClean();
      _client?.disconnect();
      _client = c;
      await c.connect(user, pass);
      c.updates?.listen((msgs) {
        for (final m in msgs) {
          final p = m.payload;
          if (p is! MqttPublishMessage) continue;
          _onMessage(m.topic, utf8.decode(p.payload.message.toList(), allowMalformed: true));
        }
      });
      c.subscribe('$_base/state', MqttQos.atMostOnce);
      c.subscribe('$_base/event', MqttQos.atLeastOnce);
    } catch (_) {
      // no internet right now; the repeat event retries
    } finally {
      _connecting = false;
    }
  }

  void _onMessage(String topic, String text) {
    try {
      final j = jsonDecode(text) as Map<String, dynamic>;
      if (topic == '$_base/state') {
        _state = j;
      } else if (topic == '$_base/event') {
        _onEvent(j);
      }
    } catch (_) {}
  }

  Map<String, dynamic>? _strip(String mac) {
    final devs = _state['devices'];
    if (devs is! List) return null;
    for (final d in devs) {
      if (d is Map<String, dynamic> && (d['mac'] ?? '').toString().toUpperCase() == mac) return d;
    }
    return null;
  }

  void _onEvent(Map<String, dynamic> e) {
    final type = (e['type'] ?? '').toString();
    final mac = (e['mac'] ?? '').toString().toUpperCase();
    final outlet = (e['outlet'] as num?)?.toInt() ?? 0;
    final msg = (e['msg'] ?? '').toString();
    final ts = (e['ts'] as num?)?.toInt() ?? 0;
    if (ts > 0 && DateTime.fromMillisecondsSinceEpoch(ts * 1000).isBefore(_startedAt.subtract(const Duration(minutes: 2)))) return;
    // same filters the user set in the app (stored on the hub)
    final cfg = _state['config'];
    final types = cfg is Map ? (cfg['ntypes'] as num?)?.toInt() ?? 0xFFFFFFFF : 0xFFFFFFFF;
    final bit = _types.indexOf(type);
    if (type != 'test' && (bit < 0 || types & (1 << bit) == 0)) return;
    final strip = mac.isEmpty ? null : _strip(mac);
    if (strip != null) {
      final mask = (strip['notify'] as num?)?.toInt() ?? 0x1F;
      if (outlet == 0 ? mask & 0x10 == 0 : mask & (1 << (outlet - 1)) == 0) return;
    }
    var stripName = '';
    if (strip != null) {
      final label = (strip['label'] ?? '').toString();
      stripName = label.isNotEmpty ? label : t('default_strip', {'id': mac.length > 4 ? mac.substring(mac.length - 4) : mac});
    } else if (mac.isNotEmpty) {
      stripName = t('default_strip', {'id': mac.length > 4 ? mac.substring(mac.length - 4) : mac});
    }

    var outletName = '';
    if (strip != null && outlet > 0) {
      final outs = strip['outlets'];
      var ol = '';
      if (outs is List) {
        for (final o in outs) {
          if (o is Map && (o['n'] as num?)?.toInt() == outlet) ol = (o['label'] ?? '').toString();
        }
      }
      outletName = ol.isNotEmpty ? ol : t('default_outlet', {'n': outlet});
    } else if (outlet > 0) {
      outletName = t('default_outlet', {'n': outlet});
    }

    final isAr = Tr.isAr;
    final isOn = msg == 'on' || msg == '1';
    final targetName = outletName.isNotEmpty ? outletName : (stripName.isNotEmpty ? stripName : (isAr ? 'المخرج' : 'Outlet'));

    final String title;
    final String body;

    if (type == 'button' || type == 'remote') {
      if (isAr) {
        title = isOn ? '«$targetName» اشتغل' : '«$targetName» اتقفل';
        final source = type == 'button' ? 'من زرار المشترك' : 'من التطبيق';
        body = stripName.isNotEmpty && stripName != targetName ? '$stripName · $source' : source;
      } else {
        title = isOn ? '"$targetName" turned on' : '"$targetName" turned off';
        final source = type == 'button' ? 'Strip button' : 'From app';
        body = stripName.isNotEmpty && stripName != targetName ? '$stripName · $source' : source;
      }
    } else if (type == 'automation') {
      final defaultTitle = isAr ? 'أتمتة' : 'Automation';
      title = (msg.isNotEmpty && msg != 'on' && msg != 'off' && msg != '1' && msg != '0') ? msg : defaultTitle;
      final who = [
        if (stripName.isNotEmpty) stripName,
        if (outletName.isNotEmpty) outletName,
      ].join(' · ');
      body = who.isNotEmpty ? who : (isAr ? 'أتمتة اتنفذت' : 'Automation ran');
    } else {
      title = switch (type) {
        'temp' => isAr ? 'حرارة عالية' : 'High temperature',
        'load' => isAr ? 'حمل عالي' : 'High load',
        'auto_off' => isAr ? 'قفل تلقائي' : 'Auto-off',
        'schedule' => isAr ? 'جدولة اتنفذت' : 'Schedule ran',
        'missed' => isAr ? 'أمر ما اتنفذش' : 'Command missed',
        'timer' => isAr ? 'تايمر خلص' : 'Timer finished',
        'cycle' => isAr ? 'إعادة تشغيل' : 'Reboot',
        'lock' => isAr ? 'قفل الأطفال' : 'Child lock',
        'added' => isAr ? 'مشترك جديد' : 'New strip',
        'online' => isAr ? 'المشترك رجع' : 'Back online',
        'offline' => isAr ? 'المشترك فصل' : 'Strip offline',
        'voltage' => isAr ? 'فولت غير طبيعي' : 'Unusual voltage',
        'test' => 'Fisha ✓',
        _ => t('nt_$type'),
      };
      final who = [
        if (stripName.isNotEmpty) stripName,
        if (outletName.isNotEmpty) outletName,
      ].join(' · ');
      final extraMsg = (msg.isNotEmpty && msg != 'on' && msg != 'off' && msg != '1' && msg != '0') ? msg : '';
      if (who.isNotEmpty) {
        body = extraMsg.isNotEmpty ? '$who — $extraMsg' : who;
      } else {
        body = extraMsg.isNotEmpty ? extraMsg : (type == 'test' ? (isAr ? 'إشعار تجربة من الـ Hub' : 'Test notification from the hub') : title);
      }
    }

    final urgent = type == 'temp' || type == 'load' || type == 'voltage' || type == 'offline';
    _notes.show(
      id: _id++,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          urgent ? 'fisha_urgent' : 'fisha_alerts',
          urgent ? 'Fisha urgent alerts' : 'Fisha alerts',
          importance: urgent ? Importance.max : Importance.high,
          priority: urgent ? Priority.max : Priority.high,
        ),
      ),
    );
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _connect();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _client?.autoReconnect = false;
    _client?.disconnect();
  }
}
