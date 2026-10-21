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

part 'state/account_sync.dart';
part 'state/backup.dart';
part 'state/cloud_link.dart';
part 'state/hub_api.dart';
part 'state/hub_firmware.dart';
part 'state/hub_lock.dart';
part 'state/local_link.dart';
part 'state/mirror_events.dart';
part 'state/notifications.dart';
part 'state/prefs.dart';
part 'state/schedules.dart';
part 'state/settings_link.dart';
part 'state/strip_control.dart';

enum ConnMode { offline, local, cloud }

/// The hub's plain-http LAN API is reachable: always on the phone; on the web only when the page itself is
/// served over http (the launcher page on the hub, `http://<hub>:8080/app`), since an https page blocks it.
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

  int tempMax = 80;

  // whole-strip protections (hub 2.10+ / F1.0.90+)
  bool vProtect = true, vRestore = true, aProtect = true;

  int vMax = 260;

  int vMin = 180;

  double aMax = 16;

  int protHoldS = 3;

  int tzOffsetMin = 120; // Default: Egypt Standard Time (UTC+2 = +120 min)

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

  /// the very first hubs reported 1.x versions without a patch number ("1.0-alpha"). 2.0.29: the public launch
  /// restarts the hub at 1.0.0 (three numbers), which is a current hub.
  bool get hubV2 => hubFw != null && (!hubFw!.startsWith('1.') || RegExp(r'^\d+\.\d+\.\d+$').hasMatch(hubFw!));

  bool get hubHasConfig => hubFw != null && hubFw != '1.0-alpha';

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

  Timer? _syncTimer;

  String _lastSyncSig = '';

  // per-phone keys that must not travel between devices through the Google copy
  static const _noSyncKeys = {'lastSync', 'accountType', 'googleEmail', 'pendingOps', 'notifyFilter'};

  /// 2.0.18: how often the automatic sync uploads (minutes): 0 = whenever something changed (checked every 10 min)
  int syncEveryMin = 0;

  static const syncChoices = [0, 60, 1440, 10080];

  /// 2.0.20: pauses automatic sync without signing out of the Google account (a manual "زامن دلوقتي" still works).
  bool syncPaused = false;

  /// 2.0.20: how many past copies to keep on Drive (the rest are pruned after each upload).
  int syncKeepVersions = 5;

  // secrets a backup file must not carry in plain text (the Google copy lives in the app's private Drive folder)
  static const _secretPrefs = {'otaPass'};

  static const _secretSettings = {'password', 'hubPass', 'ownerKey'};

  @override

  void dispose() {
    _syncTimer?.cancel();
    _widgetThrottleTimer?.cancel();
    _stopAll();
    super.dispose();
  }

  // 2.0.18: when the hub's local data can't be read, the cloud copy is used for a while instead of an empty screen
  DateTime? _localBadAt;

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

  bool _profileSending = false;

  /// Event type per bit of [notifyTypes], same order as the hub and the background service.
  static const notifyBitTypes = ['temp', 'load', 'auto_off', 'automation', 'schedule', 'missed', 'timer', 'cycle', 'lock', 'added', 'test',
      'button', 'remote', 'online', 'offline', 'voltage'];

  /// The hub's own events that have no switch in notification settings; they go to the system log only (2.0.11).
  static bool isSystemEvent(String type) => type != 'test' && !notifyBitTypes.contains(type) && !safetyTypes.contains(type);

  /// Safety cuts (hub 2.15.9+): always sent to the phone, whatever the switches or mutes, so they sit in "My notifications".
  static const safetyTypes = {'overvolt', 'undervolt', 'overcurrent', 'overload', 'trip_fail', 'pair'};

  static const notifyTypeKeys = ['temp', 'load', 'auto_off', 'automation', 'schedule', 'missed', 'timer', 'cycle', 'lock', 'added'];

  /// The background notification service filters with the hub's state from the cloud; when that state is missing it
  /// let everything through. It now falls back to this copy of the user's choices (prefs 'notifyFilter').
  String _notifyFilterSaved = '';

  /// Quick check of an MTTL-W01 .fwr before sending it: 16-byte header with the body length and load address 0x10006000.
  /// The hub checks the checksum too.
  static bool looksLikeStripFw(List<int> b) {
    if (b.length < 65536) return false;
    int u32(int o) => b[o] | b[o + 1] << 8 | b[o + 2] << 16 | b[o + 3] << 24;
    return u32(4) == 0x10006000 && u32(0) + 20 == b.length;
  }

  /// Rule to highlight when its page opens (from an outlet's menu); cleared once shown.
  int focusSid = 0;

  int focusAid = 0;

  // op: {'k': 'schedule'|'automation', 'del': bool, 'id': int (negative = new, not on the hub yet), 'b': body, 'q': queued at}
  List<Map<String, dynamic>> pendingOps = [];

  bool _flushing = false;

  Timer? _flushTimer;

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

  // The hub reports a storage id ('nvs', fw 2.15+) that changes only when its saved data is erased (e.g. a full
  // flash). Then the family members, schedules, rules and names come back from this copy by themselves.
  String _hubNvs = '';

  bool _mirrorBusy = false;

  bool _usersEditedHere = false;

  DateTime? _mirrorAt;

  Timer? _mirrorDebounce;

  // 2.0.25: the home-screen widgets (main "أ" with graph + per-strip "شكل المشترك") are drawn natively from one JSON
  final List<double> _wHist = [];

  DateTime? _wEnergyAt;

  double _wTodayKwh = 0;

  /// Lets the part-file extensions notify (notifyListeners is protected).
  void _notify() => notifyListeners();
}
