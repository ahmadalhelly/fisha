/// Data models matching the hub's JSON (GET /api/state, SSE "state", `mttl/<hub>/state`).
int _i(Object? v, [int d = 0]) => (v as num?)?.toInt() ?? d;
double _d(Object? v, [double d = 0]) => (v as num?)?.toDouble() ?? d;
String _s(Object? v) => (v ?? '').toString();

class Outlet {
  final int n;
  final bool on;
  final double powerW;
  final double energyKwh;
  final int tempC;
  final String label;
  final bool locked;
  final bool protected;
  final bool keepOn;
  final int autoOffMin;
  final int autoOffInS; // -1 = not running
  final bool hasSchedule; // an enabled schedule targets this outlet (or the whole strip)
  final bool hasRule; // an enabled watts/temperature rule watches it
  final double ampLimit; // per-outlet current limit (0 = disabled)

  const Outlet({
    required this.n,
    required this.on,
    required this.powerW,
    required this.energyKwh,
    required this.tempC,
    this.label = '',
    this.locked = false,
    this.protected = false,
    this.keepOn = false,
    this.autoOffMin = 0,
    this.autoOffInS = -1,
    this.hasSchedule = false,
    this.hasRule = false,
    this.ampLimit = 0.0,
  });

  factory Outlet.fromJson(Map<String, dynamic> j) => Outlet(
        n: _i(j['n']),
        on: j['on'] == true,
        powerW: _d(j['power_w']),
        energyKwh: _d(j['energy_kwh']),
        tempC: _i(j['temp_c']),
        label: _s(j['label']),
        locked: j['locked'] == true,
        protected: j['protected'] == true,
        keepOn: j['keep_on'] == true,
        autoOffMin: _i(j['auto_off_min']),
        autoOffInS: _i(j['auto_off_in_s'], -1),
        hasSchedule: j['sched'] == true,
        hasRule: j['rule'] == true,
        ampLimit: _d(j['amp_limit'], 0.0),
      );

  Outlet copyWith({bool? on, String? label, bool? locked, bool? protected, bool? keepOn, int? autoOffMin, double? ampLimit}) => Outlet(
        n: n,
        on: on ?? this.on,
        powerW: powerW,
        energyKwh: energyKwh,
        tempC: tempC,
        label: label ?? this.label,
        locked: locked ?? this.locked,
        protected: protected ?? this.protected,
        keepOn: keepOn ?? this.keepOn,
        autoOffMin: autoOffMin ?? this.autoOffMin,
        autoOffInS: autoOffInS,
        hasSchedule: hasSchedule,
        hasRule: hasRule,
        ampLimit: ampLimit ?? this.ampLimit,
      );

  // hub 2.15.38 "live": only the numbers that change with every strip report
  Outlet withLive({required bool on, required double powerW, required double energyKwh, required int tempC, required int autoOffInS}) => Outlet(
        n: n,
        on: on,
        powerW: powerW,
        energyKwh: energyKwh,
        tempC: tempC,
        label: label,
        locked: locked,
        protected: protected,
        keepOn: keepOn,
        autoOffMin: autoOffMin,
        autoOffInS: autoOffInS,
        hasSchedule: hasSchedule,
        hasRule: hasRule,
        ampLimit: ampLimit,
      );
}

class Strip {
  final String mac;
  final String fw;
  final bool online;
  final double? voltage;
  final int? rssi;
  final int? upS;
  final String ip;
  final String label;
  final List<Outlet> outlets;
  final int notifyMask; // bit 0-3 outlets, bit 4 strip-level events
  final bool hasSchedule; // whole-strip schedule
  final bool hasRule; // whole-strip rule
  final bool masterLock; // child lock on the strip's own physical master button (strip fw F1.0.82)

  const Strip({
    required this.mac,
    required this.fw,
    required this.online,
    required this.voltage,
    required this.rssi,
    this.upS,
    this.ip = '',
    required this.outlets,
    this.label = '',
    this.notifyMask = 0x1F,
    this.hasSchedule = false,
    this.hasRule = false,
    this.masterLock = false,
  });

