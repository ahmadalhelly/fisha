import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'i18n.dart';
import 'models.dart';

enum ConnMode { offline, local, cloud }

enum ViewMode { list, grid }

enum SortMode { manual, power, name, status }

enum ThemePref { system, dark, light, graphite, saffron }

enum LangPref { system, ar, en }

class HubSettings {
  String hubId;
  String brokerHost;
  int brokerPort;
  String username;
  String password;
  String localHost;
  int localPort;

  HubSettings({
    this.hubId = '80F3DA40F674',
    this.brokerHost = 't0eb1112.ala.eu-central-1.emqxsl.com',
    this.brokerPort = 8883,
    this.username = 'stripe_app',
    this.password = '',
    this.localHost = '192.168.1.110',
    this.localPort = 8080,
  });

  bool get hasCloud => hubId.isNotEmpty && brokerHost.isNotEmpty && username.isNotEmpty && password.isNotEmpty;
  bool get hasLocal => localHost.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'hubId': hubId,
        'brokerHost': brokerHost,
        'brokerPort': brokerPort,
        'username': username,
        'password': password,
        'localHost': localHost,
        'localPort': localPort,
      };

  factory HubSettings.fromJson(Map<String, dynamic> j) {
    final d = HubSettings();
    return HubSettings(
      hubId: (j['hubId'] ?? d.hubId).toString(),
      brokerHost: (j['brokerHost'] ?? d.brokerHost).toString(),
      brokerPort: (j['brokerPort'] as num?)?.toInt() ?? d.brokerPort,
      username: (j['username'] ?? d.username).toString(),
      password: (j['password'] ?? '').toString(),
      localHost: (j['localHost'] ?? d.localHost).toString(),
      localPort: (j['localPort'] as num?)?.toInt() ?? d.localPort,
    );
  }
}

class CmdResult {
  final bool ok;
  final String? error;
  final Map<String, dynamic>? data;
  const CmdResult(this.ok, [this.error, this.data]);
}

class AppState extends ChangeNotifier {
  static const ssePort = 8081;

  SharedPreferences? _prefs;
  HubSettings settings = HubSettings();
  bool ready = false;

  // live data
  List<Strip> _strips = [];
  List<HubTimer> timers = [];
  ConnMode mode = ConnMode.offline;
  bool mqttConnected = false;
  bool hubOnline = false;
  bool sseLive = false;
  bool hubTimeOk = false;
  String? hubFw;
  int tempMax = 70;
  String ntfyTopic = '';
  int notifyTypes = 0x7FF;
  String otaPass = '';
  String hubSsid = '';
  String wifiTest = 'idle';
  String wifiTestSsid = '';
  bool tempProtect = true;
  String provState = 'idle';
  String provMsg = '';
  String? lastError;
  DateTime? lastUpdate;

  // events
  final List<HubEvent> events = [];
  final Set<String> _eventKeys = {};
  HubEvent? lastAlert;
  int unread = 0;

  // caches
  List<Schedule> schedules = [];
  List<Automation> automations = [];

  // preferences
  ViewMode viewMode = ViewMode.list;
  SortMode sortMode = SortMode.manual;
  ThemePref themePref = ThemePref.system;
  LangPref langPref = LangPref.system;
  bool showMac = false;
  double tariff = 1.0;
  String query = '';
  int tab = 0;
  List<String> _order = [];
  Map<String, String> _names = {}; // phone-side fallback names (very old hub firmware)

  int? hubUptimeS;
  String userName = '';
  List<Room> rooms = [];

  // widget throttling
  DateTime? _lastWidgetUpdate;
  Timer? _widgetThrottleTimer;

  // internals
  final Map<String, Map<int, bool>> _pending = {};
  final Map<String, Completer<Map<String, dynamic>>> _acks = {};
  Timer? _pollTimer;
  Timer? _mqttRetry;
  MqttServerClient? _mqtt;
  StreamSubscription? _mqttSub;
  http.Client? _sseClient;
  bool _sseRunning = false;
  DateTime? _lastLocalOk;
  bool _polling = false;
  int _seq = 0;
  int _gen = 0; // bumps on restart so old loops stop

  bool get hubV2 => hubFw != null && !hubFw!.startsWith('1.');
  bool get hubHasConfig => hubFw != null && hubFw != '1.0-alpha';

