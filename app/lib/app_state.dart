import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color, HSLColor;
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'i18n.dart';
import 'models.dart';
import 'services/firmware_upload.dart';
import 'services/google_sync.dart';
import 'services/mqtt_factory.dart';
import 'services/outlet_history.dart';
import 'services/widget_data.dart';

enum ConnMode { offline, local, cloud }

/// The hub's plain-http LAN API is reachable: always on the phone; on the web only when the page itself is
/// served over http (the launcher page on the hub, http://<hub>:8080/app), since an https page blocks it.
final bool kLocalCapable = !kIsWeb || Uri.base.scheme == 'http';

enum ViewMode { list, grid }

enum SortMode { manual, power, name, status }

enum ThemePref { system, dark, light, graphite, saffron, midnight, pearl }

enum LangPref { system, ar, en }

class HubSettings {
  String hubId;
  String brokerHost;
  int brokerPort;
  String username;
  String password;
  String localHost;
  int localPort;
  /// password of the hub's own server user (ESP32_hub); the app hands it to the hub on the home Wi-Fi
  String hubPass;
  /// set when this phone was invited by the owner: remote-only, limited to what the owner allowed
  String sharedUser;
  String sharedName;
  int sharedRole;
  /// 2.0.18: this phone's key from the hub (hub 2.15.13 lock). Empty until the owner locks the hub from this phone.
  String ownerKey;

  HubSettings({
    this.hubId = '80F3DA40F674',
    this.brokerHost = 't0eb1112.ala.eu-central-1.emqxsl.com',
    this.brokerPort = 8883,
    this.username = 'fisha_app',
    this.password = '',
    this.localHost = '192.168.1.100',
    this.localPort = 8080,
    this.hubPass = '',
    this.sharedUser = '',
    this.sharedName = '',
    this.sharedRole = 0,
    this.ownerKey = '',
  });

  bool get isShared => sharedUser.isNotEmpty;
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
        'hubPass': hubPass,
        'sharedUser': sharedUser,
        'sharedName': sharedName,
        'sharedRole': sharedRole,
        'ownerKey': ownerKey,
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
      hubPass: (j['hubPass'] ?? '').toString(),
      sharedUser: (j['sharedUser'] ?? '').toString(),
      sharedName: (j['sharedName'] ?? '').toString(),
      sharedRole: (j['sharedRole'] as num?)?.toInt() ?? 0,
      ownerKey: (j['ownerKey'] ?? '').toString(),
    );
  }
}

class OwnerPhone {
  final String email, model;
  final int ts;
  const OwnerPhone(this.email, this.model, this.ts);
  factory OwnerPhone.fromJson(Map m) => OwnerPhone((m['email'] ?? '').toString(), (m['model'] ?? '').toString(), (m['ts'] as num?)?.toInt() ?? 0);
}

class PairRequest {
  final int id;
  final String email, model;
  final bool owner;                              // same email as an owner phone: approving makes it an owner phone
  final List<int> choices;
  const PairRequest(this.id, this.email, this.model, this.owner, this.choices);
  factory PairRequest.fromJson(Map m) => PairRequest(
        (m['id'] as num?)?.toInt() ?? 0,
        (m['email'] ?? '').toString(),
        (m['model'] ?? '').toString(),
        m['owner'] == true,
        (m['choices'] is List ? (m['choices'] as List) : const []).whereType<num>().map((e) => e.toInt()).toList(),
      );
}

class CmdResult {
  final bool ok;
  final String? error;
  final Map<String, dynamic>? data;
  const CmdResult(this.ok, [this.error, this.data]);
}

class AppState extends ChangeNotifier {
  static const ssePort = 8081;
  static const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

  SharedPreferences? _prefs;
  HubSettings settings = HubSettings();
  bool ready = false;

  // live data
  List<Strip> _strips = [];
  List<HubTimer> timers = [];
  ConnMode mode = ConnMode.offline;
  bool mqttConnected = false;
  bool hubOnline = false;
  // the hub's own link to the server, reported by hub 2.9+ over the home Wi-Fi
  bool? hubCloudUp;
  String hubCloudErr = '';
  bool hubHasPass = true;
  bool emqxSet = false;
  int usersCount = 0;
  DateTime? _passPushedAt;
  String _passPushedValue = '';
  // account: '' (not chosen yet) | local | google
  String accountType = '';
  String googleEmail = '';
  String googlePhoto = ''; // Google account photo link, shown wherever this person's name is
  int sharedPerms = 0; // a member's extra permissions, from the hub's "me"
  DateTime? lastSync;
  bool sseLive = false;
  bool hubTimeOk = false;
  String? hubFw;
  // 2.0.18 hub lock (hub 2.15.13): the hub refused this phone (no key, or a key it no longer knows)
  bool hubLocked = false;
  bool? hubClaimed;                              // null: hub older than 2.15.13 or not heard yet
  List<OwnerPhone> ownerPhones = [];
  List<PairRequest> pairRequests = [];
  int tempMax = 70;
  // whole-strip protections (hub 2.10+)
  bool vProtect = true, vRestore = true, aProtect = true;
  int vMax = 250;
  int vMin = 190;
  double aMax = 16;
  bool hubHasStripProt = false;
  String hubReset = '';
  String ntfyTopic = '';
  int notifyTypes = 0x7FF;
  String otaPass = '';
  String hubSsid = '';
  String wifiTest = 'idle';
  String wifiTestSsid = '';
  bool tempProtect = true;
  String provState = 'idle';
  String provMsg = '';
  String? lastError;
  DateTime? lastUpdate;

  // events
  final List<HubEvent> events = [];
  final Set<String> _eventKeys = {};
  HubEvent? lastAlert;
  int unread = 0;

  // caches
  List<Schedule> schedules = [];
  List<Automation> automations = [];

  // preferences
  ViewMode viewMode = ViewMode.list;
  SortMode sortMode = SortMode.manual;
  ThemePref themePref = ThemePref.system;
  LangPref langPref = LangPref.system;
  bool showMac = false;
  double tariff = 1.0;
  String query = '';
  int tab = 0;
  List<String> _order = [];
  Map<String, String> _names = {}; // phone-side fallback names (very old hub firmware)

  int? hubUptimeS;
  String userName = '';
  List<Room> rooms = [];

  // widget throttling
  DateTime? _lastWidgetUpdate;
  Timer? _widgetThrottleTimer;

  // internals
  final Map<String, Map<int, bool>> _pending = {};
  // hub 2.15.38 cloud state: a small head (mttl/<hub>/state with "strips":[MACs]) and one retained message per strip
  Map<String, dynamic>? _cloudHead;
  final Map<String, Map<String, dynamic>> _cloudStrips = {};
  final Map<String, Completer<Map<String, dynamic>>> _acks = {};
  Timer? _pollTimer;
  Timer? _mqttRetry;
  MqttClient? _mqtt;
  StreamSubscription? _mqttSub;
  http.Client? _sseClient;
  bool _sseRunning = false;
  DateTime? _lastLocalOk;
  bool _polling = false;
  int _seq = 0;
  int _gen = 0; // bumps on restart so old loops stop