  factory Strip.fromJson(Map<String, dynamic> j) {
    final raw = j['outlets'];
    final outs = <Outlet>[];
    if (raw is List) {
      for (final o in raw) {
        if (o is Map<String, dynamic>) outs.add(Outlet.fromJson(o));
      }
    }
    outs.sort((a, b) => a.n.compareTo(b.n));
    return Strip(
      mac: _s(j['mac']).toUpperCase(),
      fw: _s(j['fw']),
      online: j['online'] == true,
      voltage: (j['voltage'] as num?)?.toDouble(),
      rssi: (j['rssi'] as num?)?.toInt(),
      upS: (j['up_s'] as num?)?.toInt(),
      ip: _s(j['ip']),
      label: _s(j['label']),
      outlets: outs,
      notifyMask: _i(j['notify'], 0x1F),
      hasSchedule: j['sched'] == true,
      hasRule: j['rule'] == true,
      masterLock: j['mlock'] == true,
    );
  }

  int get onCount => outlets.where((o) => o.on).length;
  int get lockedCount => outlets.where((o) => o.locked).length;
  int get maxTemp => outlets.isEmpty ? 0 : outlets.map((o) => o.tempC).reduce((a, b) => a > b ? a : b);
  double get livePower => outlets.fold(0.0, (sum, o) => sum + (o.on ? o.powerW : 0));
  bool get anyProtectedOn => outlets.any((o) => o.protected && o.on);

  Strip _with({List<Outlet>? outlets, String? label, bool? masterLock}) => Strip(
        mac: mac,
        fw: fw,
        online: online,
        voltage: voltage,
        rssi: rssi,
        upS: upS,
        ip: ip,
        label: label ?? this.label,
        outlets: outlets ?? this.outlets,
        notifyMask: notifyMask,
        hasSchedule: hasSchedule,
        hasRule: hasRule,
        masterLock: masterLock ?? this.masterLock,
      );

  Strip withOutlets(int n, bool on) =>
      _with(outlets: outlets.map((o) => (n == 0 || o.n == n) ? o.copyWith(on: on) : o).toList());

  Strip withOutletState(Map<int, bool> overrides) =>
      _with(outlets: outlets.map((o) => overrides.containsKey(o.n) ? o.copyWith(on: overrides[o.n]) : o).toList());

  Strip withMasterLock(bool v) => _with(masterLock: v);

  // hub 2.15.38 "live" event: {"mac","v","r","up","o":[[on,W,kWh,°C,auto_off_in_s] x4]}; names, locks etc. stay as they are
  Strip withLive(Map<String, dynamic> j) {
    final o = j['o'];
    final outs = <Outlet>[];
    for (final x in outlets) {
      final i = x.n - 1;
      final v = o is List && i >= 0 && i < o.length ? o[i] : null;
      if (v is List && v.length >= 5) {
        outs.add(x.withLive(
            on: v[0] == 1 || v[0] == true, powerW: _d(v[1]), energyKwh: _d(v[2]), tempC: _i(v[3]), autoOffInS: _i(v[4], -1)));
      } else {
        outs.add(x);
      }
    }
    return Strip(
      mac: mac,
      fw: fw,
      online: online,
      voltage: (j['v'] as num?)?.toDouble(),
      rssi: (j['r'] as num?)?.toInt(),
      upS: (j['up'] as num?)?.toInt() ?? upS,
      ip: ip,
      label: label,
      outlets: outs,
      notifyMask: notifyMask,
      hasSchedule: hasSchedule,
      hasRule: hasRule,
      masterLock: masterLock,
    );
  }

  Strip withLabel(int n, String value) =>
      n == 0 ? _with(label: value) : _with(outlets: outlets.map((o) => o.n == n ? o.copyWith(label: value) : o).toList());

  Strip withOutlet(int n, Outlet Function(Outlet) f) => _with(outlets: outlets.map((o) => o.n == n ? f(o) : o).toList());
}

