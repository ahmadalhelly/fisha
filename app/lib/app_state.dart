import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'i18n.dart';
import 'models.dart';

enum ConnMode { offline, local, cloud }

enum ViewMode { list, grid }

enum SortMode { manual, power, name, status }

enum ThemePref { system, dark, light }

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
  const CmdResult(this.ok, [this.error]);
}

class AppState extends ChangeNotifier {
  SharedPreferences? _prefs;
  HubSettings settings = HubSettings();

  // live data
  List<Strip> _strips = [];
  ConnMode mode = ConnMode.offline;
  bool mqttConnected = false;
  bool hubOnline = false;
  String? hubFw;
  String provState = 'idle';
  String provMsg = '';
  String? lastError;

  // preferences
  ViewMode viewMode = ViewMode.list;
  SortMode sortMode = SortMode.manual;
  ThemePref themePref = ThemePref.system;
  LangPref langPref = LangPref.system;
  bool showMac = false;
  String query = '';
  int tab = 0;
  List<String> _order = [];
  Map<String, String> _names = {}; // phone-side fallback names (hub fw < 1.1)

  // internals
  final Map<String, Map<int, bool>> _pending = {};
  final Map<String, Completer<bool>> _acks = {};
  String? _lastAckError;
  Timer? _localTimer;
  Timer? _mqttRetry;
  MqttServerClient? _mqtt;
  StreamSubscription? _mqttSub;
  DateTime? _lastLocalOk;
  bool _polling = false;
  int _seq = 0;

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
    viewMode = ViewMode.values[(p.getInt('viewMode') ?? 0).clamp(0, ViewMode.values.length - 1)];
    sortMode = SortMode.values[(p.getInt('sortMode') ?? 0).clamp(0, SortMode.values.length - 1)];
    themePref = ThemePref.values[(p.getInt('themePref') ?? 0).clamp(0, ThemePref.values.length - 1)];
    langPref = LangPref.values[(p.getInt('langPref') ?? 0).clamp(0, LangPref.values.length - 1)];
    showMac = p.getBool('showMac') ?? false;
    _order = p.getStringList('order') ?? [];
    final n = p.getString('names');
    if (n != null) {
      try {
        _names = Map<String, String>.from(jsonDecode(n) as Map);
      } catch (_) {}
    }
    await restart();
  }

  @override
  void dispose() {
    _localTimer?.cancel();
    _mqttRetry?.cancel();
    _stopMqtt();
    super.dispose();
  }

  Future<void> saveSettings(HubSettings s) async {
    settings = s;
    await _prefs?.setString('settings', jsonEncode(s.toJson()));
    await restart();
  }

  Future<void> restart() async {
    _localTimer?.cancel();
    _localTimer = null;
    _mqttRetry?.cancel();
    _stopMqtt();
    _strips = [];
    _lastLocalOk = null;
    mode = ConnMode.offline;
    hubOnline = false;
    notifyListeners();
    if (settings.hasLocal) {
      _pollLocal();
      _localTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollLocal());
    }
    if (settings.hasCloud) _startMqtt();
  }

  // ---------- local REST ----------
  Uri _localUri(String path) => Uri.parse('http://${settings.localHost}:${settings.localPort}$path');

  bool get _localFresh =>
      _lastLocalOk != null && DateTime.now().difference(_lastLocalOk!) < const Duration(seconds: 6);

  Future<void> _pollLocal() async {
    if (_polling || settings.localHost.isEmpty) return;
    _polling = true;
    try {
      final r = await http.get(_localUri('/api/state')).timeout(const Duration(milliseconds: 1500));
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

  void _updateMode() {
    final m = _localFresh ? ConnMode.local : (mqttConnected && hubOnline ? ConnMode.cloud : ConnMode.offline);
    if (m != mode) {
      mode = m;
      notifyListeners();
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
    // subscribe only after listening, so retained state/info/status are not missed
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
    } else if (topic == '$_base/info') {
      try {
        final j = jsonDecode(text) as Map<String, dynamic>;
        hubFw = j['fw']?.toString() ?? hubFw;
        final ip = (j['ip'] ?? '').toString();
        if (ip.isNotEmpty && settings.localHost.isEmpty) {
          settings.localHost = ip;
          _prefs?.setString('settings', jsonEncode(settings.toJson()));
          _localTimer ??= Timer.periodic(const Duration(seconds: 2), (_) => _pollLocal());
        }
        notifyListeners();
      } catch (_) {}
    } else if (topic == '$_base/cmd/ack') {
      try {
        final j = jsonDecode(text) as Map<String, dynamic>;
        final id = (j['id'] ?? '').toString();
        _lastAckError = (j['error'] ?? '').toString();
        final done = _acks.remove(id);
        if (done != null && !done.isCompleted) done.complete(j['ok'] == true);
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
      final pv = j['provision'];
      if (pv is Map) {
        provState = (pv['state'] ?? 'idle').toString();
        provMsg = (pv['msg'] ?? '').toString();
      }
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
      notifyListeners();
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
  double? get voltage {
    for (final s in _strips) {
      if (s.voltage != null) return s.voltage;
    }
    return null;
  }

  bool isPending(String mac, int n) => _pending[mac]?.containsKey(n) ?? false;

  // ---------- commands (local REST when on the same Wi-Fi, otherwise MQTT) ----------
  Future<CmdResult> _hubCommand(String path, Map<String, dynamic> body, {String? action}) async {
    try {
      if (_localFresh) {
        final r = await http
            .post(_localUri(path), headers: {'Content-Type': 'application/json; charset=utf-8'}, body: jsonEncode(body))
            .timeout(const Duration(seconds: 8));
        final j = jsonDecode(utf8.decode(r.bodyBytes));
        final ok = r.statusCode == 200 && j is Map && j['ok'] == true;
        return CmdResult(ok, ok ? null : ((j is Map ? j['error']?.toString() : null) ?? t('err_not_confirmed')));
      }
      if (mqttConnected && _mqtt != null) {
        final id = 'a${DateTime.now().millisecondsSinceEpoch}${_seq++}';
        final done = Completer<bool>();
        _acks[id] = done;
        final msg = <String, dynamic>{'id': id, ...body};
        if (action != null) msg['action'] = action;
        final b = MqttClientPayloadBuilder()..addUTF8String(jsonEncode(msg));
        _mqtt!.publishMessage('$_base/cmd', MqttQos.atLeastOnce, b.payload!);
        final ok = await done.future.timeout(const Duration(seconds: 10), onTimeout: () => false);
        _acks.remove(id);
        return CmdResult(ok, ok ? null : ((_lastAckError?.isNotEmpty ?? false) ? _lastAckError : t('err_no_ack')));
      }
      return CmdResult(false, t('err_no_conn'));
    } catch (_) {
      return CmdResult(false, t('err_failed'));
    }
  }

  Future<void> setOutlet(String mac, int outlet, bool on) async {
    final targets = outlet == 0 ? [1, 2, 3, 4] : [outlet];
    final p = _pending.putIfAbsent(mac, () => {});
    if (targets.any(p.containsKey)) return;
    for (final x in targets) {
      p[x] = on;
    }
    final before = _strips;
    _strips = _strips.map((s) => s.mac == mac ? s.withOutlets(outlet, on) : s).toList();
    notifyListeners();

    final r = await _hubCommand('/api/onoff', {'mac': mac, 'outlet': outlet, 'on': on});

    for (final x in targets) {
      p.remove(x);
    }
    if (!r.ok) {
      _strips = before;
      lastError = r.error;
    }
    notifyListeners();
    if (_localFresh) _pollLocal();
  }

  Future<void> refresh() async {
    if (settings.hasLocal) {
      await _pollLocal();
      if (_localFresh) return;
    }
    if (mqttConnected && _mqtt != null) {
      final b = MqttClientPayloadBuilder()
        ..addUTF8String(jsonEncode({'id': 'r${DateTime.now().millisecondsSinceEpoch}', 'action': 'refresh'}));
      _mqtt!.publishMessage('$_base/cmd', MqttQos.atLeastOnce, b.payload!);
      await Future.delayed(const Duration(milliseconds: 800));
    }
  }

  void clearError() => lastError = null;

  // ---------- names (on the hub for fw >= 1.1, else on the phone) ----------
  Strip? _find(String mac) {
    for (final s in _strips) {
      if (s.mac == mac) return s;
    }
    return null;
  }

  String _shortId(String mac) => mac.length >= 4 ? mac.substring(mac.length - 4) : mac;

  String stripName(Strip s) {
    if (s.label.isNotEmpty) return s.label;
    return _names['s:${s.mac}'] ?? t('default_strip', {'id': _shortId(s.mac)});
  }

  String outletName(Strip s, int n) {
    for (final o in s.outlets) {
      if (o.n == n && o.label.isNotEmpty) return o.label;
    }
    return _names['o:${s.mac}:$n'] ?? t('default_outlet', {'n': n});
  }

  /// outlet 0 = the strip itself
  Future<void> rename(Strip s, int outlet, String value) async {
    final v = value.replaceAll('"', '').replaceAll('\\', '').trim();
    if (hubHasConfig) {
      final before = _strips;
      _strips = _strips.map((x) => x.mac == s.mac ? x.withLabel(outlet, v) : x).toList();
      notifyListeners();
      final r = await _hubCommand('/api/label', {'mac': s.mac, 'outlet': outlet, 'label': v}, action: 'label');
      if (!r.ok) {
        _strips = before;
        lastError = r.error;
      } else {
        _names.remove(outlet == 0 ? 's:${s.mac}' : 'o:${s.mac}:$outlet');
        await _prefs?.setString('names', jsonEncode(_names));
      }
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

  Future<void> setLock(Strip s, int outlet, bool locked) async {
    if (!hubHasConfig) {
      lastError = t('err_old_fw');
      notifyListeners();
      return;
    }
    final before = _strips;
    _strips = _strips.map((x) => x.mac == s.mac ? x.withLock(outlet, locked) : x).toList();
    notifyListeners();
    final r = await _hubCommand('/api/lock', {'mac': s.mac, 'outlet': outlet, 'locked': locked}, action: 'lock');
    if (!r.ok) {
      _strips = before;
      lastError = r.error;
    }
    notifyListeners();
  }

  Strip? live(String mac) => _find(mac);

  // ---------- provisioning (add strip) ----------
  Future<CmdResult> startProvision() async {
    if (!hubHasConfig) return CmdResult(false, t('err_old_fw'));
    final r = await _hubCommand('/api/provision', {}, action: 'provision');
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

  void setQuery(String q) {
    query = q;
    notifyListeners();
  }

  void setTab(int i) {
    tab = i;
    notifyListeners();
  }
}
