part of '../app_state.dart';

/// MQTT cloud link and state apply (moved verbatim from app_state.dart; behavior unchanged).
extension AppStateCloudLink on AppState {
  // ---------- MQTT ----------
  String get _base => settings.isShared ? 'mttl/${settings.hubId}/u/${settings.sharedUser}' : 'mttl/${settings.hubId}';

  String get _statusTopic => 'mttl/${settings.hubId}/status';

  Future<void> _startMqtt() async {
    final clientId = 'app-${DateTime.now().millisecondsSinceEpoch % 1000000000}';
    // phone: TLS to brokerHost:brokerPort; web: wss://brokerHost:8084/mqtt (services/mqtt_factory_*.dart)
    final c = createMqttClient(settings.brokerHost, clientId, settings.brokerPort);
    c.keepAlivePeriod = 30;
    c.autoReconnect = true;
    c.logging(on: false);
    c.setProtocolV311();
    c.connectionMessage = MqttConnectMessage().withClientIdentifier(clientId).startClean();
    c.onConnected = () {
      mqttConnected = true;
      _updateMode();
      _notify();
    };
    c.onAutoReconnected = () {
      mqttConnected = true;
      _updateMode();
      _notify();
    };
    c.onDisconnected = () {
      mqttConnected = false;
      _updateMode();
      _notify();
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
      _notify();
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
    _cloudHead = null;
    _cloudStrips.clear();
    // only what the app reads: '#' also brought every family member's copies to the owner's phone (EMQX traffic)
    for (final t in ['state', 's/+', 'event', 'info', 'cmd/ack']) {
      c.subscribe('$_base/$t', MqttQos.atLeastOnce);
    }
    c.subscribe(_statusTopic, MqttQos.atLeastOnce);
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
      _onCloudHead(text);
    } else if (topic.startsWith('$_base/s/')) {
      _onCloudStrip(topic.substring('$_base/s/'.length).toUpperCase(), text);
    } else if (topic == _statusTopic) {
      hubOnline = text.trim() == 'online';
      _updateMode();
      _notify();
    } else if (topic == '$_base/event') {
      _addEventJson(text);
    } else if (topic == '$_base/info') {
      try {
        final j = jsonDecode(text) as Map<String, dynamic>;
        hubFw = j['fw']?.toString() ?? hubFw;
        _notify();
      } catch (_) {}
    } else if (topic == '$_base/cmd/ack') {
      try {
        final j = jsonDecode(text) as Map<String, dynamic>;
        final done = _acks.remove((j['id'] ?? '').toString());
        if (done != null && !done.isCompleted) done.complete(j);
      } catch (_) {}
    }
  }

  // hub 2.15.38+: the head lists the strips and each strip comes on its own topic; older hubs send "devices" in the head
  void _onCloudHead(String text) {
    Map<String, dynamic> j;
    try {
      j = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return; // "" = cleared retained copy
    }
    if (j['strips'] is! List) {
      _cloudHead = null;
      _applyStateMap(j, fromLocal: false);
      return;
    }
    _cloudHead = j;
    _applyCloud();
  }

  void _onCloudStrip(String mac, String text) {
    if (mac.length != 12) return;
    if (text.trim().isEmpty) {
      _cloudStrips.remove(mac); // the hub wiped it: strip removed, or no longer shared with this member
    } else {
      try {
        _cloudStrips[mac] = jsonDecode(text) as Map<String, dynamic>;
      } catch (_) {
        return;
      }
    }
    if (_cloudHead != null) _applyCloud();
  }

  void _applyCloud() {
    final head = _cloudHead;
    if (head == null) return;
    final order = (head['strips'] as List).map((m) => m.toString().toUpperCase());
    final j = Map<String, dynamic>.from(head);
    j['devices'] = [for (final m in order) if (_cloudStrips[m] != null) _cloudStrips[m]];
    _applyStateMap(j, fromLocal: false);
  }

  // hub 2.15.38 SSE "live": the numbers of each online strip once a second, merged into the strips from the last "state"
  void _applyLive(String data) {
    try {
      final j = jsonDecode(data) as Map<String, dynamic>;
      final d = j['d'];
      if (d is! List || _strips.isEmpty) return;
      final byMac = <String, Map<String, dynamic>>{};
      for (final x in d) {
        if (x is Map<String, dynamic>) byMac[(x['mac'] ?? '').toString().toUpperCase()] = x;
      }
      var changed = false;
      final list = <Strip>[];
      for (final s0 in _strips) {
        final lv = byMac[s0.mac];
        if (lv == null || !s0.online) {
          list.add(s0);
          continue;
        }
        var s = s0.withLive(lv);
        final p = _pending[s.mac];
        if (p != null && p.isNotEmpty) s = s.withOutletState(p);
        list.add(s);
        changed = true;
      }
      if (!changed) return;
      _strips = list;
      OutletHistory.instance.sample(list);
      lastUpdate = DateTime.now();
      _localBadAt = null;
      _notify();
      updateWidgetThrottled();
    } catch (_) {
      // a bad "live" changes nothing; the next full state (at most 15 s) brings everything
    }
  }