class HubTimer {
  final int tid;
  final String mac;
  final int outlet;
  final String kind; // on | off | cycle | loop
  final int phase;
  final int inS;
  final int offS;
  final int onS;
  final int repeatS; // 0 = once
  const HubTimer({required this.tid, required this.mac, required this.outlet, required this.kind, required this.phase, required this.inS, required this.offS, this.onS = 0, this.repeatS = 0});
  bool get repeating => kind == 'loop' || repeatS > 0;
  factory HubTimer.fromJson(Map<String, dynamic> j) => HubTimer(
        tid: _i(j['tid']),
        mac: _s(j['mac']).toUpperCase(),
        outlet: _i(j['outlet']),
        kind: _s(j['kind']),
        phase: _i(j['phase']),
        inS: _i(j['in_s']),
        offS: _i(j['off_s']),
        onS: _i(j['on_s']),
        repeatS: _i(j['repeat_s']),
      );
}

class Schedule {
  int sid;
  String mac;
  int outlet; // 0 = whole strip
  bool on;
  int days; // bit 0 = Sunday … bit 6 = Saturday; 0 = one-time
  int hh;
  int mm;
  int date; // yyyymmdd for one-time
  bool enabled;
  String label;
  bool skip; // hub 2.15+: the next run is skipped once (set with schedule_skip, not saved through schedule_save)
  Schedule({this.sid = 0, required this.mac, this.outlet = 1, this.on = true, this.days = 0x3E, this.hh = 8, this.mm = 0, this.date = 0, this.enabled = true, this.label = '', this.skip = false});
  factory Schedule.fromJson(Map<String, dynamic> j) => Schedule(
        sid: _i(j['sid']),
        mac: _s(j['mac']).toUpperCase(),
        outlet: _i(j['outlet']),
        on: j['on'] == true,
        days: _i(j['days']),
        hh: _i(j['hh']),
        mm: _i(j['mm']),
        date: _i(j['date']),
        enabled: j['enabled'] == true,
        label: _s(j['label']),
        skip: j['skip'] == true,
      );
  Map<String, dynamic> toJson() => {
        'sid': sid,
        'mac': mac,
        'outlet': outlet,
        'on': on,
        'days': days,
        'hh': hh,
        'mm': mm,
        'date': date,
        'enabled': enabled,
        'label': label,
      };
}

class Automation {
  int aid;
  String mac;
  int outlet;
  bool above;
  double watts;
  int holdS;
  int act; // 1 notify, 2 off, 3 both
  bool enabled;
  String label;
  int metric; // 0 = power (W), 1 = temperature (°C), 2 = either, 3 = current (A); outlet 0 = whole strip
  double limit2; // °C limit when metric == 2
  Automation({this.aid = 0, required this.mac, this.outlet = 1, this.above = false, this.watts = 5, this.holdS = 600, this.act = 1, this.enabled = true, this.label = '', this.metric = 0, this.limit2 = 70});
  bool get isTemp => metric == 1;
  bool get isBoth => metric == 2;
  bool get isCurrent => metric == 3;
  factory Automation.fromJson(Map<String, dynamic> j) => Automation(
        aid: _i(j['aid']),
        mac: _s(j['mac']).toUpperCase(),
        outlet: _i(j['outlet'], 1),
        above: j['above'] == true,
        watts: _d(j['watts']),
        holdS: _i(j['hold_s'], 600),
        act: _i(j['act'], 1),
        enabled: j['enabled'] == true,
        label: _s(j['label']),
        metric: _i(j['metric']),
        limit2: _d(j['limit2'], 70),
      );
  Map<String, dynamic> toJson() => {
        'metric': metric,
        'limit2': limit2,
        'aid': aid,
        'mac': mac,
        'outlet': outlet,
        'above': above,
        'watts': watts,
        'hold_s': holdS,
        'act': act,
        'enabled': enabled,
        'label': label,
      };
}

