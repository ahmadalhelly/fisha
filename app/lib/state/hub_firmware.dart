part of '../app_state.dart';

/// Hub Wi-Fi, hub firmware and strip firmware update.
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
    // a member allowed to update the hub uses the phone's key instead of the update password
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

  /// {size, valid, fw, why, preparing, prepared, fetching, running, items:[{mac, from, to, state, msg, pct}]}, or null when unreachable.
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

  /// Prepares the spare OTA slot before a strip upload.
  /// If the Hub firmware erases 4KB sectors on-the-fly and returns "unknown action" for /api/stripfw/prepare,
  /// this gracefully returns null instead of failing with "unknown action".
  Future<String?> prepareStripFwStorage() async {
    try {
      final r = await http.post(_localUri('/api/stripfw/prepare'), headers: _localHeaders).timeout(const Duration(seconds: 9));
      if (r.statusCode != 200) {
        final err = _hubJson(utf8.decode(r.bodyBytes))?['error']?.toString() ?? 'HTTP ${r.statusCode}';
        if (err == 'unknown action' || r.statusCode == 404) {
          // Hub erases flash on-the-fly during upload; no separate prepare step needed!
          return null;
        }
        return err;
      }
      final initial = _hubJson(utf8.decode(r.bodyBytes));
      if (initial != null && initial['preparing'] != true) {
        if (initial['prepared'] == true || initial['has_slot'] == true || initial.containsKey('size')) return null;
      }
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      while (DateTime.now().isBefore(deadline)) {
        final state = await stripFwState();
        if (state == null) return 'net';
        if (state['preparing'] == true) {
          await Future.delayed(const Duration(milliseconds: 250));
          continue;
        }
        if (state['prepared'] == true || state['has_slot'] == true || state['preparing'] != true) return null;
        final why = (state['why'] ?? '').toString();
        return why.isEmpty ? 'prepare_failed' : why;
      }
      return 'prepare_timeout';
    } catch (_) {
      return 'net';
    }
  }

  /// Uploads a strip .fwr to the hub in 4 KB Base64 JSON chunks via POST /api/stripfw/chunk with retry.
  /// Returns null on success, 'unsupported' if the Hub lacks /api/stripfw/chunk, or an error string.
  Future<String?> _uploadStripFwChunked(List<int> bytes, void Function(double) progress) async {
    const int chunkSize = 4096; // 4 KB (1 NOR Flash sector; ~5.5 KB Base64 JSON to prevent ESP32 heap8 exhaustion)
    final int total = bytes.length;
    int offset = 0;
    int rewinds = 0;
    var client = http.Client();

    try {
      outer:
      while (offset < total) {
        final int end = (offset + chunkSize < total) ? (offset + chunkSize) : total;
        final bool isDone = end >= total;
        final String b64 = base64Encode(bytes.sublist(offset, end));
        final String payload = jsonEncode({
          'off': offset,
          'total': total,
          'done': isDone,
          'b64': b64,
        });

        http.Response? r;
        Object? lastEx;
        bool landed = false; // the hub already has this chunk (only its answer was lost)
        int busyWaits = 0;
        for (int attempt = 0; attempt < 6; attempt++) {
          try {
            r = await client
                .post(
                  _localUri('/api/stripfw/chunk'),
                  headers: {
                    'Content-Type': 'application/json; charset=utf-8',
                    'Connection': 'close',
                    ..._localHeaders,
                  },
                  body: payload,
                )
                .timeout(const Duration(seconds: 15));
            lastEx = null;
            if (r.statusCode == 409 && busyWaits < 60) {
              // the hub is busy with a strip update or fetching a file: wait for it, do not fail
              busyWaits++;
              r = null;
              await Future.delayed(const Duration(seconds: 1));
              attempt--;
              continue;
            }
            break;
          } catch (e) {
            lastEx = e;
            // a fresh socket for the next try, then ask the hub how far it got instead of guessing
            client.close();
            client = http.Client();
            await Future.delayed(Duration(milliseconds: 400 * (attempt + 1)));
            final st = await stripFwState();
            final w = st?['written'];
            if (w is int) {
              if (w >= end && offset > 0) {
                landed = true;
                lastEx = null;
                break;
              }
              if (w < offset && ++rewinds <= 5) {
                // the hub is behind (a sector was not kept): go back to the last 4 KB boundary it has
                offset = w - (w % chunkSize);
                continue outer;
              }
            }
          }
        }

        if (landed) {
          offset = end;
          progress(offset / total);
          if (isDone) {
            final st = await stripFwState();
            if (st != null && st['valid'] == false) {
              final why = (st['why'] ?? '').toString();
              return why.isNotEmpty ? why : 'bad_file';
            }
            return null;
          }
          continue;
        }

        if (lastEx != null || r == null) {
          lastUploadNetDetail = '${lastEx.runtimeType}: $lastEx';
          return 'net';
        }

        if (r.statusCode == 401 || r.statusCode == 403) return 'auth';
        if (r.statusCode != 200) {
          final err = _hubJson(utf8.decode(r.bodyBytes))?['error']?.toString() ?? 'HTTP ${r.statusCode}';
          if (offset == 0 && (err == 'unknown action' || r.statusCode == 404)) {
            return 'unsupported';
          }
          return err;
        }

        offset = end;
        progress(offset / total);

        if (isDone) {
          final st = _hubJson(utf8.decode(r.bodyBytes));
          if (st != null && st['valid'] == false) {
            final why = (st['why'] ?? '').toString();
            return why.isNotEmpty ? why : 'bad_file';
          }
          return null;
        }
      }
      return null;
    } finally {
      client.close();
    }
  }

  /// Uploads a strip .fwr to the hub (kept there until replaced). Returns null on success or an error text.
  /// Uses raw multipart streaming first (zero JSON/Base64 heap allocation on ESP32), then 4 KB chunked fallback.
  Future<String?> uploadStripFw(List<int> bytes, void Function(double) progress) async {
    if (!AppState.looksLikeStripFw(bytes)) return 'bad_file';
    progress(.02);

    // 1. Try 4 KB chunked JSON upload (/api/stripfw/chunk)
    final chunkErr = await _uploadStripFwChunked(bytes, (p) => progress(.02 + p * .98));
    if (chunkErr == null) {
      final verify = await stripFwState();
      if (verify != null && verify['valid'] != true) {
        final why = (verify['why'] ?? '').toString();
        return why.isNotEmpty ? why : 'bad_file';
      }
      return null;
    }
    if (chunkErr == 'auth' || chunkErr == 'bad_file') {
      return chunkErr;
    }

    // 2. Fallback for older Hub firmware without /api/stripfw/chunk
    final prepared = await prepareStripFwStorage();
    if (prepared != null) return prepared;
    var err = await uploadFirmwareBytes(
      _localUri('/api/stripfw/upload'),
      bytes,
      '',
      (p) => progress(.02 + p * .98),
      headers: _localHeaders,
      fileName: 'strip.fwr',
    );
    if (err == null) {
      final verify = await stripFwState();
      if (verify != null && verify['valid'] != true) {
        final why = (verify['why'] ?? '').toString();
        return why.isNotEmpty ? why : 'bad_file';
      }
      return null;
    }
    if (err == 'net' || err == 'auth') return err;
    return _hubJson(err)?['error']?.toString() ?? err;
  }

  /// Downloads a published .fwr on the phone (with User-Agent header), then uploads it reliably
  /// to the Hub via 8 KB chunked upload (or multipart fallback).
  Future<String?> downloadAndUploadStripFw(String url, void Function(double) progress) async {
    try {
      progress(0);
      final r = await http
          .get(
            Uri.parse(url),
            headers: const {
              'Accept': 'application/octet-stream',
              'User-Agent': 'Fisha-App',
            },
          )
          .timeout(const Duration(seconds: 45));
      if (r.statusCode != 200) return 'server replied ${r.statusCode}';
      if (!AppState.looksLikeStripFw(r.bodyBytes)) return 'downloaded file is not valid strip firmware';
      progress(.15);
      return await uploadStripFw(r.bodyBytes, (p) => progress(.15 + p * .85));
    } catch (e) {
      lastUploadNetDetail = '${e.runtimeType}: $e';
      return 'net';
    }
  }
}
