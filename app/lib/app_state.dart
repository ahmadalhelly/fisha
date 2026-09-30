import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

enum ConnMode { offline, local, cloud }

enum ViewMode { list, grid }

enum SortMode { manual, power, name, status }

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

  HubSettings copy() => HubSettings.fromJson(toJson());
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
  String? lastError;

  // UI preferences
  ViewMode viewMode = ViewMode.list;
  SortMode sortMode = SortMode.manual;
  bool showMac = false;
  String query = '';
  List<String> _order = [];
  Map<String, String> _names = {};

  // internals
  final Map<String, Map<int, bool>> _pending = {}; // mac -> outlet -> desired state
  final Map<String, Completer<bool>> _acks = {};
  String? _lastAckError;
  Timer? _localTimer;
  Timer? _mqttRetry;
  MqttServerClient? _mqtt;
  StreamSubscription? _mqttSub;
  DateTime? _lastLocalOk;
  bool _polling = false;
  int _seq = 0;

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
        _applyState(r.body, fromLocal: true);
      }
    } catch (_) {
      // not on the home network — cloud takes over
    } finally {
      _polling = false;
      _updateMode();
    }
  }

  void _updateMode() {
    final m = _localFresh
        ? ConnMode.local
        : (mqttConnected && hubOnline ? ConnMode.cloud : ConnMode.offline);
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
      c.disconnect();
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
        hubFw = j['fw']?.toString();
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
        final ok = j['ok'] == true;
        _lastAckError = (j['error'] ?? '').toString();
        final done = _acks.remove(id);
        if (done != null && !done.isCompleted) done.complete(ok);
      } catch (_) {}
    }
  }

  // ---------- state ----------
  void _applyState(String body, {required bool fromLocal}) {
    if (!fromLocal && _localFresh) return; // local data is fresher and authoritative
    try {
      final j = jsonDecode(body) as Map<String, dynamic>;
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

  List<Strip> get strips {
    var list = List<Strip>.from(_strips);
    final q = query.trim();
    if (q.isNotEmpty) {
      list = list.where((s) {
        if (stripName(s).contains(q)) return true;
        return s.outlets.any((o) => outletName(s, o.n).contains(q));
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

  // ---------- commands ----------
  Future<void> setOutlet(String mac, int outlet, bool on) async {
    final targets = outlet == 0 ? [1, 2, 3, 4] : [outlet];
    final p = _pending.putIfAbsent(mac, () => {});
    if (targets.any(p.containsKey)) return;
    for (final t in targets) {
      p[t] = on;
    }
    final before = _strips;
    _strips = _strips.map((s) => s.mac == mac ? s.withOutlets(outlet, on) : s).toList();
    notifyListeners();

    bool ok = false;
    String? err;
    try {
      if (_localFresh) {
        final r = await http
            .post(_localUri('/api/onoff'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({'mac': mac, 'outlet': outlet, 'on': on}))
            .timeout(const Duration(seconds: 8));
        final j = jsonDecode(r.body);
        ok = r.statusCode == 200 && j is Map && j['ok'] == true;
        if (!ok) err = (j is Map ? j['error']?.toString() : null) ?? 'الأمر ماتأكدش';
      } else if (mqttConnected && _mqtt != null) {
        final id = 'a${DateTime.now().millisecondsSinceEpoch}${_seq++}';
        final done = Completer<bool>();
        _acks[id] = done;
        final b = MqttClientPayloadBuilder()
          ..addUTF8String(jsonEncode({'id': id, 'mac': mac, 'outlet': outlet, 'on': on}));
        _mqtt!.publishMessage('$_base/cmd', MqttQos.atLeastOnce, b.payload!);
        ok = await done.future.timeout(const Duration(seconds: 10), onTimeout: () => false);
        _acks.remove(id);
        if (!ok) err = (_lastAckError?.isNotEmpty ?? false) ? _lastAckError : 'الـ Hub مردّش';
      } else {
        err = 'مفيش اتصال بالـ Hub';
      }
    } catch (e) {
      err = 'فشل الأمر';
    }

    for (final t in targets) {
      p.remove(t);
    }
    if (!ok) {
      _strips = before;
      lastError = err;
    }
    notifyListeners();
    if (_localFresh) _pollLocal();
  }

  Future<void> refresh() async {
    if (_localFresh || settings.hasLocal) {
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

  // ---------- names & ordering (stored on the phone in Sprint 1; moves to the hub in Sprint 2) ----------
  String stripName(Strip s) =>
      _names['s:${s.mac}'] ?? 'مشترك ${s.mac.length >= 4 ? s.mac.substring(s.mac.length - 4) : s.mac}';

  String outletName(Strip s, int n) => _names['o:${s.mac}:$n'] ?? 'مخرج $n';

  Future<void> renameStrip(Strip s, String name) => _setName('s:${s.mac}', name);

  Future<void> renameOutlet(Strip s, int n, String name) => _setName('o:${s.mac}:$n', name);

  Future<void> _setName(String key, String value) async {
    final v = value.trim();
    if (v.isEmpty) {
      _names.remove(key);
    } else {
      _names[key] = v;
    }
    await _prefs?.setString('names', jsonEncode(_names));
    notifyListeners();
  }

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

  Future<void> setShowMac(bool v) async {
    showMac = v;
    await _prefs?.setBool('showMac', v);
    notifyListeners();
  }

  void setQuery(String q) {
    query = q;
    notifyListeners();
  }
}