class HubEvent {
  final int ts;
  final String type;
  final String mac;
  final int outlet;
  final String msg;
  const HubEvent({required this.ts, required this.type, required this.mac, required this.outlet, required this.msg});
  factory HubEvent.fromJson(Map<String, dynamic> j) =>
      HubEvent(ts: _i(j['ts']), type: _s(j['type']), mac: _s(j['mac']).toUpperCase(), outlet: _i(j['outlet']), msg: _s(j['msg']));
  String get key => '$ts|$type|$mac|$outlet|$msg';
}

class EnergyDay {
  final int date; // yyyymmdd
  final List<int> wh; // per outlet
  final int peakW; // -1 = unknown
  const EnergyDay(this.date, this.wh, [this.peakW = -1]);
  int get total => wh.fold(0, (a, b) => a + b);
}

class EnergyData {
  final String mac;
  final int today;
  final List<int> todayWh;
  final List<EnergyDay> days; // newest first, excludes today
  final bool timeOk;
  final int todayPeakW; // -1 = unknown
  const EnergyData({
    required this.mac,
    required this.today,
    required this.todayWh,
    required this.days,
    required this.timeOk,
    this.todayPeakW = -1,
  });
  factory EnergyData.fromJson(Map<String, dynamic> j) {
    List<int> ints(Object? v) => v is List ? v.map((e) => (e as num).toInt()).toList() : <int>[0, 0, 0, 0];
    final days = <EnergyDay>[];
    final raw = j['days'];
    if (raw is List) {
      for (final d in raw) {
        if (d is Map<String, dynamic>) days.add(EnergyDay(_i(d['date']), ints(d['wh']), _i(d['peak_w'], -1)));
      }
    }
    return EnergyData(
      mac: _s(j['mac']).toUpperCase(),
      today: _i(j['today']),
      todayWh: ints(j['today_wh']),
      days: days,
      timeOk: j['time_ok'] == true,
      todayPeakW: _i(j['today_peak_w'], -1),
    );
  }
}

class Room {
  final String id;
  final String name;
  final List<String> stripMacs;
  final String icon;
  const Room({required this.id, required this.name, this.stripMacs = const [], this.icon = ''});

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'strips': stripMacs,
        'icon': icon,
      };

  factory Room.fromJson(Map<String, dynamic> j) => Room(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        stripMacs: (j['strips'] as List?)?.map((e) => e.toString().toUpperCase()).toList() ?? const [],
        icon: (j['icon'] ?? '').toString(),
      );

  Room copyWith({String? id, String? name, List<String>? stripMacs, String? icon}) => Room(
        id: id ?? this.id,
        name: name ?? this.name,
        stripMacs: stripMacs ?? this.stripMacs,
        icon: icon ?? this.icon,
      );
}

/// Extra permissions the owner can give a member on top of the role (admins and the owner have them all).
class Perm {
  static const auto = 1, prot = 2, stripFw = 4, wifi = 8, hubFw = 16, export = 32;
}

/// A person the owner shared the hub with (hub 2.9+). role 0 view · 1 control · 2 admin.
class HubUser {
  final String id;
  String name;
  int role;
  int perms; // extra permissions the owner granted on top of the role, see [Perm] (hub 2.15.26+)
  final String email; // the member's Google email and photo link (hub 2.15.26+)
  final String photo;
  bool all;
  List<String> strips;
  HubUser({required this.id, this.name = '', this.role = 1, this.perms = 0, this.email = '', this.photo = '', this.all = true, List<String>? strips})
      : strips = strips ?? [];
  factory HubUser.fromJson(Map<String, dynamic> j) => HubUser(
        id: _s(j['id']),
        name: _s(j['name']),
        role: _i(j['role'], 1),
        perms: _i(j['perms'], 0),
        email: _s(j['email']),
        photo: _s(j['photo']),
        all: j['all'] == true,
        strips: j['strips'] is List ? (j['strips'] as List).map((e) => e.toString().toUpperCase()).toList() : [],
      );
}
