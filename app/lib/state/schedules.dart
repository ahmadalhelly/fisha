part of '../app_state.dart';

/// Schedules, automations, saves waiting for the hub (moved verbatim from app_state.dart; behavior unchanged).
extension AppStateSchedules on AppState {
  // ---------- schedules / automations ----------
  Future<bool> loadSchedules() async {
    final r = await api('schedules');
    if (r.ok && r.data != null) {
      final l = r.data!['schedules'];
      schedules = l is List ? l.whereType<Map<String, dynamic>>().map(Schedule.fromJson).toList() : [];
      schedules = _withPending(schedules, 'schedule', 'sid', (s) => s.sid, Schedule.fromJson);
      schedules.sort((a, b) => (a.hh * 60 + a.mm).compareTo(b.hh * 60 + b.mm));
      _notify();
    }
    return r.ok;
  }

  /// Sent to the hub right away; when the hub can't be reached it waits on this phone and goes out
  /// as soon as the hub is back (a time that passed meanwhile runs at once), so the save still counts.
  Future<bool> saveSchedule(Schedule s) async {
    if (s.sid < 0) return _queueEdit('schedule', 'sid', s.sid, s.toJson());
    final r = await api('schedule_save', s.toJson());
    if (_isConnErr(r)) return _queueEdit('schedule', 'sid', s.sid, s.toJson());
    _fail(r);
    if (r.ok) {
      await loadSchedules();
      _mirrorSoon();
      _stateNow(); // outlet badges follow at once, even on a hub older
    }
    return r.ok;
  }

  /// Skip only the next run of a schedule, or undo that.
  Future<bool> skipNextSchedule(Schedule sc, bool skip) async {
    final r = await api('schedule_skip', {'sid': sc.sid, 'skip': skip});
    _fail(r);
    if (r.ok) await loadSchedules();
    return r.ok;
  }

  /// Runs a schedule's command right now, without waiting for its time.
  Future<void> runScheduleNow(Schedule sc) async {
    final r = await api('onoff', {'mac': sc.mac, 'outlet': sc.outlet, 'on': sc.on});
    _fail(r);
    if (r.ok) refresh();
  }

  Future<void> deleteSchedule(int sid) async {
    schedules = schedules.where((x) => x.sid != sid).toList();
    _notify();
    if (sid < 0) return _dropQueued('schedule', 'sid', sid);
    final r = await api('schedule_delete', {'sid': sid});
    if (_isConnErr(r)) return _queueDelete('schedule', 'sid', sid);
    _fail(r);
    await loadSchedules();
    _mirrorSoon();
    _stateNow();
  }

  Future<bool> loadAutomations() async {
    final r = await api('automations');
    if (r.ok && r.data != null) {
      final l = r.data!['automations'];
      automations = l is List ? l.whereType<Map<String, dynamic>>().map(Automation.fromJson).toList() : [];
      automations = _withPending(automations, 'automation', 'aid', (a) => a.aid, Automation.fromJson);
      _notify();
    }
    return r.ok;
  }

  Future<bool> saveAutomation(Automation a) async {
    if (a.aid < 0) return _queueEdit('automation', 'aid', a.aid, a.toJson());
    final r = await api('automation_save', a.toJson());
    if (_isConnErr(r)) return _queueEdit('automation', 'aid', a.aid, a.toJson());
    _fail(r);
    if (r.ok) {
      await loadAutomations();
      _mirrorSoon();
      _stateNow();
    }
    return r.ok;
  }

  Future<void> deleteAutomation(int aid) async {
    automations = automations.where((x) => x.aid != aid).toList();
    _notify();
    if (aid < 0) return _dropQueued('automation', 'aid', aid);
    final r = await api('automation_delete', {'aid': aid});
    if (_isConnErr(r)) return _queueDelete('automation', 'aid', aid);
    _fail(r);
    await loadAutomations();
    _mirrorSoon();
    _stateNow();
  }

  bool _isConnErr(CmdResult r) =>
      !r.ok && (r.error == t('err_no_conn') || r.error == t('err_failed') || r.error == t('err_no_ack'));