  // ---------- state ----------
  void _applyState(String body, {required bool fromLocal}) {
    if (!fromLocal && _localFresh) return; // local data is fresher and authoritative
    Map<String, dynamic> j;
    try {
      j = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      if (fromLocal) {
        _localBadAt = DateTime.now();
        _updateMode();
      }
      return;
    }
    _applyStateMap(j, fromLocal: fromLocal);
  }

  void _applyStateMap(Map<String, dynamic> j, {required bool fromLocal}) {
    if (!fromLocal && _localFresh) return;
    try {
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
        if (cfg.containsKey('v_max') || cfg.containsKey('v_min')) {
          hubHasStripProt = true;
          vProtect = cfg['v_protect'] != false;
          vRestore = cfg['v_restore'] != false;
          vMax = (cfg['v_max'] as num?)?.toInt() ?? vMax;
          vMin = (cfg['v_min'] as num?)?.toInt() ?? vMin;
          aProtect = cfg['a_protect'] != false;
          aMax = (cfg['a_max'] as num?)?.toDouble() ?? aMax;
        }
        protHoldS = (cfg['hold_s'] as num?)?.toInt() ?? protHoldS;
        tzOffsetMin = (cfg['tz_min'] as num?)?.toInt() ?? tzOffsetMin;
        ntfyTopic = (cfg['ntfy'] ?? ntfyTopic).toString();
        notifyTypes = (cfg['ntypes'] as num?)?.toInt() ?? notifyTypes;
        hubSsid = (cfg['ssid'] ?? hubSsid).toString();
        wifiTest = (cfg['wifi_test'] ?? wifiTest).toString();
        wifiTestSsid = (cfg['wifi_test_ssid'] ?? wifiTestSsid).toString();
      }
      if (j['reset'] != null) hubReset = j['reset'].toString();
      final me = j['me'];
      if (me is Map && settings.isShared) {
        sharedPerms = (me['perms'] as num?)?.toInt() ?? 0;
        final r = (me['role'] as num?)?.toInt();
        if (r != null && r != settings.sharedRole) settings.sharedRole = r;
        _syncProfile(me);
      }
      final au = j['auth'];
      if (au is Map) {
        hubClaimed = au['claimed'] == true;
        final ow = au['owners'], pr = au['pair'];
        ownerPhones = ow is List ? ow.whereType<Map>().map((m) => OwnerPhone.fromJson(m)).toList() : [];
        pairRequests = pr is List ? pr.whereType<Map>().map((m) => PairRequest.fromJson(m)).toList() : [];
      }
      final nvs = (j['nvs'] ?? '').toString();
      if (nvs.isNotEmpty && !settings.isShared) _checkNvs(nvs);
      final cl = j['cloud'];
      if (cl is Map && fromLocal) {
        hubCloudUp = cl['up'] == true;
        hubCloudErr = (cl['err'] ?? '').toString();
        hubHasPass = cl['has_pass'] != false;
        hubOnline = hubCloudUp!;
        emqxSet = j['emqx_cfg'] == true;
        usersCount = (j['users_n'] as num?)?.toInt() ?? usersCount;
        if (settings.hubPass.isNotEmpty && (hubCloudErr == 'no_pass' || hubCloudErr == 'auth' || _passPushedValue != settings.hubPass)) {
          Future.microtask(() => pushHubPass());
        }
      }
      final hid = (j['hub'] ?? '').toString().toUpperCase();
      final lip = (j['lip'] ?? '').toString();
      // a family member follows the hub's current home address (the one in an old invite may be stale,
      // e.g. after the hub moved from .110 to .100), so they get local control too, not only remote
      if (lip.isNotEmpty && lip != '0.0.0.0' && settings.isShared && lip != settings.localHost && !_localFresh) {
        settings.localHost = lip;
        _prefs?.setString('settings', jsonEncode(settings.toJson()));
      }
      if (fromLocal && hid.length == 12 && hid != settings.hubId.toUpperCase() && !settings.isShared) {
        settings.hubId = hid;               // the hub knows its own id; a wrong one breaks the remote link
        _prefs?.setString('settings', jsonEncode(settings.toJson()));
        if (settings.hasCloud) {
          _stopMqtt();
          _startMqtt();
        }
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
      _saveNotifyFilter();
      OutletHistory.instance.sample(list); // app-side per-outlet kWh + daily peak (services/outlet_history.dart)
      for (final s in list) {
        if (!_order.contains(s.mac)) _order.add(s.mac);
      }
      if (!fromLocal) hubOnline = true;
      lastUpdate = DateTime.now();
      if (fromLocal) _localBadAt = null;
      _notify();
      updateWidgetThrottled();
    } catch (_) {
      if (fromLocal) {
        _localBadAt = DateTime.now();
        _updateMode();
      }
    }
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
}
