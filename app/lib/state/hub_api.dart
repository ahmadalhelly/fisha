part of '../app_state.dart';

/// Hub API, shared users (moved verbatim from app_state.dart; behavior unchanged).
extension AppStateHubApi on AppState {
  // ---------- hub API: local REST when on the same Wi-Fi, otherwise MQTT ----------
  Future<CmdResult> api(String action, [Map<String, dynamic> body = const {}]) async {
    try {
      if (_localFresh) {
        final r = await http
            .post(_localUri('/api/$action'),
                headers: {'Content-Type': 'application/json; charset=utf-8', ..._localHeaders}, body: jsonEncode(body))
            .timeout(const Duration(seconds: 9));
        final j = jsonDecode(utf8.decode(r.bodyBytes));
        if (j is! Map<String, dynamic>) return CmdResult(false, t('err_failed'));
        final ok = j['ok'] == true;
        final data = j['data'];
        return CmdResult(ok, ok ? null : (j['error'] == null ? t('err_not_confirmed') : _errText(j['error'].toString())),
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
        final err = _errText((j['error'] ?? '').toString());
        return CmdResult(ok, ok ? null : (err.isNotEmpty ? err : t('err_not_confirmed')),
            data is Map<String, dynamic> ? data : null);
      }
      return CmdResult(false, t('err_no_conn'));
    } catch (_) {
      return CmdResult(false, t('err_failed'));
    }
  }

  String _errText(String e) {
    switch (e) {
      case 'forbidden':
        return t('err_forbidden');
      case 'local_only':
        return t('err_local_only');
      case 'emqx_not_set':
        return t('users_need_emqx');
      case 'busy':
        return t('err_busy');
      default:
        return e;
    }
  }

  // ---------- shared users (owner) ----------
  Future<List<HubUser>?> loadUsers() async {
    final r = await api('users');
    if (!r.ok) {
      _fail(r);
      return null;
    }
    emqxSet = r.data?['emqx'] == true;
    final l = r.data?['users'];
    return l is List ? l.whereType<Map<String, dynamic>>().map(HubUser.fromJson).toList() : <HubUser>[];
  }

  /// Hub 2.10 runs server work in the background: start it, then wait for the result.
  Future<CmdResult> _job(String action, Map<String, dynamic> body) async {
    final r = await api(action, body);
    if (!r.ok || r.data?['job'] != true) return r;
    final until = DateTime.now().add(const Duration(seconds: 80));
    while (DateTime.now().isBefore(until)) {
      await Future.delayed(const Duration(milliseconds: 1500));
      final p = await api('ujob');
      if (!p.ok) continue;                      // the hub may be busy for a moment
      final st = p.data?['state'];
      if (st == 'running') continue;
      if (st == 'done') {
        final ok = p.data?['ok'] == true;
        final d = p.data?['data'];
        return CmdResult(ok, ok ? null : _errText((p.data?['error'] ?? '').toString()), d is Map<String, dynamic> ? d : null);
      }
      return CmdResult(false, t('err_not_confirmed'));
    }
    return CmdResult(false, t('err_no_ack'));
  }

  Future<CmdResult> setEmqx(String url, String key, String secret) => _job('emqx_config', {'url': url, 'key': key, 'secret': secret});

  /// Returns the invite code in [CmdResult.data]['code'].
  Future<CmdResult> inviteUser(String name, int role, bool all, List<String> strips, {int perms = 0}) =>
      _job('user_invite', {'name': name, 'role': role, 'perms': perms, 'all': all, 'strips': strips.join(',')}).then(_mirrorAfter);

  Future<CmdResult> updateUser(HubUser u) =>
      api('user_update', {'id': u.id, 'name': u.name, 'role': u.role, 'perms': u.perms, 'all': u.all, 'strips': u.strips.join(',')}).then(_mirrorAfter);

  Future<CmdResult> revokeUser(String id) => _job('user_revoke', {'id': id}).then(_mirrorAfter);

  CmdResult _mirrorAfter(CmdResult r) {
    if (r.ok) {
      _usersEditedHere = true;   // the hub's list is what the owner wants now, even if it is empty
      _mirrorSoon();
    }
    return r;
  }
}
