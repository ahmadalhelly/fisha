part of '../app_state.dart';

/// Hub Wi-Fi, hub firmware and strip firmware update (moved verbatim from app_state.dart; behavior unchanged).
extension AppStateHubFirmware on AppState {
  // ---------- hub Wi-Fi ----------
  /// Asks the hub to switch to another home network. It tests it first and stays on the old one if it fails.
  /// Hands the hub's current network to one strip on its normal link (safe: it rejoins the same Wi-Fi). A
  /// "wifipush connect_ok" event in the system log means moving strips with the hub works.
  Future<CmdResult> testStripWifi(String mac) => api('strip_wifi_test', {'mac': mac});

  Future<CmdResult> setHubWifi(String ssid, String pass) async {
    final r = await api('wifi', {'ssid': ssid, 'pass': pass});
    if (r.ok) {
      wifiTest = 'queued';
      wifiTestSsid = ssid;
      _notify();
    }
    return r;
  }

  // ---------- hub firmware update (local network only) ----------
  Future<void> setOtaPass(String v) async {
    otaPass = v;
    await _prefs?.setString('otaPass', v);
  }

  /// The password every hub accepts for updates: `fisha-<hub MAC>`. The owner may also set one of their own.
  String get defaultOtaPass => 'fisha-${settings.hubId.toUpperCase()}';

  /// Uploads a hub .bin trying, in order, the saved own password then the default `fisha-<MAC>`; if both fail it asks
  /// through [ask] once (returns null to cancel). Returns null on success, 'cancel', 'auth', 'net', 'bad_file' or the hub's text.
  Future<String?> uploadFirmwareAuto(List<int> bytes, void Function(double) progress, {Future<String?> Function()? ask}) async {
    if (settings.isShared) return uploadFirmware(bytes, '', progress);
    final tried = <String>[];
    Future<String?> go(String p) async {
      tried.add(p);
      return uploadFirmware(bytes, p, progress);
    }
    var err = await go(otaPass.isNotEmpty ? otaPass : defaultOtaPass);
    if (err == 'auth' && !tried.contains(defaultOtaPass)) err = await go(defaultOtaPass);
    if (err == null) {
      if (tried.last == defaultOtaPass && otaPass.isNotEmpty) await setOtaPass('');
      return null;
    }
    if (err != 'auth') return err;
    if (otaPass.isNotEmpty) await setOtaPass('');       // the saved one is stale: forget it
    final p = ask == null ? null : await ask();
    if (p == null || p.isEmpty) return 'auth';
    err = await go(p);
    if (err == null) await setOtaPass(p == defaultOtaPass ? '' : p);
    return err;
  }

  /// Owner: change the update password. [cur] = `fisha-<MAC>` or the current own one; [next] empty = back to the default.
  Future<String?> changeOtaPass(String cur, String next) async {
    final r = await api('ota_pass', {'cur': cur, 'new': next});
    if (!r.ok) return r.error ?? 'failed';
    await setOtaPass(next);
    return null;
  }

  bool get canUpdateFirmware => !kIsWeb && (_localFresh || settings.hasLocal);

  /// Uploads a firmware .bin to the hub's /update page; [progress] gets 0..1. Returns null on success or an error text.
  Future<String?> uploadFirmware(List<int> bytes, String password, void Function(double) progress) async {
    if (bytes.length < 100000 || bytes.first != 0xE9) return 'bad_file';
    // hub 2.15.26: a member allowed to update the hub uses the phone's key instead of the update password
    return uploadFirmwareBytes(_localUri('/update'), bytes, password, progress, headers: settings.isShared ? _localHeaders : null);
  }

  Map<String, dynamic>? _hubJson(String body) {
    try {
      final j = jsonDecode(body);
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      return null;
    }
  }

  /// {size, valid, why, fetching, running, items:[{mac, from, to, state, msg, pct}]}, or null when unreachable
  /// (or is older than 2.15.8).
  Future<Map<String, dynamic>?> stripFwState() async {
    try {
      final r = await http.get(_localUri('/api/stripfw'), headers: _localHeaders).timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) return null;
      return _hubJson(utf8.decode(r.bodyBytes));
    } catch (_) {
      return null;
    }
  }

  /// Returns null on success, else the hub's error text.
  Future<String?> stripFwStart(List<String> macs) async {
    try {
      final r = await http
          .post(_localUri('/api/stripfw/start'),
              headers: {'Content-Type': 'application/json; charset=utf-8', ..._localHeaders}, body: jsonEncode({'macs': macs}))
          .timeout(const Duration(seconds: 9));
      if (r.statusCode == 200) return null;
      return _hubJson(utf8.decode(r.bodyBytes))?['error']?.toString() ?? 'HTTP ${r.statusCode}';
    } catch (_) {
      return 'net';
    }
  }

  Future<void> stripFwCancel() async {
    try {
      await http.post(_localUri('/api/stripfw/cancel'), headers: _localHeaders).timeout(const Duration(seconds: 6));
    } catch (_) {}
  }

  /// Uploads a strip .fwr to the hub (kept there until replaced). Returns null on success or an error text.
  Future<String?> uploadStripFw(List<int> bytes, void Function(double) progress) async {
    if (!AppState.looksLikeStripFw(bytes)) return 'bad_file';
    var err = await uploadFirmwareBytes(_localUri('/api/stripfw/upload'), bytes, '', progress,
        headers: _localHeaders, fileName: 'strip.fwr');
    if (err == 'net') {                                   // the hub can be busy for a moment (flash erase): one more try
      await Future.delayed(const Duration(seconds: 2));
      err = await uploadFirmwareBytes(_localUri('/api/stripfw/upload'), bytes, '', progress,
          headers: _localHeaders, fileName: 'strip.fwr');
    }
    if (err == null || err == 'net' || err == 'auth') return err;
    return _hubJson(err)?['error']?.toString() ?? err;
  }

  /// Hub 2.16+: the hub downloads the .fwr itself over HTTP(S) and stores it — the file never passes through
  /// this phone. Returns null on success or an error text.
  Future<String?> fetchStripFwByUrl(String url) async {
    try {
      final r = await http
          .post(_localUri('/api/stripfw/fetch'),
              headers: {'Content-Type': 'application/json; charset=utf-8', ..._localHeaders}, body: jsonEncode({'url': url}))
          // Older 1.0.5 hubs finish the same endpoint synchronously; allow that
          // response while newer hubs return immediately and expose fetching.
          .timeout(const Duration(seconds: 35));
      if (r.statusCode != 200) return _hubJson(utf8.decode(r.bodyBytes))?['error']?.toString() ?? 'HTTP ${r.statusCode}';
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      while (DateTime.now().isBefore(deadline)) {
        final state = await stripFwState();
        if (state == null) return 'net';
        if (state['fetching'] != true) {
          final size = (state['size'] as num?)?.toInt() ?? 0;
          if (state['valid'] == true && size > 0) return null;
          final why = (state['why'] ?? '').toString();
          return why.isEmpty ? 'download_failed' : why;
        }
        await Future.delayed(const Duration(seconds: 1));
      }
      return 'fetch_timeout';
    } catch (_) {
      return 'net';
    }
  }
}