  bool get hubV2 => hubFw != null && !hubFw!.startsWith('1.');
  bool get hubHasConfig => hubFw != null && hubFw != '1.0-alpha';

  // ---------- lifecycle ----------
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _loadPrefs();
    _loadPendingOps();
    if (pendingOps.isNotEmpty) _savePendingOps();
    ready = true;
    await restart();
    // the web build has no Google sign-in (see WEB.md)
    if (!kIsWeb && accountType == 'google') {
      GoogleSync.I.restore().then((ok) async {
        final ph = GoogleSync.I.photoUrl ?? '';          // a restored sign-in has the photo too (older builds never saved it)
        if (ok && ph.isNotEmpty && ph != googlePhoto) {
          googlePhoto = ph;
          await _prefs?.setString('googlePhoto', ph);
          notifyListeners();
        }
        if (ok && lastSync != null) {
          _startAutoSync();
          Future.delayed(const Duration(seconds: 20), _autoSync);
        }
      });
    }
  }

  // ---------- Google account: optional sign-in + settings sync (Drive appDataFolder) ----------
  Timer? _syncTimer;
  String _lastSyncSig = '';

  // per-phone keys that must not travel between devices through the Google copy
  static const _noSyncKeys = {'lastSync', 'accountType', 'googleEmail', 'pendingOps', 'notifyFilter'};

  /// 2.0.18: how often the automatic sync uploads (minutes): 0 = whenever something changed (checked every 10 min)
  int syncEveryMin = 0;
  static const syncChoices = [0, 60, 1440, 10080];
  Future<void> setSyncEvery(int m) async {
    syncEveryMin = m;
    await _prefs?.setInt('syncEvery', m);
    notifyListeners();
  }

  /// 2.0.20: pauses automatic sync without signing out of the Google account (a manual "زامن دلوقتي" still works).
  bool syncPaused = false;
  Future<void> setSyncPaused(bool v) async {
    syncPaused = v;
    await _prefs?.setBool('syncPaused', v);
    if (!v) _startAutoSync();
    notifyListeners();
  }

  /// 2.0.20: how many past copies to keep on Drive (the rest are pruned after each upload).
  int syncKeepVersions = 5;
  Future<void> setSyncKeepVersions(int n) async {
    syncKeepVersions = n.clamp(1, 10);
    await _prefs?.setInt('syncKeep', syncKeepVersions);
    notifyListeners();
  }

  /// Every saved copy on Drive, newest first; throws on a Drive error.
  Future<List<SyncVersion>> listGoogleVersions() => GoogleSync.I.listVersions();

  Future<Map<String, dynamic>> _syncPayload() async {
    // 2.0.18: the copy of the hub's data (rules, schedules, names, protection, family) is refreshed first, so the
    // upload carries everything as it is now, not as it was at the last 15-minute refresh
    if (!settings.isShared && mode != ConnMode.offline && _hubNvs.isNotEmpty) await _refreshMirror();
    final b = await exportBackup(parts: {'app'}, withSecrets: true);
    final app = b['app'];
    if (app is Map) app.removeWhere((k, _) => _noSyncKeys.contains(k));
    return b;
  }

  String _googleErr(Object e, [String fallback = 'g_sync_failed']) {
    if (e is GoogleSyncError) {
      switch (e.code) {
        case 'not_configured':
          return t('g_err_not_configured');
        case 'network':
          return t('g_err_network');
        case 'drive_disabled':
          return t('g_err_drive_disabled');
        case 'auth':
          return t('g_err_auth');
      }
      return '${t(fallback)} (${e.detail})';
    }
    return t(fallback);
  }

  /// null = signed in; otherwise a message for the user.
  /// Auto-sync starts only after the first restore or upload, so it can never overwrite the Google copy
  /// while the user is still deciding whether to restore it.
  Future<String?> googleSignIn() async {
    try {
      final e = await GoogleSync.I.signIn();
      if (e == null) return t('g_cancelled');
      await setAccount('google', email: e);
      googlePhoto = GoogleSync.I.photoUrl ?? '';
      await _prefs?.setString('googlePhoto', googlePhoto);
      if (userName.isEmpty) {
        final dn = GoogleSync.I.displayName;
        await setUserName(dn != null && dn.trim().isNotEmpty ? dn : e.split('@').first);
      }
      return null;
    } catch (e) {
      return _googleErr(e, 'g_failed');
    }
  }

  /// true / false, or null when Google could not be checked (then nothing must be uploaded).
  Future<bool?> googleHasData() async {
    try {
      return await GoogleSync.I.download() != null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> syncNow() async {
    try {
      final b = await _syncPayload();
      await GoogleSync.I.upload(b, keep: syncKeepVersions);
      _lastSyncSig = jsonEncode(b['app']);
      await markSynced();
      if (_syncTimer == null) _startAutoSync();
      return null;
    } catch (e) {
      return _googleErr(e);
    }
  }

  /// Restores a specific saved copy ([id]), or the newest one when [id] is null.
  Future<String?> restoreFromGoogle([String? id]) async {
    try {
      final b = await GoogleSync.I.download(id);
      if (b == null) return t('g_no_data');
      final app = b['app'];
      if (app is Map) app.removeWhere((k, _) => _noSyncKeys.contains(k));
      final r = await importBackup(b, parts: {'app'});
      _lastSyncSig = jsonEncode(b['app']);
      await markSynced();
      if (_syncTimer == null) _startAutoSync();
      return r;
    } catch (e) {
      return _googleErr(e);
    }
  }

  Future<void> useLocalAccount() async {
    _syncTimer?.cancel();
    _syncTimer = null;
    if (accountType == 'google') {
      try {
        await GoogleSync.I.signOut();
      } catch (_) {}
    }
    await setAccount('local');
  }

  /// Leaves the account (Google or local) and goes back to the welcome screen. Data on this phone stays.
  Future<void> logout() async {
    _syncTimer?.cancel();
    _syncTimer = null;
    if (accountType == 'google') {
      await _autoSync();
      try {
        await GoogleSync.I.signOut();
      } catch (_) {}
    }
    // 2.0.18: signing out leaves nothing behind: no hub key, no family login, no strips on screen
    _strips = [];
    timers = [];
    ownerPhones = [];
    pairRequests = [];
    await saveSettings(HubSettings());
    await setAccount('');
  }

  void _startAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(minutes: 10), (_) => _autoSync());
  }

  Future<void> _autoSync() async {
    if (accountType != 'google' || syncPaused) return;
    if (syncEveryMin > 0 && lastSync != null && DateTime.now().difference(lastSync!) < Duration(minutes: syncEveryMin)) return;
    try {
      final b = await _syncPayload();
      final sig = jsonEncode(b['app']);
      if (sig == _lastSyncSig) return;
      await GoogleSync.I.upload(b, keep: syncKeepVersions);
      _lastSyncSig = sig;
      await markSynced();
    } catch (_) {}
  }

  void _loadPrefs() {
    final p = _prefs;
    if (p == null) return;
    final s = p.getString('settings');
    if (s != null) {
      try {
        settings = HubSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);
        // hub moved from .110 to .100 with firmware 2.13.1
        if (!settings.isShared && settings.localHost == '192.168.1.110') settings.localHost = '192.168.1.100';
      } catch (_) {}
    }
    int idx(String k, int len) => (p.getInt(k) ?? 0).clamp(0, len - 1);
    viewMode = ViewMode.values[idx('viewMode', ViewMode.values.length)];
    sortMode = SortMode.values[idx('sortMode', SortMode.values.length)];
    themePref = ThemePref.values[idx('themePref', ThemePref.values.length)];
    langPref = LangPref.values[idx('langPref', LangPref.values.length)];
    showMac = p.getBool('showMac') ?? false;
    tariff = p.getDouble('tariff') ?? 1.0;
    otaPass = p.getString('otaPass') ?? '';
    accountType = p.getString('accountType') ?? '';
    googleEmail = p.getString('googleEmail') ?? '';
    googlePhoto = p.getString('googlePhoto') ?? '';
    syncEveryMin = p.getInt('syncEvery') ?? 0;
    syncPaused = p.getBool('syncPaused') ?? false;
    syncKeepVersions = (p.getInt('syncKeep') ?? 5).clamp(1, 10);
    final ls = p.getString('lastSync');
    lastSync = ls == null ? null : DateTime.tryParse(ls);
    userName = p.getString('userName') ?? '';
    _order = p.getStringList('order') ?? [];
    final n = p.getString('names');
    if (n != null) {
      try {
        _names = Map<String, String>.from(jsonDecode(n) as Map);
      } catch (_) {}
    }
    final rm = p.getString('rooms');
    if (rm != null) {
      try {
        rooms = (jsonDecode(rm) as List).whereType<Map<String, dynamic>>().map(Room.fromJson).toList();
      } catch (_) {}
    }
  }

  // secrets a backup file must not carry in plain text (the Google copy lives in the app's private Drive folder)
  static const _secretPrefs = {'otaPass'};
  static const _secretSettings = {'password', 'hubPass', 'ownerKey'};

  Future<Map<String, dynamic>> exportBackup({Set<String> parts = const {'app', 'hub'}, bool withSecrets = false}) async {
    final out = <String, dynamic>{
      'fisha_backup': 1,
      'created': DateTime.now().toIso8601String(),
      'app_version': appVersion,
    };

    if (parts.contains('app')) {
      final appMap = <String, dynamic>{};
      final p = _prefs ?? await SharedPreferences.getInstance();
      _prefs = p;
      for (final k in p.getKeys()) {
        if (k == 'pendingOps' || k == 'notifyFilter') continue;      // this phone's queue / cache, not a setting
        final v = p.get(k);
        if (v is bool) {
          appMap[k] = {'t': 'b', 'v': v};
        } else if (v is int) {
          appMap[k] = {'t': 'i', 'v': v};
        } else if (v is double) {
          appMap[k] = {'t': 'd', 'v': v};
        } else if (v is List) {
          appMap[k] = {'t': 'l', 'v': v.map((e) => e.toString()).toList()};
        } else if (v is String) {
          appMap[k] = {'t': 's', 'v': v};
        }
      }
      if (!withSecrets) {
        appMap.removeWhere((k, _) => _secretPrefs.contains(k));
        final st = appMap['settings'];
        if (st is Map && st['v'] is String) {
          try {
            final m = Map<String, dynamic>.from(jsonDecode(st['v'] as String) as Map)
              ..removeWhere((k, _) => _secretSettings.contains(k));
            appMap['settings'] = {'t': 's', 'v': jsonEncode(m)};
          } catch (_) {
            appMap.remove('settings');
          }
        }
      }
      out['app'] = appMap;
    }

    if (parts.contains('hub') && mode != ConnMode.offline) {
      await loadSchedules();
      await loadAutomations();
      final users = settings.isShared ? null : await _exportUsers();
      out['hub'] = <String, dynamic>{
        if (users != null) 'users': users,
        'schedules': [for (final s in schedules) if (s.sid > 0) s.toJson()],
        'automations': [for (final a in automations) if (a.aid > 0) a.toJson()],
        'strips': [
          for (final s in allStrips)
            {
              'mac': s.mac,
              'label': s.label,
              'notify': s.notifyMask,
              'notifyMask': s.notifyMask,
              'outlets': [
                for (final o in s.outlets)
                  {
                    'n': o.n,
                    'label': o.label,
                    'locked': o.locked,
                    'protected': o.protected,
                    'autooff': o.autoOffMin,
                    'auto_off_min': o.autoOffMin,
                    'keep_on': o.keepOn,
                    'keepOn': o.keepOn,
                    'amp_limit': o.ampLimit,
                  }
              ],
            }
        ],
        // 2.0.23: the daily energy history travels with every backup / Google sync (compact rows yyyymmdd:wh1:wh2:wh3:wh4:peak)
        'energy': await _exportEnergy(),
        'config': {
          'temp_max': tempMax,
          'temp_protect': tempProtect,
          if (hubHasStripProt) ...{
            'v_protect': vProtect,
            'v_restore': vRestore,
            'v_max': vMax,
            'v_min': vMin,
            'a_protect': aProtect,
            'a_max': aMax,
          },
          'ntfy': ntfyTopic,
          'notifyTypes': notifyTypes,
        },
      };
    }

    return out;
  }

  Future<Map<String, String>> _exportEnergy() async {
    final out = <String, String>{};
    for (final s in allStrips) {
      // 2.0.25: the history lives on the hub, so an offline strip's days are exported too
      final r = await api('energy', {'mac': s.mac});
      final days = r.data?['days'];
      if (!r.ok || days is! List) continue;
      final rows = <String>[];
      for (final d in days) {
        if (d is! Map) continue;
        final wh = d['wh'];
        if (wh is! List || wh.length < 4) continue;
        rows.add('${d['date']}:${wh[0]}:${wh[1]}:${wh[2]}:${wh[3]}:${(d['peak_w'] as num?)?.toInt().clamp(0, 65535) ?? 0}');
      }
      if (rows.isNotEmpty) out[s.mac] = rows.join(';');
    }
    return out;
  }

  Future<String?> importBackup(Map<String, dynamic> j, {Set<String> parts = const {'app', 'hub'}, bool replace = false}) async {
    if (j['fisha_backup'] != 1) return t('backup_err_invalid');

    int skipped = 0;
    if (parts.contains('hub') && j['hub'] is Map<String, dynamic>) {
      if (mode == ConnMode.offline) return t('err_no_conn');
      final hubData = j['hub'] as Map<String, dynamic>;

      // schedules
      if (hubData['schedules'] is List) {
        if (replace) {
          await loadSchedules();
          for (final s in schedules) {
            await api('schedule_delete', {'sid': s.sid});
          }
        }
        for (final raw in hubData['schedules']) {
          if (raw is Map) {
            final m = Map<String, dynamic>.from(raw)..remove('sid');
            await api('schedule_save', m);
          }
        }
      }

      // automations
      if (hubData['automations'] is List) {
        if (replace) {
          await loadAutomations();
          for (final a in automations) {
            await api('automation_delete', {'aid': a.aid});
          }
        }
        for (final raw in hubData['automations']) {
          if (raw is Map) {
            final m = Map<String, dynamic>.from(raw)..remove('aid');
            await api('automation_save', m);
          }
        }
      }

      // family members (hub 2.15+), with their own passwords so their phones keep working
      if (hubData['users'] is List && !settings.isShared) {
        for (final raw in hubData['users']) {
          if (raw is! Map || (raw['pw'] ?? '').toString().isEmpty) continue;
          final st = raw['strips'];
          await api('user_restore', {
            'id': raw['id'],
            'name': raw['name'],
            'role': raw['role'],
            'perms': raw['perms'] ?? 0,
            'all': raw['all'] == true,
            'strips': st is List ? st.join(',') : (st ?? '').toString(),
            'pw': raw['pw'],
          });
        }
      }

      // strips
      final currentMacs = allStrips.map((s) => s.mac.toUpperCase()).toSet();
      // energy history (hub 2.15.27+): days the hub already has are never overwritten
      final en = hubData['energy'];
      if (en is Map && !settings.isShared) {
        for (final e in en.entries) {
          if (e.value is String && (e.value as String).isNotEmpty) await api('energy_restore', {'mac': e.key.toString(), 'd': e.value});
        }
      }

      if (hubData['strips'] is List) {
        for (final raw in hubData['strips']) {
          if (raw is! Map) continue;
          final mac = (raw['mac'] ?? '').toString().toUpperCase();
          if (mac.isEmpty || !currentMacs.contains(mac)) {
            skipped++;
            continue;
          }
          final label = (raw['label'] ?? '').toString();
          if (label.isNotEmpty) {
            await api('label', {'mac': mac, 'outlet': 0, 'label': label});
          }
          final mask = raw['notifyMask'] ?? raw['notify'];
          if (mask is num) {
            await api('notify', {'mac': mac, 'mask': mask.toInt()});
          }
          final outlets = raw['outlets'];
          if (outlets is List) {
            for (final o in outlets) {
              if (o is! Map) continue;
              final n = (o['n'] as num?)?.toInt() ?? 0;
              if (n <= 0) continue;
              final oLabel = (o['label'] ?? '').toString();
              if (oLabel.isNotEmpty) {
                await api('label', {'mac': mac, 'outlet': n, 'label': oLabel});
              }
              if (o.containsKey('locked')) {
                await api('lock', {'mac': mac, 'outlet': n, 'locked': o['locked'] == true});
              }
              if (o.containsKey('protected')) {
                await api('protect', {'mac': mac, 'outlet': n, 'protected': o['protected'] == true});
              }
              if (o.containsKey('keep_on') || o.containsKey('keepOn')) {
                final keep = (o['keep_on'] ?? o['keepOn']) == true;
                await api('keepon', {'mac': mac, 'outlet': n, 'on': keep});
              }
              if (o['amp_limit'] is num) {
                await api('amplimit', {'mac': mac, 'outlet': n, 'max_a': (o['amp_limit'] as num).toDouble()});
              }
              if (o.containsKey('autooff') || o.containsKey('auto_off_min') || o.containsKey('autoOffMin')) {
                final min = num.tryParse('${o['autooff'] ?? o['auto_off_min'] ?? o['autoOffMin'] ?? 0}')?.toInt() ?? 0;
                await api('autooff', {'mac': mac, 'outlet': n, 'minutes': min});
              }
            }
          }
        }
      }

      // config & notify
      final cfg = hubData['config'] is Map ? hubData['config'] as Map : hubData;
      final tempMax = (cfg['temp_max'] as num?)?.toInt();
      final tempProtect = cfg['temp_protect'] is bool ? cfg['temp_protect'] as bool : null;
      if (tempMax != null || tempProtect != null) {
        await api('config', {
          if (tempProtect != null) 'temp_protect': tempProtect,
          if (tempMax != null) 'temp_max': tempMax,
        });
      }
      // 2.0.18: whole-strip protection (voltage and current limits)
      final prot = <String, dynamic>{
        for (final k in ['v_protect', 'v_restore', 'a_protect'])
          if (cfg[k] is bool) k: cfg[k],
        for (final k in ['v_max', 'v_min', 'a_max'])
          if (cfg[k] is num) k: cfg[k],
      };
      if (prot.isNotEmpty) await api('config', prot);
      final ntfy = (cfg['ntfy'] ?? cfg['ntfy_topic'])?.toString();
      final nt = cfg['notifyTypes'] ?? cfg['notify_types'] ?? cfg['ntypes'];
      final ntypes = nt == null ? null : num.tryParse('$nt')?.toInt();
      if (ntfy != null || ntypes != null) {
        await api('notify', {
          if (ntfy != null) 'ntfy': ntfy,
          if (ntypes != null) 'types': ntypes,
        });
      }

      await loadSchedules();
      await loadAutomations();
      await refresh();
    }

    if (parts.contains('app') && j['app'] is Map<String, dynamic>) {
      final appMap = j['app'] as Map<String, dynamic>;
      final p = _prefs ?? await SharedPreferences.getInstance();
      _prefs = p;
      for (final entry in appMap.entries) {
        final k = entry.key;
        var item = entry.value;
        if (k == 'settings' && item is Map && item['v'] is String) {
          // a backup file has no passwords: keep the ones already on this phone
          try {
            final m = Map<String, dynamic>.from(jsonDecode(item['v'] as String) as Map);
            final cur = settings.toJson();
            for (final sk in _secretSettings) {
              if ((m[sk] ?? '').toString().isEmpty) m[sk] = cur[sk];
            }
            item = {'t': 's', 'v': jsonEncode(m)};
          } catch (_) {}
        }
        if (item is Map) {
          final t = item['t'];
          final v = item['v'];
          if (t == 'b' && v is bool) {
            await p.setBool(k, v);
          } else if (t == 'i' && v is num) {
            await p.setInt(k, v.toInt());
          } else if (t == 'd' && v is num) {
            await p.setDouble(k, v.toDouble());
          } else if (t == 's' && v is String) {
            await p.setString(k, v);
          } else if (t == 'l' && v is List) {
            await p.setStringList(k, v.map((e) => e.toString()).toList());
          }
        }
      }
      _loadPrefs();
      await restart();
    }

    if (skipped > 0) {
      return t('backup_skipped', {'n': '$skipped'});
    }
    return null;
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _widgetThrottleTimer?.cancel();
    _stopAll();
    super.dispose();
  }

  void _stopAll() {
    _gen++;
    _pollTimer?.cancel();
    _pollTimer = null;
    _mqttRetry?.cancel();
    _sseRunning = false;
    _sseClient?.close();
    _sseClient = null;
    sseLive = false;
    _stopMqtt();
  }

  Future<void> saveSettings(HubSettings s) async {
    final passChanged = s.hubPass != settings.hubPass;
    settings = s;
    await _prefs?.setString('settings', jsonEncode(s.toJson()));
    if (passChanged) _passPushedValue = '';
    await restart();
  }

  /// Hands the hub its server password (hub 2.9+, home Wi-Fi only). The hub keeps it and reconnects only if it changed.
  Future<CmdResult> pushHubPass({bool force = false}) async {
    final p = settings.hubPass;
    if (p.isEmpty || settings.isShared) return CmdResult(false, t('cloud_need_pass'));
    if (!_localFresh) return CmdResult(false, t('err_local_only'));
    if (!force && _passPushedValue == p && _passPushedAt != null && DateTime.now().difference(_passPushedAt!) < const Duration(minutes: 2)) {
      return const CmdResult(true);
    }
    _passPushedAt = DateTime.now();
    _passPushedValue = p;
    return api('cloud', {'pass': p, 'host': settings.brokerHost, 'user': 'ESP_hub'});
  }

  /// Owner only: the hub's address on the home network (hub 2.15.20+). The hub restarts to use it.
  Future<CmdResult> pushHubLocalIp(String ip) async {
    if (settings.isShared || !_localFresh) return CmdResult(false, t('err_local_only'));
    return api('cloud', {'lip': ip});
  }

  bool get hubSupportsCloudCfg => hubCloudUp != null;

  Future<void> restart() async {
    _stopAll();
    _strips = [];
    timers = [];
    _lastLocalOk = null;
    mode = ConnMode.offline;
    hubOnline = false;
    hubCloudUp = null;
    hubCloudErr = '';
    notifyListeners();
    final gen = _gen;
    // https web page: the hub's plain-http LAN API is blocked as mixed content, so cloud only
    if (kLocalCapable && settings.hasLocal) {
      _pollLocal();
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (!sseLive) _pollLocal();
        _updateMode();
      });
      _runSse(gen);
    }
    if (settings.hasCloud) _startMqtt();
    Future.delayed(const Duration(seconds: 3), () {
      if (gen == _gen) loadEvents();
    });
  }

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

  // 2.0.18: when the hub's local data can't be read, the cloud copy is used for a while instead of an empty screen
  DateTime? _localBadAt;
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
            ? Uri.parse('http://${settings.localHost}:$ssePort/events?u=${settings.sharedUser}&t=${settings.password}')
            : settings.ownerKey.isNotEmpty
                ? Uri.parse('http://${settings.localHost}:$ssePort/events?t=${settings.ownerKey}')
                : Uri.parse('http://${settings.localHost}:$ssePort/events');
        final req = http.Request('GET', sseUri);
        req.headers['Accept'] = 'text/event-stream';
        req.headers.addAll(_localHeaders);
        final resp = await client.send(req).timeout(const Duration(seconds: 4));
        if (resp.statusCode != 200) throw http.ClientException('sse');
        sseLive = true;
        backoff = 2;
        _lastLocalOk = DateTime.now();
        _updateMode();
        notifyListeners();
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
        // hub older than v2.0, or not on this Wi-Fi
      }
      client.close();
      if (sseLive) {
        sseLive = false;
        notifyListeners();
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
      notifyListeners();
      updateWidgetThrottled();
      if (m != ConnMode.offline && pendingOps.isNotEmpty) Future.microtask(flushPending);
    }
  }

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
      try {
        c.disconnect();
      } catch (_) {}
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
      notifyListeners();
    } else if (topic == '$_base/event') {
      _addEventJson(text);
    } else if (topic == '$_base/info') {
      try {
        final j = jsonDecode(text) as Map<String, dynamic>;
        hubFw = j['fw']?.toString() ?? hubFw;
        notifyListeners();
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
      notifyListeners();
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
      notifyListeners();
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

  // ---------- 2.0.18 hub lock (hub 2.15.13) ----------
  void _setLocked(bool v) {
    if (v == hubLocked) return;
    hubLocked = v;
    notifyListeners();
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
      final r = await http.get(Uri.parse('http://$ip/'), headers: _localHeaders).timeout(const Duration(seconds: 3));
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
    notifyListeners();
    return 'ok';
  }

  /// The owner's answer to a phone asking in: [pick] is the number chosen, [role] 0 view · 1 control, -1 refuses.
  Future<CmdResult> answerPair(int id, int pick, int role) async {
    final r = await _job('pair_answer', {'id': id, 'pick': pick, 'role': role});
    pairRequests = pairRequests.where((p) => p.id != id).toList();
    notifyListeners();
    if (!r.ok && r.error == 'wrong_number') return CmdResult(false, t('lock_wrong_number'));
    if (!r.ok && r.error == 'expired') return CmdResult(false, t('lock_expired'));
    if (r.ok && role >= 0) _mirrorSoon();
    return r;
  }

  Future<CmdResult> removeOwnerPhone(String email) => api('owner_remove', {'email': email});

  // ---------- joining someone else's hub ----------
  static Map<String, dynamic>? decodeInvite(String code) {
    try {
      var c = code.trim().replaceAll(RegExp(r'\s'), '').replaceAll('-', '+').replaceAll('_', '/');
      while (c.length % 4 != 0) {
        c += '=';
      }
      final j = jsonDecode(utf8.decode(base64.decode(c)));
      if (j is! Map<String, dynamic> || j['u'] == null || j['pw'] == null || j['hub'] == null || j['h'] == null) return null;
      return j;
    } catch (_) {
      return null;
    }
  }

  Future<bool> joinWithCode(String code) async {
    final j = decodeInvite(code);
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

  bool _profileSending = false;
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

  // ---------- account ----------
  Future<void> setAccount(String type, {String email = ''}) async {
    accountType = type;
    googleEmail = email;
    await _prefs?.setString('accountType', type);
    await _prefs?.setString('googleEmail', email);
    notifyListeners();
  }

  Future<void> markSynced() async {
    lastSync = DateTime.now();
    await _prefs?.setString('lastSync', lastSync!.toIso8601String());
    notifyListeners();
  }

  void _fail(CmdResult r) {
    if (!r.ok) {
      lastError = r.error;
      notifyListeners();
    }
  }

  void clearError() => lastError = null;

  Future<bool> forget(String mac) async {
    final r = await api('forget', {'mac': mac});
    _fail(r);
    if (r.ok) {
      _strips = _strips.where((s) => s.mac != mac).toList();
      notifyListeners();
    }
    return r.ok;
  }

  Future<void> setOutlet(String mac, int outlet, bool on) async {
    final strip = live(mac);
    if (strip?.online == false) {
      lastError = t('strip_offline_cmd');
      notifyListeners();
      return;
    }
    // A master "all on/off" (outlet 0) leaves child-locked outlets alone — same as the hub (lockSkip, 2.15.23).
    // Without this the UI showed the locked outlet flip, then flip back once the real state came back unchanged.
    if (!canControl) {
      lastError = Tr.isAr ? 'صلاحيتك مشاهدة بس' : 'You can view only';
      notifyListeners();
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
      notifyListeners();
      return;
    }
    for (final x in targets) {
      p[x] = on;
    }
    final before = _strips;
    _strips = _strips.map((s) => s.mac == mac ? s.withOutletState({for (final x in targets) x: on}) : s).toList();
    notifyListeners();
    final r = await api('onoff', {'mac': mac, 'outlet': outlet, 'on': on});
    for (final x in targets) {
      p.remove(x);
    }
    if (!r.ok) {
      _strips = before;
      lastError = r.error;
    }
    notifyListeners();
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
      notifyListeners();
      final r = await api('label', {'mac': s.mac, 'outlet': outlet, 'label': v});
      if (!r.ok) _strips = before;
      _fail(r);
      notifyListeners();
      return;
    }
    final key = outlet == 0 ? 's:${s.mac}' : 'o:${s.mac}:$outlet';
    if (v.isEmpty) {
      _names.remove(key);
    } else {
      _names[key] = v;
    }
    await _prefs?.setString('names', jsonEncode(_names));
    notifyListeners();
  }

  Future<void> _flag(Strip s, int outlet, String action, Map<String, dynamic> body, Outlet Function(Outlet) apply) async {
    final before = _strips;
    _strips = _strips.map((x) => x.mac == s.mac ? x.withOutlet(outlet, apply) : x).toList();
    notifyListeners();
    final r = await api(action, {'mac': s.mac, 'outlet': outlet, ...body});
    if (!r.ok) _strips = before;
    _fail(r);
    notifyListeners();
  }

  Future<void> setLock(Strip s, int outlet, bool v) =>
      _flag(s, outlet, 'lock', {'locked': v}, (o) => o.copyWith(locked: v));
  Future<void> setMasterLock(Strip s, bool v) async {
    final before = _strips;
    _strips = _strips.map((x) => x.mac == s.mac ? x.withMasterLock(v) : x).toList();
    notifyListeners();
    final r = await api('lock', {'mac': s.mac, 'outlet': 0, 'locked': v});
    if (!r.ok) _strips = before;
    _fail(r);
    notifyListeners();
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
    notifyListeners();
    _fail(await api('timer_cancel', {'tid': tid}));
  }

  Future<void> setStripProtection({bool? vOn, bool? vBack, int? vLimit, int? vMinLimit, bool? aOn, double? aLimit}) async {
    if (vOn != null) vProtect = vOn;
    if (vBack != null) vRestore = vBack;
    if (vLimit != null) vMax = vLimit;
    if (vMinLimit != null) vMin = vMinLimit;
    if (aOn != null) aProtect = aOn;
    if (aLimit != null) aMax = aLimit;
    notifyListeners();
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
    notifyListeners();
    _fail(await api('config', {'temp_protect': tempProtect, 'temp_max': tempMax}));
  }

  // ---------- notifications (hub pushes them through ntfy) ----------
  /// Event type per bit of [notifyTypes], same order as the hub and the background service.
  static const notifyBitTypes = ['temp', 'load', 'auto_off', 'automation', 'schedule', 'missed', 'timer', 'cycle', 'lock', 'added', 'test',
      'button', 'remote', 'online', 'offline', 'voltage'];

  /// Whether [e] is one the user gets as a phone notification (type switched on, and that strip/outlet not muted).
  bool eventNotifies(HubEvent e) {
    if (e.type == 'test' || safetyTypes.contains(e.type)) return true;
    final bit = notifyBitTypes.indexOf(e.type);
    if (bit < 0 || notifyTypes & (1 << bit) == 0) return false;
    if (e.mac.isEmpty) return true;
    final st = _strips.where((x) => x.mac.toUpperCase() == e.mac);
    if (st.isEmpty) return true;
    final mask = st.first.notifyMask;
    return e.outlet == 0 ? mask & 0x10 != 0 : mask & (1 << (e.outlet - 1)) != 0;
  }

  /// The hub's own events that have no switch in notification settings; they go to the system log only (2.0.11).
  static bool isSystemEvent(String type) => type != 'test' && !notifyBitTypes.contains(type) && !safetyTypes.contains(type);

  /// Safety cuts (hub 2.15.9+): always sent to the phone, whatever the switches or mutes, so they sit in "My notifications".
  static const safetyTypes = {'overvolt', 'undervolt', 'overcurrent', 'overload', 'trip_fail', 'pair'};

  static const notifyTypeKeys = ['temp', 'load', 'auto_off', 'automation', 'schedule', 'missed', 'timer', 'cycle', 'lock', 'added'];

  /// The background notification service filters with the hub's state from the cloud; when that state is missing it
  /// let everything through. It now falls back to this copy of the user's choices (prefs 'notifyFilter').
  String _notifyFilterSaved = '';
  void _saveNotifyFilter() {
    final f = jsonEncode({'types': notifyTypes, 'masks': {for (final x in _strips) x.mac: x.notifyMask}});
    if (f == _notifyFilterSaved) return;
    _notifyFilterSaved = f;
    _prefs?.setString('notifyFilter', f);
  }

  Future<bool> setNotifyConfig({String? topic, int? types}) async {
    if (topic != null) ntfyTopic = topic;
    if (types != null) notifyTypes = types;
    _saveNotifyFilter();
    notifyListeners();
    final r = await api('notify', {if (topic != null) 'ntfy': topic, if (types != null) 'types': types});
    _fail(r);
    return r.ok;
  }

  Future<void> setNotifyMask(Strip s, int mask) async {
    final before = _strips;
    _strips = _strips.map((x) => x.mac == s.mac ? Strip(mac: x.mac, fw: x.fw, online: x.online, voltage: x.voltage, rssi: x.rssi, upS: x.upS, ip: x.ip, outlets: x.outlets, label: x.label, notifyMask: mask, hasSchedule: x.hasSchedule, hasRule: x.hasRule) : x).toList();
    _saveNotifyFilter();
    notifyListeners();
    final r = await api('notify', {'mac': s.mac, 'mask': mask});
    if (!r.ok) _strips = before;
    _fail(r);
    notifyListeners();
  }

  Future<bool> testNotify() async {
    final r = await api('notify', {'test': true});
    _fail(r);
    return r.ok;
  }

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
      notifyListeners();
    }
    return r;
  }

  // ---------- hub firmware update (local network only) ----------
  Future<void> setOtaPass(String v) async {
    otaPass = v;
    await _prefs?.setString('otaPass', v);
  }

  /// The password every hub accepts for updates: fisha-<hub MAC>. The owner may also set one of their own.
  String get defaultOtaPass => 'fisha-${settings.hubId.toUpperCase()}';

  /// Uploads a hub .bin trying, in order, the saved own password then the default fisha-<MAC>; if both fail it asks
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

  /// Owner: change the update password. [cur] = fisha-<MAC> or the current own one; [next] empty = back to the default.
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

  // ---------- strip firmware (hub 2.15.8+): the hub stores the .fwr and updates the chosen strips one by one ----------
  /// Quick check of an MTTL-W01 .fwr before sending it: 16-byte header with the body length and load address 0x10006000.
  /// The hub checks the checksum too.
  static bool looksLikeStripFw(List<int> b) {
    if (b.length < 65536) return false;
    int u32(int o) => b[o] | b[o + 1] << 8 | b[o + 2] << 16 | b[o + 3] << 24;
    return u32(4) == 0x10006000 && u32(0) + 20 == b.length;
  }

  Map<String, dynamic>? _hubJson(String body) {
    try {
      final j = jsonDecode(body);
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      return null;
    }
  }

  /// {size, valid, why, running, items:[{mac, from, to, state, msg, pct}]}, or null when the hub can't be reached
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
    if (!looksLikeStripFw(bytes)) return 'bad_file';
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
          .timeout(const Duration(seconds: 30));
      if (r.statusCode == 200) return null;
      return _hubJson(utf8.decode(r.bodyBytes))?['error']?.toString() ?? 'HTTP ${r.statusCode}';
    } catch (_) {
      return 'net';
    }
  }

  // ---------- schedules / automations ----------
  Future<bool> loadSchedules() async {
    final r = await api('schedules');
    if (r.ok && r.data != null) {
      final l = r.data!['schedules'];
      schedules = l is List ? l.whereType<Map<String, dynamic>>().map(Schedule.fromJson).toList() : [];
      schedules = _withPending(schedules, 'schedule', 'sid', (s) => s.sid, Schedule.fromJson);
      schedules.sort((a, b) => (a.hh * 60 + a.mm).compareTo(b.hh * 60 + b.mm));
      notifyListeners();
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
      _stateNow(); // outlet badges follow at once, even on a hub older than 2.15.2
    }
    return r.ok;
  }

  /// Skip only the next run of a schedule (hub 2.15+), or undo that.
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

  /// Rule to highlight when its page opens (from an outlet's menu); cleared once shown.
  int focusSid = 0;
  int focusAid = 0;

  Future<void> deleteSchedule(int sid) async {
    schedules = schedules.where((x) => x.sid != sid).toList();
    notifyListeners();
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
      notifyListeners();
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
    notifyListeners();
    if (aid < 0) return _dropQueued('automation', 'aid', aid);
    final r = await api('automation_delete', {'aid': aid});
    if (_isConnErr(r)) return _queueDelete('automation', 'aid', aid);
    _fail(r);
    await loadAutomations();
    _mirrorSoon();
    _stateNow();
  }

  // ---------- saves waiting for the hub (this phone only, key 'pendingOps') ----------
  // op: {'k': 'schedule'|'automation', 'del': bool, 'id': int (negative = new, not on the hub yet), 'b': body, 'q': queued at}
  List<Map<String, dynamic>> pendingOps = [];
  bool _flushing = false;
  Timer? _flushTimer;

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
    notifyListeners();
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
    notifyListeners();
    return true;
  }

  Future<void> _queueDelete(String kind, String idKey, int id) async {
    pendingOps.removeWhere((o) => o['k'] == kind && o['id'] == id);
    pendingOps.add({'k': kind, 'del': true, 'id': id, 'b': {idKey: id}, 'q': DateTime.now().toIso8601String()});
    _savePendingOps();
    lastError = t('queued_for_hub');
    notifyListeners();
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
          if (q != null && sc.enabled && _missedSince(sc, q, DateTime.now())) {
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

  /// true when the schedule had a run time after [from] and up to [to].
  static bool _missedSince(Schedule s, DateTime from, DateTime to) {
    if (s.days == 0) {
      if (s.date <= 0) return false;
      final at = DateTime(s.date ~/ 10000, (s.date ~/ 100) % 100, s.date % 100, s.hh, s.mm);
      return at.isAfter(from) && !at.isAfter(to);
    }
    var d = DateTime(from.year, from.month, from.day);
    for (var i = 0; i < 8 && !d.isAfter(to); i++, d = DateTime(d.year, d.month, d.day + 1)) {
      final at = DateTime(d.year, d.month, d.day, s.hh, s.mm);
      if (s.days & (1 << (d.weekday % 7)) != 0 && at.isAfter(from) && !at.isAfter(to)) return true;
    }
    return false;
  }

  // ---------- copy of the hub's data (prefs 'hubMirror': travels with Google sync and the backup file) ----------
  // The hub reports a storage id ('nvs', fw 2.15+) that changes only when its saved data is erased (e.g. a full
  // flash). Then the family members, schedules, rules and names come back from this copy by themselves.
  String _hubNvs = '';
  bool _mirrorBusy = false;
  bool _usersEditedHere = false;
  DateTime? _mirrorAt;
  Timer? _mirrorDebounce;

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
          notifyListeners();
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
      notifyListeners();
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
      notifyListeners();
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
    notifyListeners();
  }

  void markEventsRead() {
    unread = 0;
    notifyListeners();
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

  // ---------- provisioning ----------
  Future<CmdResult> startProvision() async {
    if (!hubHasConfig) return CmdResult(false, t('err_old_fw'));
    final r = await api('provision');
    if (r.ok) {
      provState = 'queued';
      provMsg = '';
      notifyListeners();
    }
    return r;
  }

  // ---------- UI prefs ----------
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

  Future<void> setThemePref(ThemePref m) async {
    themePref = m;
    await _prefs?.setInt('themePref', m.index);
    notifyListeners();
  }

  Future<void> setLangPref(LangPref m) async {
    langPref = m;
    await _prefs?.setInt('langPref', m.index);
    notifyListeners();
  }

  Future<void> setShowMac(bool v) async {
    showMac = v;
    await _prefs?.setBool('showMac', v);
    notifyListeners();
  }

  Future<void> setTariff(double v) async {
    tariff = v;
    await _prefs?.setDouble('tariff', v);
    notifyListeners();
  }

  void setQuery(String q) {
    query = q;
    notifyListeners();
  }

  void setTab(int i) {
    tab = i;
    notifyListeners();
  }

  Future<void> setUserName(String name) async {
    userName = name.trim();
    await _prefs?.setString('userName', userName);
    notifyListeners();
  }

  bool requiresBio(String mac, int n) => _prefs?.getBool('bio_${mac.toUpperCase()}_$n') ?? false;

  Future<void> setRequiresBio(String mac, int n, bool val) async {
    await _prefs?.setBool('bio_${mac.toUpperCase()}_$n', val);
    notifyListeners();
  }

  Room? roomForStrip(String mac) {
    final upper = mac.toUpperCase();
    for (final r in rooms) {
      if (r.stripMacs.contains(upper)) return r;
    }
    return null;
  }

  Future<void> saveRooms() async {
    await _prefs?.setString('rooms', jsonEncode([for (final r in rooms) r.toJson()]));
    notifyListeners();
  }

  Future<void> addRoom(String name) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    rooms.add(Room(id: id, name: name.trim()));
    await saveRooms();
  }

  Future<void> renameRoom(String id, String newName) async {
    final i = rooms.indexWhere((r) => r.id == id);
    if (i >= 0) {
      rooms[i] = rooms[i].copyWith(name: newName.trim());
      await saveRooms();
    }
  }

  Future<void> deleteRoom(String id) async {
    rooms.removeWhere((r) => r.id == id);
    await saveRooms();
  }

  Future<void> assignStripToRoom(String mac, String? roomId) async {
    final upper = mac.toUpperCase();
    for (var i = 0; i < rooms.length; i++) {
      if (rooms[i].stripMacs.contains(upper)) {
        final updated = List<String>.from(rooms[i].stripMacs)..remove(upper);
        rooms[i] = rooms[i].copyWith(stripMacs: updated);
      }
    }
    if (roomId != null && roomId.isNotEmpty) {
      final i = rooms.indexWhere((r) => r.id == roomId);
      if (i >= 0) {
        final updated = List<String>.from(rooms[i].stripMacs);
        if (!updated.contains(upper)) updated.add(upper);
        rooms[i] = rooms[i].copyWith(stripMacs: updated);
      }
    }
    await saveRooms();
  }

  Future<void> setRoomIcon(String id, String icon) async {
    final i = rooms.indexWhere((r) => r.id == id);
    if (i >= 0) {
      rooms[i] = rooms[i].copyWith(icon: icon);
      await saveRooms();
      notifyListeners();
    }
  }

  String outletIcon(String mac, int n) => _prefs?.getString('outlet_icon_${mac.toUpperCase()}_$n') ?? '';
  Future<void> setOutletIcon(String mac, int n, String icon) async {
    await _prefs?.setString('outlet_icon_${mac.toUpperCase()}_$n', icon);
    notifyListeners();
  }

  String stripIcon(String mac) => _prefs?.getString('strip_icon_${mac.toUpperCase()}') ?? '';
  Future<void> setStripIcon(String mac, String icon) async {
    await _prefs?.setString('strip_icon_${mac.toUpperCase()}', icon);
    notifyListeners();
  }

  void updateWidgetThrottled() {
    if (kIsWeb) return; // the home-screen widget is Android-only
    final now = DateTime.now();
    if (_lastWidgetUpdate != null && now.difference(_lastWidgetUpdate!) < const Duration(seconds: 15)) {
      if (_widgetThrottleTimer == null || !_widgetThrottleTimer!.isActive) {
        final remaining = const Duration(seconds: 15) - now.difference(_lastWidgetUpdate!);
        _widgetThrottleTimer = Timer(remaining, _updateWidget);
      }
      return;
    }
    _updateWidget();
  }

  // 2.0.25: the home-screen widgets (main "أ" with graph + per-strip "شكل المشترك") are drawn natively from one JSON
  final List<double> _wHist = [];
  DateTime? _wEnergyAt;
  double _wTodayKwh = 0;

  String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  Future<void> _updateWidget() async {
    _widgetThrottleTimer?.cancel();
    _lastWidgetUpdate = DateTime.now();
    try {
      _wHist.add(totalPower);
      if (_wHist.length > 48) _wHist.removeAt(0);
      if (mode != ConnMode.offline && _strips.isNotEmpty && (_wEnergyAt == null || DateTime.now().difference(_wEnergyAt!) > const Duration(minutes: 10))) {
        _wEnergyAt = DateTime.now();
        try {
          final en = await loadEnergy();
          _wTodayKwh = en.fold<double>(0, (a, e) => a + e.todayWh.fold<int>(0, (x, y) => x + y) / 1000);
        } catch (_) {}
      }
      final ar = Tr.isAr;
      const hues = [162.0, 222.0, 36.0, 300.0, 100.0, 0.0];
      final strips = <Map<String, dynamic>>[];
      for (var i = 0; i < _strips.length; i++) {
        final st = _strips[i];
        final h = hues[i % hues.length];
        strips.add({
          'mac': st.mac,
          'name': stripName(st),
          'on': st.online,
          'w': st.livePower.round(),
          't': st.maxTemp,
          'c': _hex(HSLColor.fromAHSL(1, h, .85, .6).toColor()),
          ...stripWidgetJson(this, st),
        });
      }
      final conn = switch (mode) {
        ConnMode.local => t('mode_local'),
        ConnMode.cloud => t('mode_cloud'),
        ConnMode.offline => t('mode_offline'),
      };
      final j = {
        'ar': ar,
        'mode': conn,
        'total': totalPower.round(),
        'hot': maxTemp,
        'hist': [for (final v in _wHist) v.round()],
        'kwh': _wTodayKwh,
        'cost': _wTodayKwh * tariff,
        'on': '$onCount/$outletCount',
        'strips': strips,
        'url': mode == ConnMode.local && settings.hasLocal ? _localUri('/api/onoff').toString() : '',
        'hdr': _localHeaders,
        'l_now': ar ? 'الاستهلاك دلوقتي' : 'Power now',
        'l_today': ar ? 'النهارده' : 'Today',
        'l_cost': ar ? 'تكلفة' : 'Cost',
        'l_run': ar ? 'شغال' : 'On',
        'l_total': ar ? 'الإجمالي' : 'Total',
        'l_none': ar ? 'افتح فيشة وسجّل الدخول' : 'Open Fisha and sign in',
        't_lock': ar ? 'ده محتاج تأكيد، افتح التطبيق' : 'This needs a confirmation, open the app',
        't_away': ar ? 'التحكم من الويدجت على شبكة البيت بس' : 'Widget control works on the home network only',
        't_fail': ar ? 'الأمر ماوصلش' : 'The command did not go through',
      };
      await HomeWidget.saveWidgetData<String>('widget_json', jsonEncode(j));
      await HomeWidget.updateWidget(
        name: 'FishaWidgetProvider',
        androidName: 'FishaWidgetProvider',
        qualifiedAndroidName: 'com.mttlhub.mttl_hub.FishaWidgetProvider',
      );
    } catch (_) {}
  }
}