  void _loadPendingOps() {
    try {
      final raw = _prefs?.getString('pendingOps');
      pendingOps = raw == null ? [] : (jsonDecode(raw) as List).whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      pendingOps = [];
    }
  }

  void _savePendingOps() {
    _prefs?.setString('pendingOps', jsonEncode(pendingOps));
    _flushTimer?.cancel();
    _flushTimer = pendingOps.isEmpty ? null : Timer.periodic(const Duration(seconds: 20), (_) => flushPending());
    _notify();
  }

  int get pendingCount => pendingOps.length;

  bool _queueEdit(String kind, String idKey, int id, Map<String, dynamic> body) {
    var qid = id;
    if (qid == 0) qid = -(DateTime.now().millisecondsSinceEpoch % 1000000000) - 1 - (_seq++ % 1000);
    final b = Map<String, dynamic>.from(body)..[idKey] = qid;
    pendingOps.removeWhere((o) => o['k'] == kind && o['id'] == qid);
    pendingOps.add({'k': kind, 'del': false, 'id': qid, 'b': b, 'q': DateTime.now().toIso8601String()});
    _savePendingOps();
    if (kind == 'schedule') {
      final sc = Schedule.fromJson(b);
      schedules = [...schedules.where((x) => x.sid != qid), sc]..sort((a, c) => (a.hh * 60 + a.mm).compareTo(c.hh * 60 + c.mm));
    } else {
      final au = Automation.fromJson(b);
      automations = [...automations.where((x) => x.aid != qid), au];
    }
    lastError = t('queued_for_hub');
    _notify();
    return true;
  }

  Future<void> _queueDelete(String kind, String idKey, int id) async {
    pendingOps.removeWhere((o) => o['k'] == kind && o['id'] == id);
    pendingOps.add({'k': kind, 'del': true, 'id': id, 'b': {idKey: id}, 'q': DateTime.now().toIso8601String()});
    _savePendingOps();
    lastError = t('queued_for_hub');
    _notify();
  }

  Future<void> _dropQueued(String kind, String idKey, int id) async {
    pendingOps.removeWhere((o) => o['k'] == kind && o['id'] == id);
    _savePendingOps();
  }

  /// The hub's list plus what still waits on this phone (new ones added, edits shown, deletes hidden).
  List<T> _withPending<T>(List<T> list, String kind, String idKey, int Function(T) idOf, T Function(Map<String, dynamic>) from) {
    final out = List<T>.from(list);
    for (final o in pendingOps.where((o) => o['k'] == kind)) {
      final id = (o['id'] as num).toInt();
      out.removeWhere((x) => idOf(x) == id);
      if (o['del'] != true && o['b'] is Map) out.add(from(Map<String, dynamic>.from(o['b'] as Map)));
    }
    return out;
  }

  /// Sends what waited for the hub, oldest first. A schedule whose time came while it waited runs now.
  Future<void> flushPending() async {
    if (_flushing || pendingOps.isEmpty || mode == ConnMode.offline) return;
    _flushing = true;
    try {
      while (pendingOps.isNotEmpty) {
        final o = pendingOps.first;
        final kind = o['k'].toString();
        final idKey = kind == 'schedule' ? 'sid' : 'aid';
        final id = (o['id'] as num).toInt();
        final body = Map<String, dynamic>.from(o['b'] as Map);
        if (id < 0) body[idKey] = 0;
        final r = o['del'] == true
            ? await api('${kind}_delete', {idKey: id})
            : await api('${kind}_save', body);
        if (_isConnErr(r)) break;               // still unreachable: keep it for the next try
        pendingOps.removeAt(0);
        _savePendingOps();
        if (!r.ok) {
          _fail(r);
          continue;
        }
        if (kind == 'schedule' && o['del'] != true) {
          final sc = Schedule.fromJson(body);
          final q = DateTime.tryParse((o['q'] ?? '').toString());
          if (q != null && sc.enabled && AppState._missedSince(sc, q, DateTime.now())) {
            await api('onoff', {'mac': sc.mac, 'outlet': sc.outlet, 'on': sc.on});
          }
        }
      }
    } finally {
      _flushing = false;
    }
    await loadSchedules();
    await loadAutomations();
    _mirrorSoon();
  }
}
