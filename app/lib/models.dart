/// Data models matching the hub's JSON (GET /api/state, SSE "state", mttl/<hub>/state).
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
  final int autoOffMin;
  final int autoOffInS; // -1 = not running
  final bool hasSchedule; // an enabled schedule targets this outlet (or the whole strip)
  final bool hasRule; // an enabled watts/temperature rule watches it

  const Outlet({
    required this.n,
    required this.on,
    required this.powerW,
    required this.energyKwh,
    required this.tempC,
    this.label = '',
    this.locked = false,
    this.protected = false,
    this.autoOffMin = 0,
    this.autoOffInS = -1,
    this.hasSchedule = false,
    this.hasRule = false,
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
        autoOffMin: _i(j['auto_off_min']),
        autoOffInS: _i(j['auto_off_in_s'], -1),
        hasSchedule: j['sched'] == true,
        hasRule: j['rule'] == true,
      );

  Outlet copyWith({bool? on, String? label, bool? locked, bool? protected, int? autoOffMin}) => Outlet(
        n: n,
        on: on ?? this.on,
        powerW: powerW,
        energyKwh: energyKwh,
        tempC: tempC,
        label: label ?? this.label,
        locked: locked ?? this.locked,
        protected: protected ?? this.protected,
        autoOffMin: autoOffMin ?? this.autoOffMin,
        autoOffInS: autoOffInS,
        hasSchedule: hasSchedule,
        hasRule: hasRule,
      );
}

class Strip {
  final String mac;
  final String fw;
  final bool online;
  final double? voltage;
  final int? rssi;
  final String label;
  final List<Outlet> outlets;
  final int notifyMask; // bit 0-3 outlets, bit 4 strip-level events
  final bool hasSchedule; // whole-strip schedule
  final bool hasRule; // whole-strip rule

  const Strip({
    required this.mac,
    required this.fw,
    required this.online,
    required this.voltage,
    required this.rssi,
    required this.outlets,
    this.label = '',
    this.notifyMask = 0x1F,
    this.hasSchedule = false,
    this.hasRule = false,
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
      label: _s(j['label']),
      outlets: outs,
      notifyMask: _i(j['notify'], 0x1F),
      hasSchedule: j['sched'] == true,
      hasRule: j['rule'] == true,
    );
  }

  int get onCount => outlets.where((o) => o.on).length;
  int get lockedCount => outlets.where((o) => o.locked).length;
  int get maxTemp => outlets.isEmpty ? 0 : outlets.map((o) => o.tempC).reduce((a, b) => a > b ? a : b);
  double get livePower => outlets.fold(0.0, (sum, o) => sum + (o.on ? o.powerW : 0));
  bool get anyProtectedOn => outlets.any((o) => o.protected && o.on);

  Strip _with({List<Outlet>? outlets, String? label}) => Strip(
        mac: mac,
        fw: fw,
        online: online,
        voltage: voltage,
        rssi: rssi,
        label: label ?? this.label,
        outlets: outlets ?? this.outlets,
        notifyMask: notifyMask,
        hasSchedule: hasSchedule,
        hasRule: hasRule,
      );

  Strip withOutlets(int n, bool on) =>
      _with(outlets: outlets.map((o) => (n == 0 || o.n == n) ? o.copyWith(on: on) : o).toList());

  Strip withOutletState(Map<int, bool> overrides) =>
      _with(outlets: outlets.map((o) => overrides.containsKey(o.n) ? o.copyWith(on: overrides[o.n]) : o).toList());

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
  Schedule({this.sid = 0, required this.mac, this.outlet = 1, this.on = true, this.days = 0x3E, this.hh = 8, this.mm = 0, this.date = 0, this.enabled = true, this.label = ''});
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
  int metric; // 0 = power (W), 1 = temperature (°C), 2 = either; outlet 0 = whole strip
  double limit2; // °C limit when metric == 2
  Automation({this.aid = 0, required this.mac, this.outlet = 1, this.above = false, this.watts = 5, this.holdS = 600, this.act = 1, this.enabled = true, this.label = '', this.metric = 0, this.limit2 = 70});
  bool get isTemp => metric == 1;
  bool get isBoth => metric == 2;
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
  const EnergyDay(this.date, this.wh);
  int get total => wh.fold(0, (a, b) => a + b);
}

class EnergyData {
  final String mac;
  final int today;
  final List<int> todayWh;
  final List<EnergyDay> days; // newest first, excludes today
  final bool timeOk;
  const EnergyData({required this.mac, required this.today, required this.todayWh, required this.days, required this.timeOk});
  factory EnergyData.fromJson(Map<String, dynamic> j) {
    List<int> ints(Object? v) => v is List ? v.map((e) => (e as num).toInt()).toList() : <int>[0, 0, 0, 0];
    final days = <EnergyDay>[];
    final raw = j['days'];
    if (raw is List) {
      for (final d in raw) {
        if (d is Map<String, dynamic>) days.add(EnergyDay(_i(d['date']), ints(d['wh'])));
      }
    }
    return EnergyData(mac: _s(j['mac']).toUpperCase(), today: _i(j['today']), todayWh: ints(j['today_wh']), days: days, timeOk: j['time_ok'] == true);
  }
}