  // ---------- lifecycle ----------
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final p = _prefs!;
    final s = p.getString('settings');
    if (s != null) {
      try {
        settings = HubSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);
      } catch (_) {}
    }
    int idx(String k, int len) => (p.getInt(k) ?? 0).clamp(0, len - 1);
    viewMode = ViewMode.values[idx('viewMode', ViewMode.values.length)];
    sortMode = SortMode.values[idx('sortMode', SortMode.values.length)];
    themePref = ThemePref.values[idx('themePref', ThemePref.values.length)];
    langPref = LangPref.values[idx('langPref', LangPref.values.length)];
    showMac = p.getBool('showMac') ?? false;
    tariff = p.getDouble('tariff') ?? 1.0;
    otaPass = p.getString('otaPass') ?? '';
    userName = p.getString('userName') ?? '';
    _order = p.getStringList('order') ?? [];
    final n = p.getString('names');
    if (n != null) {
      try {
        _names = Map<String, String>.from(jsonDecode(n) as Map);
      } catch (_) {}
    }
    final rm = p.getString('rooms');
    if (rm != null) {
      try {
        rooms = (jsonDecode(rm) as List).whereType<Map<String, dynamic>>().map(Room.fromJson).toList();
      } catch (_) {}
    }
    ready = true;
    await restart();
  }

  @override
  void dispose() {
    _widgetThrottleTimer?.cancel();
    _stopAll();
    super.dispose();
  }

  void _stopAll() {
    _gen++;
    _pollTimer?.cancel();
    _pollTimer = null;
    _mqttRetry?.cancel();
    _sseRunning = false;
    _sseClient?.close();
    _sseClient = null;
    sseLive = false;
    _stopMqtt();
  }

  Future<void> saveSettings(HubSettings s) async {
    settings = s;
    await _prefs?.setString('settings', jsonEncode(s.toJson()));
    await restart();
  }

  Future<void> restart() async {
    _stopAll();
    _strips = [];
    timers = [];
    _lastLocalOk = null;
    mode = ConnMode.offline;
    hubOnline = false;
    notifyListeners();
    final gen = _gen;
    if (settings.hasLocal) {
      _pollLocal();
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (!sseLive) _pollLocal();
        _updateMode();
      });
      _runSse(gen);
    }
    if (settings.hasCloud) _startMqtt();
    Future.delayed(const Duration(seconds: 3), () {
      if (gen == _gen) loadEvents();
    });
  }

  // ---------- local: REST + Server-Sent Events ----------
  Uri _localUri(String path) => Uri.parse('http://${settings.localHost}:${settings.localPort}$path');

  bool get _localFresh =>
      _lastLocalOk != null && DateTime.now().difference(_lastLocalOk!) < const Duration(seconds: 7);

  Future<void> _pollLocal() async {
    if (_polling || settings.localHost.isEmpty) return;
    _polling = true;
    try {
      final r = await http.get(_localUri('/api/state')).timeout(const Duration(milliseconds: 1800));
      if (r.statusCode == 200) {
        _lastLocalOk = DateTime.now();
        _applyState(utf8.decode(r.bodyBytes), fromLocal: true);
      }
    } catch (_) {
      // not on the home network — the cloud path takes over
    } finally {
      _polling = false;
      _updateMode();
    }
  }

  Future<void> _runSse(int gen) async {
    if (_sseRunning) return;
    _sseRunning = true;
    var backoff = 2;
    while (_sseRunning && gen == _gen && settings.hasLocal) {
      final client = http.Client();
      _sseClient = client;
      try {
        final req = http.Request('GET', Uri.parse('http://${settings.localHost}:$ssePort/events'));
        req.headers['Accept'] = 'text/event-stream';
        final resp = await client.send(req).timeout(const Duration(seconds: 4));
        if (resp.statusCode != 200) throw const HttpException('sse');
        sseLive = true;
        backoff = 2;
        _lastLocalOk = DateTime.now();
        _updateMode();
        notifyListeners();
        var event = 'message';
        final data = StringBuffer();
        final lines =
            resp.stream.transform(utf8.decoder).transform(const LineSplitter()).timeout(const Duration(seconds: 25));
        await for (final line in lines) {
          if (gen != _gen) break;
          _lastLocalOk = DateTime.now();
          if (line.isEmpty) {
            if (data.isNotEmpty) _onSse(event, data.toString());
            event = 'message';
            data.clear();
          } else if (line.startsWith(':')) {
            continue;
          } else if (line.startsWith('event:')) {
            event = line.substring(6).trim();
          } else if (line.startsWith('data:')) {
            if (data.isNotEmpty) data.write('\n');
            data.write(line.substring(5).trimLeft());
          }
        }
      } catch (_) {
        // hub older than v2.0, or not on this Wi-Fi
      }
      client.close();
      if (sseLive) {
        sseLive = false;
        notifyListeners();
      }
      _updateMode();
      if (!_sseRunning || gen != _gen) break;
      await Future.delayed(Duration(seconds: backoff));
      backoff = backoff >= 20 ? 20 : backoff * 2;
    }
    if (gen == _gen) _sseRunning = false;
  }

  void _onSse(String event, String data) {
    if (event == 'state') {
      _applyState(data, fromLocal: true);
    } else if (event == 'event') {
      _addEventJson(data);
    }
  }

  void _updateMode() {
    final m = _localFresh ? ConnMode.local : (mqttConnected && hubOnline ? ConnMode.cloud : ConnMode.offline);
    if (m != mode) {
      mode = m;
      notifyListeners();
      updateWidgetThrottled();
    }
  }

  // ---------- MQTT ----------
  String get _base => 'mttl/${settings.hubId}';

  Future<void> _startMqtt() async {
    final clientId = 'app-${DateTime.now().millisecondsSinceEpoch % 1000000000}';
    final c = MqttServerClient.withPort(settings.brokerHost, clientId, settings.brokerPort);
    c.secure = true;
    c.securityContext = SecurityContext.defaultContext;
    c.keepAlivePeriod = 30;
    c.autoReconnect = true;
    c.logging(on: false);
    c.setProtocolV311();
    c.connectionMessage = MqttConnectMessage().withClientIdentifier(clientId).startClean();
    c.onConnected = () {
      mqttConnected = true;
      _updateMode();
      notifyListeners();
    };
    c.onAutoReconnected = () {
      mqttConnected = true;
      _updateMode();
      notifyListeners();
    };
    c.onDisconnected = () {
      mqttConnected = false;
      _updateMode();
      notifyListeners();
    };
    _mqtt = c;
    try {
      await c.connect(settings.username, settings.password);
    } catch (e) {
      mqttConnected = false;
      try {
        c.disconnect();
      } catch (_) {}
      _mqtt = null;
      _updateMode();
      notifyListeners();
      _mqttRetry = Timer(const Duration(seconds: 15), () {
        if (_mqtt == null && settings.hasCloud) _startMqtt();
      });
      return;
    }
    _mqttSub = c.updates?.listen((msgs) {
      for (final m in msgs) {
        final payload = m.payload;
        if (payload is! MqttPublishMessage) continue;
        final text = utf8.decode(payload.payload.message.toList(), allowMalformed: true);
        _onMqtt(m.topic.toString(), text);
      }
    });
    c.subscribe('$_base/#', MqttQos.atLeastOnce);
  }

  void _stopMqtt() {
    _mqttSub?.cancel();
    _mqttSub = null;
    final c = _mqtt;
    _mqtt = null;
    if (c != null) {
      c.autoReconnect = false;
      try {
        c.disconnect();
      } catch (_) {}
    }
    mqttConnected = false;
  }

  void _onMqtt(String topic, String text) {
    if (topic == '$_base/state') {
      _applyState(text, fromLocal: false);
    } else if (topic == '$_base/status') {
      hubOnline = text.trim() == 'online';
      _updateMode();
      notifyListeners();
    } else if (topic == '$_base/event') {
      _addEventJson(text);
    } else if (topic == '$_base/info') {
      try {
        final j = jsonDecode(text) as Map<String, dynamic>;
        hubFw = j['fw']?.toString() ?? hubFw;
        notifyListeners();
      } catch (_) {}
    } else if (topic == '$_base/cmd/ack') {
      try {
        final j = jsonDecode(text) as Map<String, dynamic>;
        final done = _acks.remove((j['id'] ?? '').toString());
        if (done != null && !done.isCompleted) done.complete(j);
      } catch (_) {}
    }
  }

  // ---------- state ----------
  void _applyState(String body, {required bool fromLocal}) {
    if (!fromLocal && _localFresh) return; // local data is fresher and authoritative
    try {
      final j = jsonDecode(body) as Map<String, dynamic>;
      final fw = j['hub_fw'];
      if (fw != null) hubFw = fw.toString();
      hubTimeOk = j['time_ok'] == true;
      if (j.containsKey('uptime_s')) hubUptimeS = (j['uptime_s'] as num?)?.toInt() ?? hubUptimeS;
      final pv = j['provision'];
      if (pv is Map) {
        provState = (pv['state'] ?? 'idle').toString();
        provMsg = (pv['msg'] ?? '').toString();
      }
      final cfg = j['config'];
      if (cfg is Map) {
        tempMax = (cfg['temp_max'] as num?)?.toInt() ?? tempMax;
        tempProtect = cfg['temp_protect'] != false;
        ntfyTopic = (cfg['ntfy'] ?? ntfyTopic).toString();
        notifyTypes = (cfg['ntypes'] as num?)?.toInt() ?? notifyTypes;
        hubSsid = (cfg['ssid'] ?? hubSsid).toString();
        wifiTest = (cfg['wifi_test'] ?? wifiTest).toString();
        wifiTestSsid = (cfg['wifi_test_ssid'] ?? wifiTestSsid).toString();
      }
      final tm = j['timers'];
      timers = tm is List ? tm.whereType<Map<String, dynamic>>().map(HubTimer.fromJson).toList() : [];
      final devs = j['devices'];
      if (devs is! List) return;
      final list = <Strip>[];
      for (final d in devs) {
        if (d is! Map<String, dynamic>) continue;
        var s = Strip.fromJson(d);
        final p = _pending[s.mac];
        if (p != null && p.isNotEmpty) s = s.withOutletState(p);
        list.add(s);
      }
      _strips = list;
      for (final s in list) {
        if (!_order.contains(s.mac)) _order.add(s.mac);
      }
      if (!fromLocal) hubOnline = true;
      lastUpdate = DateTime.now();
      notifyListeners();
      updateWidgetThrottled();
    } catch (_) {}
  }

  List<Strip> get allStrips => List.unmodifiable(_strips);
  Set<String> get macs => _strips.map((s) => s.mac).toSet();

  List<Strip> get strips {
    var list = List<Strip>.from(_strips);
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((s) {
        if (stripName(s).toLowerCase().contains(q)) return true;
        return s.outlets.any((o) => outletName(s, o.n).toLowerCase().contains(q));
      }).toList();
    }
    switch (sortMode) {
      case SortMode.manual:
        list.sort((a, b) => _orderIndex(a.mac).compareTo(_orderIndex(b.mac)));
        break;
      case SortMode.power:
        list.sort((a, b) => b.livePower.compareTo(a.livePower));
        break;
      case SortMode.name:
        list.sort((a, b) => stripName(a).compareTo(stripName(b)));
        break;
      case SortMode.status:
        list.sort((a, b) {
          final c = b.onCount.compareTo(a.onCount);
          return c != 0 ? c : b.livePower.compareTo(a.livePower);
        });
        break;
    }
    return list;
  }

  int _orderIndex(String mac) {
    final i = _order.indexOf(mac);
    return i < 0 ? 1 << 20 : i;
  }

  double get totalPower => _strips.fold(0.0, (s, e) => s + e.livePower);
  int get onCount => _strips.fold(0, (s, e) => s + e.onCount);
  int get outletCount => _strips.fold(0, (s, e) => s + e.outlets.length);
  int get onlineCount => _strips.where((s) => s.online).length;
  int get maxTemp => _strips.isEmpty ? 0 : _strips.map((s) => s.maxTemp).reduce((a, b) => a > b ? a : b);
  /// average of the strips that report a voltage
  double? get voltage {
    final v = [for (final s in _strips) if (s.online && s.voltage != null) s.voltage!];
    return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
  }

  bool isPending(String mac, int n) => _pending[mac]?.containsKey(n) ?? false;
  List<HubTimer> timersFor(String mac, [int? outlet]) =>
      timers.where((x) => x.mac == mac && (outlet == null || x.outlet == outlet || x.outlet == 0)).toList();
  Strip? live(String mac) {
    for (final s in _strips) {
      if (s.mac == mac) return s;
    }
    return null;
  }

  // ---------- hub API: local REST when on the same Wi-Fi, otherwise MQTT ----------
  Future<CmdResult> api(String action, [Map<String, dynamic> body = const {}]) async {
    try {
      if (_localFresh) {
        final r = await http
            .post(_localUri('/api/$action'),
                headers: {'Content-Type': 'application/json; charset=utf-8'}, body: jsonEncode(body))
            .timeout(const Duration(seconds: 9));
        final j = jsonDecode(utf8.decode(r.bodyBytes));
        if (j is! Map<String, dynamic>) return CmdResult(false, t('err_failed'));
        final ok = j['ok'] == true;
        final data = j['data'];
        return CmdResult(ok, ok ? null : (j['error']?.toString() ?? t('err_not_confirmed')),
            data is Map<String, dynamic> ? data : null);
      }
      if (mqttConnected && _mqtt != null) {
        final id = 'a${DateTime.now().millisecondsSinceEpoch}${_seq++}';
        final done = Completer<Map<String, dynamic>>();
        _acks[id] = done;
        final msg = <String, dynamic>{'id': id, 'path': '/api/$action', ...body};
        final b = MqttClientPayloadBuilder()..addUTF8String(jsonEncode(msg));
        _mqtt!.publishMessage('$_base/cmd', MqttQos.atLeastOnce, b.payload!);
        final j = await done.future.timeout(const Duration(seconds: 12), onTimeout: () => <String, dynamic>{});
        _acks.remove(id);
        if (j.isEmpty) return CmdResult(false, t('err_no_ack'));
        final ok = j['ok'] == true;
        final data = j['data'];
        final err = (j['error'] ?? '').toString();
        return CmdResult(ok, ok ? null : (err.isNotEmpty ? err : t('err_not_confirmed')),
            data is Map<String, dynamic> ? data : null);
      }
      return CmdResult(false, t('err_no_conn'));
    } catch (_) {
      return CmdResult(false, t('err_failed'));
    }
  }

  void _fail(CmdResult r) {
    if (!r.ok) {
      lastError = r.error;
      notifyListeners();
    }
  }

  void clearError() => lastError = null;

  Future<bool> forget(String mac) async {
    final r = await api('forget', {'mac': mac});
    _fail(r);
    if (r.ok) {
      _strips = _strips.where((s) => s.mac != mac).toList();
      notifyListeners();
    }
    return r.ok;
  }

  Future<void> setOutlet(String mac, int outlet, bool on) async {
    if (live(mac)?.online == false) {
      lastError = t('strip_offline_cmd');
      notifyListeners();
      return;
    }
    final targets = outlet == 0 ? [1, 2, 3, 4] : [outlet];
    final p = _pending.putIfAbsent(mac, () => {});
    if (targets.any(p.containsKey)) return;
    for (final x in targets) {
      p[x] = on;
    }
    final before = _strips;
    _strips = _strips.map((s) => s.mac == mac ? s.withOutlets(outlet, on) : s).toList();
    notifyListeners();
    final r = await api('onoff', {'mac': mac, 'outlet': outlet, 'on': on});
    for (final x in targets) {
      p.remove(x);
    }
    if (!r.ok) {
      _strips = before;
      lastError = r.error;
    }
    notifyListeners();
    if (_localFresh && !sseLive) _pollLocal();
  }

  /// Turns off every outlet of a strip except the protected ones.
  Future<void> offExceptProtected(Strip s) async {
    for (final o in s.outlets) {
      if (o.on && !o.protected) await setOutlet(s.mac, o.n, false);
    }
  }

  Future<void> refresh() async {
    if (_localFresh) {
      if (!sseLive) await _pollLocal();
      return;
    }
    if (settings.hasLocal) {
      await _pollLocal();
      if (_localFresh) return;
    }
    if (mqttConnected) await api('refresh');
  }

  // ---------- names / flags ----------
  String _shortId(String mac) => mac.length >= 4 ? mac.substring(mac.length - 4) : mac;

  String stripName(Strip s) {
    if (s.label.isNotEmpty) return s.label;
    return _names['s:${s.mac}'] ?? t('default_strip', {'id': _shortId(s.mac)});
  }

  String outletName(Strip s, int n) {
    if (n == 0) return t('whole_strip');
    for (final o in s.outlets) {
      if (o.n == n && o.label.isNotEmpty) return o.label;
    }
    return _names['o:${s.mac}:$n'] ?? t('default_outlet', {'n': n});
  }

  String nameForMac(String mac, int outlet) {
    final s = live(mac);
    if (s == null) return outlet == 0 ? t('whole_strip') : t('default_outlet', {'n': outlet});
    return outlet == 0 ? stripName(s) : '${stripName(s)} · ${outletName(s, outlet)}';
  }

  Future<void> rename(Strip s, int outlet, String value) async {
    final v = value.replaceAll('"', '').replaceAll('\\', '').trim();
    if (hubHasConfig) {
      final before = _strips;
      _strips = _strips.map((x) => x.mac == s.mac ? x.withLabel(outlet, v) : x).toList();
      notifyListeners();
      final r = await api('label', {'mac': s.mac, 'outlet': outlet, 'label': v});
      if (!r.ok) _strips = before;
      _fail(r);
      notifyListeners();
      return;
    }
    final key = outlet == 0 ? 's:${s.mac}' : 'o:${s.mac}:$outlet';
    if (v.isEmpty) {
      _names.remove(key);
    } else {
      _names[key] = v;
    }
    await _prefs?.setString('names', jsonEncode(_names));
    notifyListeners();
  }

  Future<void> _flag(Strip s, int outlet, String action, Map<String, dynamic> body, Outlet Function(Outlet) apply) async {
    final before = _strips;
    _strips = _strips.map((x) => x.mac == s.mac ? x.withOutlet(outlet, apply) : x).toList();
    notifyListeners();
    final r = await api(action, {'mac': s.mac, 'outlet': outlet, ...body});
    if (!r.ok) _strips = before;
    _fail(r);
    notifyListeners();
  }

  Future<void> setLock(Strip s, int outlet, bool v) =>
      _flag(s, outlet, 'lock', {'locked': v}, (o) => o.copyWith(locked: v));
  Future<void> setProtected(Strip s, int outlet, bool v) =>
      _flag(s, outlet, 'protect', {'protected': v}, (o) => o.copyWith(protected: v));
  Future<void> setKeepOn(Strip s, int outlet, bool v) =>
      _flag(s, outlet, 'keepon', {'on': v}, (o) => o.copyWith(keepOn: v));
  Future<void> setAutoOff(Strip s, int outlet, int minutes) =>
      _flag(s, outlet, 'autooff', {'minutes': minutes}, (o) => o.copyWith(autoOffMin: minutes));

  Future<bool> addTimer(String mac, int outlet, String kind, {int delayS = 0, int offS = 10, int onS = 0, int repeatS = 0}) async {
    final r = await api('timer', {'mac': mac, 'outlet': outlet, 'kind': kind, 'delay_s': delayS, 'off_s': offS, 'on_s': onS, 'repeat_s': repeatS});
    _fail(r);
    return r.ok;
  }

  Future<void> cancelTimer(int tid) async {
    timers = timers.where((x) => x.tid != tid).toList();
    notifyListeners();
    _fail(await api('timer_cancel', {'tid': tid}));
  }

  Future<void> setTempProtection({bool? enabled, int? max}) async {
    if (enabled != null) tempProtect = enabled;
    if (max != null) tempMax = max;
    notifyListeners();
    _fail(await api('config', {'temp_protect': tempProtect, 'temp_max': tempMax}));
  }

  // ---------- notifications (hub pushes them through ntfy) ----------
  static const notifyTypeKeys = ['temp', 'load', 'auto_off', 'automation', 'schedule', 'missed', 'timer', 'cycle', 'lock', 'added'];

  Future<bool> setNotifyConfig({String? topic, int? types}) async {
    if (topic != null) ntfyTopic = topic;
    if (types != null) notifyTypes = types;
    notifyListeners();
    final r = await api('notify', {if (topic != null) 'ntfy': topic, if (types != null) 'types': types});
    _fail(r);
    return r.ok;
  }

  Future<void> setNotifyMask(Strip s, int mask) async {
    final before = _strips;
    _strips = _strips.map((x) => x.mac == s.mac ? Strip(mac: x.mac, fw: x.fw, online: x.online, voltage: x.voltage, rssi: x.rssi, upS: x.upS, outlets: x.outlets, label: x.label, notifyMask: mask, hasSchedule: x.hasSchedule, hasRule: x.hasRule) : x).toList();
    notifyListeners();
    final r = await api('notify', {'mac': s.mac, 'mask': mask});
    if (!r.ok) _strips = before;
    _fail(r);
    notifyListeners();
  }

  Future<bool> testNotify() async {
    final r = await api('notify', {'test': true});
    _fail(r);
    return r.ok;
  }

  // ---------- hub Wi-Fi ----------
  /// Asks the hub to switch to another home network. It tests it first and stays on the old one if it fails.
  Future<CmdResult> setHubWifi(String ssid, String pass) async {
    final r = await api('wifi', {'ssid': ssid, 'pass': pass});
    if (r.ok) {
      wifiTest = 'queued';
      wifiTestSsid = ssid;
      notifyListeners();
    }
    return r;
  }

  // ---------- hub firmware update (local network only) ----------
  Future<void> setOtaPass(String v) async {
    otaPass = v;
    await _prefs?.setString('otaPass', v);
  }

  bool get canUpdateFirmware => _localFresh || settings.hasLocal;

  /// Uploads a firmware .bin to the hub's /update page; [progress] gets 0..1. Returns null on success or an error text.
  Future<String?> uploadFirmware(List<int> bytes, String password, void Function(double) progress) async {
    if (bytes.length < 100000 || bytes.first != 0xE9) return 'bad_file';
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client.postUrl(_localUri('/update'));
      req.headers.set(HttpHeaders.authorizationHeader, 'Basic ${base64Encode(utf8.encode('admin:$password'))}');
      final boundary = '----fisha${DateTime.now().millisecondsSinceEpoch}';
      req.headers.contentType = ContentType('multipart', 'form-data', parameters: {'boundary': boundary});
      final head = utf8.encode('--$boundary\r\nContent-Disposition: form-data; name="f"; filename="firmware.bin"\r\n'
          'Content-Type: application/octet-stream\r\n\r\n');
      final tail = utf8.encode('\r\n--$boundary--\r\n');
      req.contentLength = head.length + bytes.length + tail.length;
      req.add(head);
      const chunk = 8192;
      for (var i = 0; i < bytes.length; i += chunk) {
        req.add(bytes.sublist(i, i + chunk > bytes.length ? bytes.length : i + chunk));
        await req.flush();
        progress((i + chunk).clamp(0, bytes.length) / bytes.length);
      }
      req.add(tail);
      final resp = await req.close().timeout(const Duration(seconds: 60));
      final body = await resp.transform(utf8.decoder).join();
      if (resp.statusCode == 401) return 'auth';
      if (resp.statusCode != 200) return body.trim().isEmpty ? 'HTTP ${resp.statusCode}' : body.trim();
      return null;
    } catch (e) {
      return 'net';
    } finally {
      client.close(force: true);
    }
  }

  // ---------- schedules / automations ----------
  Future<bool> loadSchedules() async {
    final r = await api('schedules');
    if (r.ok && r.data != null) {
      final l = r.data!['schedules'];
      schedules = l is List ? l.whereType<Map<String, dynamic>>().map(Schedule.fromJson).toList() : [];
      schedules.sort((a, b) => (a.hh * 60 + a.mm).compareTo(b.hh * 60 + b.mm));
      notifyListeners();
    }
    return r.ok;
  }

  Future<bool> saveSchedule(Schedule s) async {
    final r = await api('schedule_save', s.toJson());
    _fail(r);
    if (r.ok) await loadSchedules();
    return r.ok;
  }

  Future<void> deleteSchedule(int sid) async {
    schedules = schedules.where((x) => x.sid != sid).toList();
    notifyListeners();
    _fail(await api('schedule_delete', {'sid': sid}));
    await loadSchedules();
  }

  Future<bool> loadAutomations() async {
    final r = await api('automations');
    if (r.ok && r.data != null) {
      final l = r.data!['automations'];
      automations = l is List ? l.whereType<Map<String, dynamic>>().map(Automation.fromJson).toList() : [];
      notifyListeners();
    }
    return r.ok;
  }

  Future<bool> saveAutomation(Automation a) async {
    final r = await api('automation_save', a.toJson());
    _fail(r);
    if (r.ok) await loadAutomations();
    return r.ok;
  }

  Future<void> deleteAutomation(int aid) async {
    automations = automations.where((x) => x.aid != aid).toList();
    notifyListeners();
    _fail(await api('automation_delete', {'aid': aid}));
    await loadAutomations();
  }

  // ---------- events ----------
  void _addEventJson(String text) {
    try {
      final e = HubEvent.fromJson(jsonDecode(text) as Map<String, dynamic>);
      if (!_eventKeys.add(e.key)) return;
      events.insert(0, e);
      if (events.length > 100) events.removeLast();
      unread++;
      lastAlert = e;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadEvents() async {
    if (!hubV2) return;
    final r = await api('events');
    if (!r.ok || r.data == null) return;
    final l = r.data!['events'];
    if (l is! List) return;
    for (final m in l.whereType<Map<String, dynamic>>()) {
      final e = HubEvent.fromJson(m);
      if (_eventKeys.add(e.key)) events.add(e);
    }
    events.sort((a, b) => b.ts.compareTo(a.ts));
    notifyListeners();
  }

  void markEventsRead() {
    unread = 0;
    notifyListeners();
  }

  HubEvent? takeAlert() {
    final a = lastAlert;
    lastAlert = null;
    return a;
  }

  // ---------- energy ----------
  Future<List<EnergyData>> loadEnergy() async {
    final out = <EnergyData>[];
    for (final s in _strips) {
      final r = await api('energy', {'mac': s.mac});
      if (r.ok && r.data != null) out.add(EnergyData.fromJson(r.data!));
    }
    return out;
  }

  // ---------- provisioning ----------
  Future<CmdResult> startProvision() async {
    if (!hubHasConfig) return CmdResult(false, t('err_old_fw'));
    final r = await api('provision');
    if (r.ok) {
      provState = 'queued';
      provMsg = '';
      notifyListeners();
    }
    return r;
  }

  // ---------- UI prefs ----------
  Future<void> reorder(int oldIndex, int newIndex) async {
    final visible = strips.map((s) => s.mac).toList();
    if (newIndex > oldIndex) newIndex -= 1;
    final mac = visible.removeAt(oldIndex);
    visible.insert(newIndex, mac);
    final rest = _order.where((m) => !visible.contains(m)).toList();
    _order = [...visible, ...rest];
    await _prefs?.setStringList('order', _order);
    notifyListeners();
  }

  Future<void> setViewMode(ViewMode m) async {
    viewMode = m;
    await _prefs?.setInt('viewMode', m.index);
    notifyListeners();
  }

  Future<void> setSortMode(SortMode m) async {
    sortMode = m;
    await _prefs?.setInt('sortMode', m.index);
    notifyListeners();
  }

  Future<void> setThemePref(ThemePref m) async {
    themePref = m;
    await _prefs?.setInt('themePref', m.index);
    notifyListeners();
  }

  Future<void> setLangPref(LangPref m) async {
    langPref = m;
    await _prefs?.setInt('langPref', m.index);
    notifyListeners();
  }

  Future<void> setShowMac(bool v) async {
    showMac = v;
    await _prefs?.setBool('showMac', v);
    notifyListeners();
  }

  Future<void> setTariff(double v) async {
    tariff = v;
    await _prefs?.setDouble('tariff', v);
    notifyListeners();
  }

  void setQuery(String q) {
    query = q;
    notifyListeners();
  }

  void setTab(int i) {
    tab = i;
    notifyListeners();
  }

  Future<void> setUserName(String name) async {
    userName = name.trim();
    await _prefs?.setString('userName', userName);
    notifyListeners();
  }

  bool requiresBio(String mac, int n) => _prefs?.getBool('bio_${mac.toUpperCase()}_$n') ?? false;

  Future<void> setRequiresBio(String mac, int n, bool val) async {
    await _prefs?.setBool('bio_${mac.toUpperCase()}_$n', val);
    notifyListeners();
  }

  Room? roomForStrip(String mac) {
    final upper = mac.toUpperCase();
    for (final r in rooms) {
      if (r.stripMacs.contains(upper)) return r;
    }
    return null;
  }

  Future<void> saveRooms() async {
    await _prefs?.setString('rooms', jsonEncode([for (final r in rooms) r.toJson()]));
    notifyListeners();
  }

  Future<void> addRoom(String name) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    rooms.add(Room(id: id, name: name.trim()));
    await saveRooms();
  }

  Future<void> renameRoom(String id, String newName) async {
    final i = rooms.indexWhere((r) => r.id == id);
    if (i >= 0) {
      rooms[i] = rooms[i].copyWith(name: newName.trim());
      await saveRooms();
    }
  }

  Future<void> deleteRoom(String id) async {
    rooms.removeWhere((r) => r.id == id);
    await saveRooms();
  }

  Future<void> assignStripToRoom(String mac, String? roomId) async {
    final upper = mac.toUpperCase();
    for (var i = 0; i < rooms.length; i++) {
      if (rooms[i].stripMacs.contains(upper)) {
        final updated = List<String>.from(rooms[i].stripMacs)..remove(upper);
        rooms[i] = rooms[i].copyWith(stripMacs: updated);
      }
    }
    if (roomId != null && roomId.isNotEmpty) {
      final i = rooms.indexWhere((r) => r.id == roomId);
      if (i >= 0) {
        final updated = List<String>.from(rooms[i].stripMacs);
        if (!updated.contains(upper)) updated.add(upper);
        rooms[i] = rooms[i].copyWith(stripMacs: updated);
      }
    }
    await saveRooms();
  }

  void updateWidgetThrottled() {
    final now = DateTime.now();
    if (_lastWidgetUpdate != null && now.difference(_lastWidgetUpdate!) < const Duration(seconds: 15)) {
      if (_widgetThrottleTimer == null || !_widgetThrottleTimer!.isActive) {
        final remaining = const Duration(seconds: 15) - now.difference(_lastWidgetUpdate!);
        _widgetThrottleTimer = Timer(remaining, _updateWidget);
      }
      return;
    }
    _updateWidget();
  }

  Future<void> _updateWidget() async {
    _widgetThrottleTimer?.cancel();
    _lastWidgetUpdate = DateTime.now();
    try {
      final totalW = '${totalPower.toStringAsFixed(0)} W';
      final outletsOn = '$onCount/$outletCount';
      final hottest = '$maxTemp°C';
      final conn = switch (mode) {
        ConnMode.local => t('mode_local'),
        ConnMode.cloud => t('mode_cloud'),
        ConnMode.offline => t('mode_offline'),
      };
      await HomeWidget.saveWidgetData<String>('total_w', totalW);
      await HomeWidget.saveWidgetData<String>('outlets_on', outletsOn);
      await HomeWidget.saveWidgetData<String>('hottest_temp', hottest);
      await HomeWidget.saveWidgetData<String>('conn_mode', conn);
      await HomeWidget.updateWidget(
        name: 'FishaWidgetProvider',
        androidName: 'FishaWidgetProvider',
        qualifiedAndroidName: 'com.mttlhub.mttl_hub.FishaWidgetProvider',
      );
    } catch (_) {}
  }
}
