part of '../app_state.dart';

/// Account, outlets, names, flags, protections (moved verbatim from app_state.dart; behavior unchanged).
extension AppStateStripControl on AppState {
  // ---------- account ----------
  Future<void> setAccount(String type, {String email = ''}) async {
    accountType = type;
    googleEmail = email;
    await _prefs?.setString('accountType', type);
    await _prefs?.setString('googleEmail', email);
    _notify();
  }

  Future<void> markSynced() async {
    lastSync = DateTime.now();
    await _prefs?.setString('lastSync', lastSync!.toIso8601String());
    _notify();
  }

  void _fail(CmdResult r) {
    if (!r.ok) {
      lastError = r.error;
      _notify();
    }
  }

  void clearError() => lastError = null;

  Future<bool> forget(String mac) async {
    final r = await api('forget', {'mac': mac});
    _fail(r);
    if (r.ok) {
      _strips = _strips.where((s) => s.mac != mac).toList();
      _notify();
    }
    return r.ok;
  }

  Future<void> setOutlet(String mac, int outlet, bool on) async {
    final strip = live(mac);
    if (strip?.online == false) {
      lastError = t('strip_offline_cmd');
      _notify();
      return;
    }
    // A master "all on/off" (outlet 0) leaves child-locked outlets alone — same as the hub (lockSkip, 2.15.23).
    // Without this the UI showed the locked outlet flip, then flip back once the real state came back unchanged.
    if (!canControl) {
      lastError = Tr.isAr ? 'صلاحيتك مشاهدة بس' : 'You can view only';
      _notify();
      return;
    }
    final targets = outlet != 0
        ? [outlet]
        : [for (final o in strip?.outlets ?? const <Outlet>[]) if (!o.locked) o.n];
    if (targets.isEmpty) return;
    // 2.0.22: a control member's "all on/off" skips overload-protected outlets one by one (the hub refuses them)
    if (outlet == 0 && !can(Perm.prot) && (strip?.outlets.any((o) => o.protected) ?? false)) {
      for (final o in strip!.outlets) {
        if (!o.locked && !o.protected && o.on != on) await setOutlet(mac, o.n, on);
      }
      return;
    }
    final p = _pending.putIfAbsent(mac, () => {});
    if (targets.any(p.containsKey)) {
      lastError = t('err_busy');                   // a previous command for this outlet is still on its way
      _notify();
      return;
    }
    for (final x in targets) {
      p[x] = on;
    }
    final before = _strips;
    _strips = _strips.map((s) => s.mac == mac ? s.withOutletState({for (final x in targets) x: on}) : s).toList();
    _notify();
    final r = await api('onoff', {'mac': mac, 'outlet': outlet, 'on': on});
    for (final x in targets) {
      p.remove(x);
    }
    if (!r.ok) {
      _strips = before;
      lastError = r.error;
    }
    _notify();
    if (_localFresh && !sseLive) _pollLocal();
  }

  /// Turns off every outlet of a strip except the protected ones.
  Future<void> offExceptProtected(Strip s) async {
    for (final o in s.outlets) {
      if (o.on && !o.protected) await setOutlet(s.mac, o.n, false);
    }
  }

  /// Fetches the state once even while the live stream is up (rule badges after a schedule/automation edit).
  Future<void> _stateNow() async {
    if (_localFresh) return _pollLocal();
    return refresh();
  }

  Future<void> refresh() async {
    if (_localFresh) {
      if (!sseLive) await _pollLocal();
      return;
    }
    if (kLocalCapable && settings.hasLocal) {
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
    if (s == null) {
      final unknown = Tr.isAr ? 'مشترك غير معروف' : 'Unknown strip';
      return outlet == 0 ? unknown : '$unknown · ${t('default_outlet', {'n': outlet})}';
    }
    return outlet == 0 ? stripName(s) : '${stripName(s)} · ${outletName(s, outlet)}';
  }

  Future<void> rename(Strip s, int outlet, String value) async {
    final v = value.replaceAll('"', '').replaceAll('\\', '').trim();
    if (hubHasConfig) {
      final before = _strips;
      _strips = _strips.map((x) => x.mac == s.mac ? x.withLabel(outlet, v) : x).toList();
      _notify();
      final r = await api('label', {'mac': s.mac, 'outlet': outlet, 'label': v});
      if (!r.ok) _strips = before;
      _fail(r);
      _notify();
      return;
    }
    final key = outlet == 0 ? 's:${s.mac}' : 'o:${s.mac}:$outlet';
    if (v.isEmpty) {
      _names.remove(key);
    } else {
      _names[key] = v;
    }
    await _prefs?.setString('names', jsonEncode(_names));
    _notify();
  }

  Future<void> _flag(Strip s, int outlet, String action, Map<String, dynamic> body, Outlet Function(Outlet) apply) async {
    final before = _strips;
    _strips = _strips.map((x) => x.mac == s.mac ? x.withOutlet(outlet, apply) : x).toList();
    _notify();
    final r = await api(action, {'mac': s.mac, 'outlet': outlet, ...body});
    if (!r.ok) _strips = before;
    _fail(r);
    _notify();
  }

  Future<void> setLock(Strip s, int outlet, bool v) =>
      _flag(s, outlet, 'lock', {'locked': v}, (o) => o.copyWith(locked: v));

  Future<void> setMasterLock(Strip s, bool v) async {
    final before = _strips;
    _strips = _strips.map((x) => x.mac == s.mac ? x.withMasterLock(v) : x).toList();
    _notify();
    final r = await api('lock', {'mac': s.mac, 'outlet': 0, 'locked': v});
    if (!r.ok) _strips = before;
    _fail(r);
    _notify();
  }

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
    _notify();
    _fail(await api('timer_cancel', {'tid': tid}));
  }

  Future<void> setStripProtection({bool? vOn, bool? vBack, int? vLimit, int? vMinLimit, bool? aOn, double? aLimit}) async {
    if (vOn != null) vProtect = vOn;
    if (vBack != null) vRestore = vBack;
    if (vLimit != null) vMax = vLimit;
    if (vMinLimit != null) vMin = vMinLimit;
    if (aOn != null) aProtect = aOn;
    if (aLimit != null) aMax = aLimit;
    _notify();
    _fail(await api('config', {
      'v_protect': vProtect,
      'v_restore': vRestore,
      'v_max': vMax,
      'v_min': vMin,
      'a_protect': aProtect,
      'a_max': aMax,
    }));
  }

  Future<CmdResult> setOutletAmpLimit(String mac, int outlet, double maxA) async {
    final r = await api('amplimit', {'mac': mac, 'outlet': outlet, 'max_a': maxA});
    _fail(r);
    return r;
  }

  /// Restarts the ESP32 hub (owner only). It is back in about 15 s.
  Future<CmdResult> rebootHub() => api('reboot');

  Future<void> setTempProtection({bool? enabled, int? max}) async {
    if (enabled != null) tempProtect = enabled;
    if (max != null) tempMax = max;
    _notify();
    _fail(await api('config', {'temp_protect': tempProtect, 'temp_max': tempMax}));
  }
}
