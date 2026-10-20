part of '../app_state.dart';

/// Hub lock, pairing, joining a hub (moved verbatim from app_state.dart; behavior unchanged).
extension AppStateHubLock on AppState {
  // ---------- 2.0.18 hub lock (hub 2.15.13) ----------
  void _setLocked(bool v) {
    if (v == hubLocked) return;
    hubLocked = v;
    _notify();
  }

  String get _phoneModel {
    if (kIsWeb) return 'Web';
    final os = defaultTargetPlatform == TargetPlatform.iOS ? 'iPhone' : 'Android';
    return os;
  }

  Future<Map<String, dynamic>?> _authPost(String path, Map<String, dynamic> body, [Duration timeout = const Duration(seconds: 8)]) async {
    try {
      final r = await http
          .post(Uri.parse('http://${settings.localHost}:${settings.localPort}$path'),
              headers: {'Content-Type': 'application/json; charset=utf-8'}, body: jsonEncode(body))
          .timeout(timeout);
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      return null;
    }
  }

  /// 2.0.24: after the in-app hub setup: this hub's id and address, and the owner key when this phone claimed it.
  Future<void> applyHubSetup({required String hub, required String ip, String key = ''}) async {
    final j = settings.toJson();
    if (hub.length == 12) j['hubId'] = hub.toUpperCase();
    if (ip.isNotEmpty) j['localHost'] = ip;
    if (key.isNotEmpty) {
      j['ownerKey'] = key;
      j['sharedUser'] = '';
      j['sharedName'] = '';
      j['sharedRole'] = 0;
    }
    hubLocked = false;
    await saveSettings(HubSettings.fromJson(j));
  }

  /// true once the hub answers on the home network at [ip]
  Future<bool> hubAnswersAt(String ip) async {
    try {
      final r = await http
          .get(Uri(scheme: 'http', host: ip, port: settings.localPort, path: '/'), headers: _localHeaders)
          .timeout(const Duration(seconds: 3));
      return r.statusCode == 200 && r.body.contains('Fisha Hub');
    } catch (_) {
      return false;
    }
  }

  String get phoneModel => _phoneModel;

  Future<void> _useOwnerKey(String key) async {
    final j = settings.toJson()
      ..['ownerKey'] = key
      ..['sharedUser'] = ''
      ..['sharedName'] = ''
      ..['sharedRole'] = 0;
    if (settings.isShared) {                     // was a family member before: back to the owner's own connection
      final d = HubSettings();
      j['username'] = d.username;
      j['password'] = '';
    }
    hubLocked = false;
    await saveSettings(HubSettings.fromJson(j));
  }

  /// Locks the hub to this phone: the hub's update password proves it is yours. Returns an error text, or null.
  Future<String?> claimHub(String otaPass) async {
    if (googleEmail.isEmpty) return t('lock_need_google');
    final j = await _authPost('/api/auth/claim', {'ota': otaPass, 'email': googleEmail, 'model': _phoneModel});
    if (j == null) return t('lock_no_hub');
    if (j['ok'] != true) {
      final e = (j['error'] ?? '').toString();
      if (e == 'claim_window') return Tr.isAr ? 'تسجيل المالك متاح أول 10 دقايق بعد تشغيل الهاب. افصل الهاب ورجّعه وجرّب تاني.' : 'Claiming is open for 10 minutes after the hub powers on. Power-cycle the hub and try again.';
      if (e == 'claimed') return t('lock_claimed');
      return e == 'wrong_password' ? t('lock_wrong_pass') : e == 'wait' ? t('lock_wait') : t('err_failed');
    }
    final key = (j['data'] is Map ? j['data']['key'] : null)?.toString() ?? '';
    if (key.isEmpty) return t('err_failed');
    await _useOwnerKey(key);
    return null;
  }

