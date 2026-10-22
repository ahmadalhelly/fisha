part of '../app_state.dart';

/// Local: REST + Server-Sent Events (moved verbatim from app_state.dart; behavior unchanged).
extension AppStateLocalLink on AppState {
  // ---------- local: REST + Server-Sent Events ----------
  Map<String, String> get _localHeaders => {
        if (settings.isShared && settings.sharedUser.isNotEmpty) ...{
          'X-User': settings.sharedUser,
          'X-Token': settings.password,
          'Authorization': 'Basic ${base64Encode(utf8.encode('${settings.sharedUser}:${settings.password}'))}',
        } else if (settings.ownerKey.isNotEmpty)
          'X-Token': settings.ownerKey,
      };

  Uri _localUri(String path) {
    if (settings.isShared && settings.sharedUser.isNotEmpty) {
      final sep = path.contains('?') ? '&' : '?';
      return Uri.parse('http://${settings.localHost}:${settings.localPort}$path${sep}u=${settings.sharedUser}&t=${settings.password}');
    }
    return Uri.parse('http://${settings.localHost}:${settings.localPort}$path');
  }

  // An open live stream (SSE) is the local link itself: the hub only writes to it when something changes, with a
  // heartbeat every 15 s, so a 7 s window alone flipped "Local" off between heartbeats and sent commands via the
  // cloud. The stream drops itself after 25 s of silence (see _runSse), which clears sseLive.
  bool get _localFresh =>
      !_localBad && (sseLive || (_lastLocalOk != null && DateTime.now().difference(_lastLocalOk!) < const Duration(seconds: 7)));

  bool get _localBad => _localBadAt != null && DateTime.now().difference(_localBadAt!) < const Duration(seconds: 15);

  Future<void> _pollLocal() async {
    if (!kLocalCapable || _polling || settings.localHost.isEmpty) return;
    _polling = true;
    try {
      final r = await http.get(_localUri('/api/state'), headers: _localHeaders).timeout(const Duration(milliseconds: 1800));
      if (r.statusCode == 200) {
        _lastLocalOk = DateTime.now();
        _setLocked(false);
        _applyState(utf8.decode(r.bodyBytes), fromLocal: true);
      } else if (r.statusCode == 401) {
        _setLocked(true);
      }
    } catch (_) {
      // not on the home network — the cloud path takes over
    } finally {
      _polling = false;
      _updateMode();
    }
  }

  Future<void> _runSse(int gen) async {
    // web: a browser http.Client buffers the whole response, so SSE never delivers; the 2 s poll covers it
    if (kIsWeb || _sseRunning) return;
    _sseRunning = true;
    var backoff = 2;
    while (_sseRunning && gen == _gen && settings.hasLocal) {
      final client = http.Client();
      _sseClient = client;
      try {
        final sseUri = settings.isShared && settings.sharedUser.isNotEmpty
            ? Uri.parse('http://${settings.localHost}:${AppState.ssePort}/events?u=${settings.sharedUser}&t=${settings.password}')
            : settings.ownerKey.isNotEmpty
                ? Uri.parse('http://${settings.localHost}:${AppState.ssePort}/events?t=${settings.ownerKey}')
                : Uri.parse('http://${settings.localHost}:${AppState.ssePort}/events');
        final req = http.Request('GET', sseUri);
        req.headers['Accept'] = 'text/event-stream';
        req.headers.addAll(_localHeaders);
        final resp = await client.send(req).timeout(const Duration(seconds: 4));
        if (resp.statusCode != 200) throw http.ClientException('sse');
        sseLive = true;
        backoff = 2;
        _lastLocalOk = DateTime.now();
        _updateMode();
        _notify();
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
        // an old hub, or not on this Wi-Fi
      }
      client.close();
      if (sseLive) {
        sseLive = false;
        _notify();
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
    } else if (event == 'live') {
      _applyLive(data);
    } else if (event == 'event') {
      _addEventJson(data);
    }
  }

  void _updateMode() {
    final m = _localFresh ? ConnMode.local : (mqttConnected && hubOnline ? ConnMode.cloud : ConnMode.offline);
    if (m != mode) {
      mode = m;
      _notify();
      updateWidgetThrottled();
      if (m != ConnMode.offline && pendingOps.isNotEmpty) Future.microtask(flushPending);
    }
  }
}
