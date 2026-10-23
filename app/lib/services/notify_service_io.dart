import 'dart:convert';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../i18n.dart';
import 'automation_text.dart';

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

  /// Starts the service if the user turned native notifications on. Also restarts a running service that
  /// has heard nothing from the hub for 3 minutes (it lost the server and did not get it back by itself).
  static Future<void> resume() async {
    if (!await isEnabled()) return;
    _init();
    if (!await FlutterForegroundTask.isRunningService) {
      await _start();
      return;
    }
    final st = await status();
    final last = (st?['msg'] as num?)?.toInt() ?? 0;
    final started = (st?['start'] as num?)?.toInt() ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - last > _staleMs && now - started > _staleMs) await FlutterForegroundTask.restartService();
  }

  static const _staleMs = 180000; // the hub publishes its state at least every 30 s

  /// What the background service last wrote (prefs 'notifyStatus'): {start, msg, alert, conn} in ms since epoch.
  static Future<Map<String, dynamic>?> status() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final raw = prefs.getString('notifyStatus');
      return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// True while the service hears from the hub (a state or event in the last 3 minutes).
  static bool isLive(Map<String, dynamic>? st) =>
      st != null && DateTime.now().millisecondsSinceEpoch - ((st['msg'] as num?)?.toInt() ?? 0) < _staleMs;

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
  final Map<String, Map<String, dynamic>> _strips = {}; // mttl/<hub>/s/<MAC>
  int _id = 1;
  Map<String, dynamic>? _filter; // the app's copy of the user's choices (prefs 'notifyFilter'), when the hub state is missing
  final _seen = <String>[]; // recent events, so one held back by the hub and sent on reconnect never shows twice
  DateTime _startedAt = DateTime.now();
  bool _connecting = false;
  int _lastMsgAt = 0, _lastAlertAt = 0, _connAt = 0, _statusAt = 0; // ms since epoch, for the self-check and the status line

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _startedAt = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    final lang = prefs.getInt('langPref') ?? 0;
    Tr.lang = lang == 2 ? 'en' : (lang == 1 ? 'ar' : (Platform.localeName.startsWith('en') ? 'en' : 'ar'));
    await _notes.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    await _loadFilter();
    await _connect();
    await _saveStatus();
  }

  /// Written for the app (Notifications screen, and resume() on app open).
  Future<void> _saveStatus() async {
    _statusAt = DateTime.now().millisecondsSinceEpoch;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('notifyStatus', jsonEncode({
        'start': _startedAt.millisecondsSinceEpoch,
        'msg': _lastMsgAt,
        'alert': _lastAlertAt,
        'conn': _client?.connectionStatus?.state == MqttConnectionState.connected,
      }));
    } catch (_) {}
  }

  Future<void> _loadFilter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload(); // this isolate's copy does not see the app's writes otherwise
      final f = prefs.getString('notifyFilter');
      _filter = f == null ? null : jsonDecode(f) as Map<String, dynamic>;
    } catch (_) {}
  }

  Future<void> _connect({bool force = false}) async {
    if (_connecting || (!force && _client?.connectionStatus?.state == MqttConnectionState.connected)) return;
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
      final old = _client;
      old?.autoReconnect = false;
      old?.disconnect();
      _client = c;
      await c.connect(user, pass);
      _connAt = DateTime.now().millisecondsSinceEpoch;
      c.updates?.listen((msgs) {
        for (final m in msgs) {
          final p = m.payload;
          if (p is! MqttPublishMessage) continue;
          _onMessage(m.topic, utf8.decode(p.payload.message.toList(), allowMalformed: true));
        }
      });
      c.subscribe('$_base/state', MqttQos.atMostOnce);
      c.subscribe('$_base/s/+', MqttQos.atMostOnce); // each strip on its own topic
      c.subscribe('$_base/event', MqttQos.atLeastOnce);
    } catch (_) {
      // no internet right now; the repeat event retries
    } finally {
      _connecting = false;
    }
  }

  void _onMessage(String topic, String text) {
    _lastMsgAt = DateTime.now().millisecondsSinceEpoch;
    if (_lastMsgAt - _statusAt > 30000) _saveStatus();
    if (topic.startsWith('$_base/s/')) {
      final mac = topic.substring('$_base/s/'.length).toUpperCase();
      try {
        _strips[mac] = jsonDecode(text) as Map<String, dynamic>;
      } catch (_) {
        _strips.remove(mac); // "" = wiped by the hub
      }
      return;
    }
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
    final one = _strips[mac];
    if (one != null) return one;
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
    final key = '$ts|$type|$mac|$outlet|$msg';
    if (ts > 0) {
      if (_seen.contains(key)) return;
      _seen.add(key);
      if (_seen.length > 60) _seen.removeAt(0);
    }
    // same filters the user set in the app (stored on the hub); without the hub's state yet, the app's saved copy
    final cfg = _state['config'];
    final fTypes = (_filter?['types'] as num?)?.toInt();
    final types = cfg is Map && cfg['ntypes'] is num ? (cfg['ntypes'] as num).toInt() : (fTypes ?? 0xFFFFFFFF);
    final bit = _types.indexOf(type);
    final safety = const {'overvolt', 'undervolt', 'overcurrent', 'overload', 'trip_fail', 'pair'}.contains(type); // always shown
    if (!safety && type != 'test' && (bit < 0 || types & (1 << bit) == 0)) return;
    final strip = mac.isEmpty ? null : _strip(mac);
    final fMasks = _filter?['masks'];
    final savedMask = fMasks is Map ? (fMasks[mac] as num?)?.toInt() : null;
    final mask = strip != null ? (strip['notify'] as num?)?.toInt() ?? savedMask ?? 0x1F : savedMask;
    if (!safety && mask != null && (outlet == 0 ? mask & 0x10 == 0 : mask & (1 << (outlet - 1)) == 0)) return;
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
      final who = [
        if (stripName.isNotEmpty) stripName,
        if (outletName.isNotEmpty) outletName,
      ].join(' · ');
      final am = AutomationMsg.parse(msg);
      if (am != null) {
        // "Automation: Fan guard" / "Light · Voltage 231 V is above the limit 190 V — switched off: Lamp"
        title = am.title(ar: isAr);
        final sentence = am.sentence((n) => _outletNameIn(strip, n), ar: isAr).replaceFirst(RegExp(r'^(القاعدة «[^»]*»: |Rule "[^"]*": )'), '');
        body = who.isEmpty ? sentence : '$who\n$sentence';
      } else {
        title = (msg.isNotEmpty && msg != 'on' && msg != 'off' && msg != '1' && msg != '0') ? _outletNames(strip, msg, isAr) : defaultTitle;
        body = who.isNotEmpty ? who : (isAr ? 'أتمتة اتنفذت' : 'Automation ran');
      }
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
        'overvolt' => isAr ? 'فولت عالي: المشترك اتقفل' : 'High voltage: strip turned off',
        'undervolt' => isAr ? 'فولت واطي: المشترك اتقفل' : 'Low voltage: strip turned off',
        'overcurrent' => isAr ? 'تيار عالي: اتقفل' : 'Over current: turned off',
        'overload' => isAr ? 'الحمل عدّى الحد: المشترك قفل مخارج' : 'Load over the limit: outlets turned off',
        'trip_fail' => isAr ? 'أمر القفل ماتأكدش' : 'Safety cut not confirmed',
        'pair' => isAr ? 'تليفون جديد طالب يدخل على الـ Hub' : 'A new phone wants access to the hub',
        'test' => 'Fisha ✓',
        _ => t('nt_$type'),
      };
      final who = [
        if (stripName.isNotEmpty) stripName,
        if (outletName.isNotEmpty) outletName,
      ].join(' · ');
      final extraMsg = (msg.isNotEmpty && msg != 'on' && msg != 'off' && msg != '1' && msg != '0') ? _outletNames(strip, msg, isAr) : '';
      if (who.isNotEmpty) {
        body = extraMsg.isNotEmpty ? '$who — $extraMsg' : who;
      } else {
        body = extraMsg.isNotEmpty ? extraMsg : (type == 'test' ? (isAr ? 'إشعار تجربة من الـ Hub' : 'Test notification from the hub') : title);
      }
    }

    _lastAlertAt = DateTime.now().millisecondsSinceEpoch;
    _saveStatus();
    final urgent = type == 'temp' || type == 'load' || type == 'voltage' || type == 'offline' || safety;
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
    _loadFilter();
    // "connected" is not enough: after a network change the client could sit there hearing nothing
    // (notifications came back only when the user switched them off and on). The hub publishes its state at least
    // every 30 s, so 3 minutes of silence means a dead link: start a fresh connection.
    final now = DateTime.now().millisecondsSinceEpoch;
    final heard = _lastMsgAt > _connAt ? _lastMsgAt : _connAt;
    final stale = _connAt > 0 && now - heard > 180000;
    _connect(force: stale);
    _saveStatus();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _client?.autoReconnect = false;
    _client?.disconnect();
  }
}

String _outletNameIn(Map<String, dynamic>? strip, int n) {
  final outs = strip?['outlets'];
  if (outs is List) {
    for (final o in outs) {
      if (o is Map && (o['n'] as num?)?.toInt() == n && (o['label'] ?? '').toString().isNotEmpty) return o['label'].toString();
    }
  }
  return t('default_outlet', {'n': n});
}

/// " · o:2,4" at the end of a hub message (the outlets it cut) becomes the outlets' names from the saved strip
String _outletNames(Map<String, dynamic>? strip, String msg, bool isAr) {
  final m = RegExp(r' · o:([\d,]+)$').firstMatch(msg);
  if (m == null) return msg;
  final outs = strip?['outlets'];
  String name(int n) {
    if (outs is List) {
      for (final o in outs) {
        if (o is Map && (o['n'] as num?)?.toInt() == n && (o['label'] ?? '').toString().isNotEmpty) return o['label'].toString();
      }
    }
    return t('default_outlet', {'n': n});
  }

  final names = [for (final n in m.group(1)!.split(',').map(int.tryParse).whereType<int>()) name(n)];
  return '${msg.substring(0, m.start)} · ${isAr ? 'اتقفل' : 'off'}: ${names.join(isAr ? '، ' : ', ')}';
}