  /// Asks the hub for access. Returns (id, code) to show on this phone, or an error key in [error].
  Future<({int id, int code, String? error})> requestAccess() async {
    if (googleEmail.isEmpty) return (id: 0, code: 0, error: t('lock_need_google'));
    final j = await _authPost('/api/pair/request', {'email': googleEmail, 'model': _phoneModel});
    if (j == null) return (id: 0, code: 0, error: t('lock_no_hub'));
    final d = j['data'];
    if (j['ok'] != true || d is! Map) {
      final e = (j['error'] ?? '').toString();
      return (id: 0, code: 0, error: e == 'busy' ? t('err_busy') : e == 'not_claimed' ? t('lock_not_claimed') : t('err_failed'));
    }
    return (id: (d['id'] as num).toInt(), code: (d['code'] as num).toInt(), error: null);
  }

  /// One check of a request: pending · ok (this phone is in now) · refused · expired · error.
  Future<String> pollAccess(int id, int code) async {
    final j = await _authPost('/api/pair/poll', {'id': id, 'code': code}, const Duration(seconds: 5));
    final d = j?['data'];
    if (d is! Map) return 'error';
    final st = (d['state'] ?? '').toString();
    if (st != 'ok') return st;
    final key = (d['key'] ?? '').toString();
    final code0 = (d['code'] ?? '').toString();
    if (key.isNotEmpty) {
      await _useOwnerKey(key);
    } else if (code0.isNotEmpty && await joinWithCode(code0)) {
      hubLocked = false;
    } else {
      return 'error';
    }
    _notify();
    return 'ok';
  }

  /// The owner's answer to a phone asking in: [pick] is the number chosen, [role] 0 view · 1 control, -1 refuses.
  Future<CmdResult> answerPair(int id, int pick, int role) async {
    final r = await _job('pair_answer', {'id': id, 'pick': pick, 'role': role});
    pairRequests = pairRequests.where((p) => p.id != id).toList();
    _notify();
    if (!r.ok && r.error == 'wrong_number') return CmdResult(false, t('lock_wrong_number'));
    if (!r.ok && r.error == 'expired') return CmdResult(false, t('lock_expired'));
    if (r.ok && role >= 0) _mirrorSoon();
    return r;
  }

  Future<CmdResult> removeOwnerPhone(String email) => api('owner_remove', {'email': email});

  Future<bool> joinWithCode(String code) async {
    final j = AppState.decodeInvite(code);
    if (j == null) return false;
    final lip = (j['lip'] ?? j['lh'] ?? '').toString();
    await saveSettings(HubSettings(
      hubId: j['hub'].toString().toUpperCase(),
      brokerHost: j['h'].toString(),
      brokerPort: (j['p'] as num?)?.toInt() ?? 8883,
      username: j['u'].toString(),
      password: j['pw'].toString(),
      localHost: lip,
      sharedUser: j['u'].toString(),
      sharedName: (j['n'] ?? '').toString(),
      sharedRole: (j['r'] as num?)?.toInt() ?? 0,
    ));
    return true;
  }

  /// Back to being the owner of your own hub (default connection settings).
  Future<void> leaveShared() => saveSettings(HubSettings());

  bool get isShared => settings.isShared;

  bool get canControl => !settings.isShared || settings.sharedRole >= 1;

  bool get canAdmin => !settings.isShared || settings.sharedRole >= 2;

  bool get isOwner => !settings.isShared;

  /// One of [Perm]: the owner and admins have them all, other members only what the owner granted.
  bool can(int perm) => canAdmin || (sharedPerms & perm) != 0;

  /// 0 view · 1 control · 2 admin · 3 owner
  int get myRole => settings.isShared ? settings.sharedRole : 3;

  // a member's phone tells the hub its Google email and photo, so the owner's family page shows them
  Future<void> _syncProfile(Map me) async {
    if (_profileSending || googleEmail.isEmpty) return;
    if ((me['email'] ?? '') == googleEmail && (me['photo'] ?? '') == googlePhoto) return;
    _profileSending = true;
    try {
      await api('profile', {'email': googleEmail, 'photo': googlePhoto});
    } finally {
      _profileSending = false;
    }
  }
}
