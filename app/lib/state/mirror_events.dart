part of '../app_state.dart';

/// Hub data mirror, events, energy (moved verbatim from app_state.dart; behavior unchanged).
extension AppStateMirrorEvents on AppState {
  Map<String, dynamic>? get _mirror {
    try {
      final raw = _prefs?.getString('hubMirror');
      return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  void _mirrorSoon() {
    if (settings.isShared || _hubNvs.isEmpty || (_mirrorDebounce?.isActive ?? false)) return;
    _mirrorDebounce = Timer(const Duration(seconds: 3), _refreshMirror);
  }

  Future<List<Map<String, dynamic>>?> _exportUsers() async {
    final r = await api('users_export');
    final l = r.data?['users'];
    if (!r.ok || l is! List) return null;
    return l.whereType<Map<String, dynamic>>().toList();
  }

  Future<void> _refreshMirror() async {
    if (_mirrorBusy || settings.isShared || _hubNvs.isEmpty || mode == ConnMode.offline) return;
    _mirrorBusy = true;
    try {
      final nvs = _hubNvs;
      var users = await _exportUsers();
      // 2.0.10: the family list can vanish from a hub whose storage was not erased (a save refused by a full NVS),
      // so the storage id stays the same and the copy below used to be overwritten with the empty list. Now an
      // empty list that this phone did not empty brings the saved members back.
      final old = _mirror;
      final oldUsers = old != null && (old['hub_id'] ?? '').toString() == settings.hubId.toUpperCase() && old['users'] is List
          ? (old['users'] as List).whereType<Map<String, dynamic>>().where((u) => (u['pw'] ?? '').toString().isNotEmpty).toList()
          : const <Map<String, dynamic>>[];
      if (users != null && users.isEmpty && oldUsers.isNotEmpty && !_usersEditedHere) {
        for (final u in oldUsers) {
          final st = u['strips'];
          await api('user_restore', {
            'id': u['id'],
            'name': u['name'],
            'role': u['role'],
            'perms': u['perms'] ?? 0,
            'all': u['all'] == true,
            'strips': st is List ? st.join(',') : (st ?? '').toString(),
            'pw': u['pw'],
          });
        }
        users = await _exportUsers();
        if (users != null && users.isNotEmpty) {
          lastError = t('users_restored', {'n': users.length});
          _notify();
        }
      }
      _usersEditedHere = false;
      final b = await exportBackup(parts: {'hub'});
      final hub = b['hub'];
      if (users == null || hub is! Map<String, dynamic> || nvs != _hubNvs) return;
      hub['users'] = users;
      // 2.0.25: a strip the hub couldn't answer for right now keeps the energy history saved in the last copy,
      // so one offline strip doesn't wipe its stats out of the Google copy
      final oldEn = old != null && (old['hub_id'] ?? '').toString() == settings.hubId.toUpperCase() ? old['energy'] : null;
      if (oldEn is Map) {
        final en = Map<String, dynamic>.from(hub['energy'] as Map? ?? {});
        for (final e in oldEn.entries) {
          en.putIfAbsent(e.key.toString(), () => e.value);
        }
        hub['energy'] = en;
      }
      final m = {'nvs': nvs, 'hub_id': settings.hubId.toUpperCase(), 'at': DateTime.now().toIso8601String(), ...hub};
      // 2.0.18: rewritten only when something in it changed, so an unchanged hub doesn't trigger a sync upload
      final same = old != null && jsonEncode({...old}..remove('at')) == jsonEncode({...m}..remove('at'));
      if (!same) await _prefs?.setString('hubMirror', jsonEncode(m));
      _mirrorAt = DateTime.now();
    } catch (_) {
    } finally {
      _mirrorBusy = false;
    }
  }

  /// Called with every state from the hub (owner only).
  void _checkNvs(String nvs) {
    if (nvs == _hubNvs || _mirrorBusy) {
      if (_mirrorAt == null || DateTime.now().difference(_mirrorAt!) > const Duration(minutes: 15)) _mirrorSoon();
      return;
    }
    final m = _mirror;
    final sameHub = m != null && (m['hub_id'] ?? '').toString() == settings.hubId.toUpperCase();
    _hubNvs = nvs;
    if (!sameHub || (m['nvs'] ?? '').toString().isEmpty || m['nvs'] == nvs) {
      _mirrorSoon();
      return;
    }
    Future.microtask(() => _restoreMirror(m));
  }

  /// The hub's storage was erased: put everything back, but only into a hub that is really empty
  /// (another phone may already have done it, or the owner started over on purpose).
  Future<void> _restoreMirror(Map<String, dynamic> m) async {
    _mirrorBusy = true;
    try {
      final users = await _exportUsers();
      final sOk = await loadSchedules();
      final aOk = await loadAutomations();
      if (users == null || !sOk || !aOk) return;
      if (users.isNotEmpty || schedules.any((x) => x.sid > 0) || automations.any((x) => x.aid > 0)) return;
      await importBackup({'fisha_backup': 1, 'hub': m}, parts: {'hub'});
      lastError = t('hub_restored');
      _notify();
    } catch (_) {
    } finally {
      _mirrorBusy = false;
    }
    await _refreshMirror();
  }

  // ---------- events ----------
  void _addEventJson(String text) {
    try {
      final e = HubEvent.fromJson(jsonDecode(text) as Map<String, dynamic>);
      if (!_eventKeys.add(e.key)) return;
      events.insert(0, e);
      if (events.length > 100) events.removeLast();
      // only what shows under "My notifications" counts on the bell or pops up (2.0.11)
      if (eventNotifies(e)) {
        unread++;
        lastAlert = e;
      }
      _notify();
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
    _notify();
  }

  void markEventsRead() {
    unread = 0;
    _notify();
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
}
