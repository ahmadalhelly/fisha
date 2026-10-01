/// Data models matching the hub's JSON (GET /api/state and mttl/<hub>/state).
class Outlet {
  final int n;
  final bool on;
  final double powerW;
  final double energyKwh;
  final int tempC;
  final String label; // user name stored on the hub ('' = none)
  final bool locked; // child lock

  const Outlet({
    required this.n,
    required this.on,
    required this.powerW,
    required this.energyKwh,
    required this.tempC,
    this.label = '',
    this.locked = false,
  });

  factory Outlet.fromJson(Map<String, dynamic> j) => Outlet(
        n: (j['n'] as num?)?.toInt() ?? 0,
        on: j['on'] == true,
        powerW: (j['power_w'] as num?)?.toDouble() ?? 0,
        energyKwh: (j['energy_kwh'] as num?)?.toDouble() ?? 0,
        tempC: (j['temp_c'] as num?)?.toInt() ?? 0,
        label: (j['label'] ?? '').toString(),
        locked: j['locked'] == true,
      );

  Outlet copyWith({bool? on, String? label, bool? locked}) => Outlet(
        n: n,
        on: on ?? this.on,
        powerW: powerW,
        energyKwh: energyKwh,
        tempC: tempC,
        label: label ?? this.label,
        locked: locked ?? this.locked,
      );
}

class Strip {
  final String mac;
  final String fw;
  final bool online;
  final double powerW;
  final double energyKwh;
  final double? voltage;
  final int? rssi;
  final String label;
  final List<Outlet> outlets;

  const Strip({
    required this.mac,
    required this.fw,
    required this.online,
    required this.powerW,
    required this.energyKwh,
    required this.voltage,
    required this.rssi,
    required this.outlets,
    this.label = '',
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
      mac: (j['mac'] ?? '').toString().toUpperCase(),
      fw: (j['fw'] ?? '').toString(),
      online: j['online'] == true,
      powerW: (j['power_w'] as num?)?.toDouble() ?? 0,
      energyKwh: (j['energy_kwh'] as num?)?.toDouble() ?? 0,
      voltage: (j['voltage'] as num?)?.toDouble(),
      rssi: (j['rssi'] as num?)?.toInt(),
      label: (j['label'] ?? '').toString(),
      outlets: outs,
    );
  }

  int get onCount => outlets.where((o) => o.on).length;
  bool get anyOn => outlets.any((o) => o.on);
  int get lockedCount => outlets.where((o) => o.locked).length;
  int get maxTemp => outlets.isEmpty ? 0 : outlets.map((o) => o.tempC).reduce((a, b) => a > b ? a : b);
  double get livePower => outlets.fold(0.0, (sum, o) => sum + (o.on ? o.powerW : 0));

  Strip _with({List<Outlet>? outlets, String? label}) => Strip(
        mac: mac,
        fw: fw,
        online: online,
        powerW: powerW,
        energyKwh: energyKwh,
        voltage: voltage,
        rssi: rssi,
        label: label ?? this.label,
        outlets: outlets ?? this.outlets,
      );

  /// A copy with outlet [n] (or all when n == 0) switched to [on] — used for optimistic UI.
  Strip withOutlets(int n, bool on) =>
      _with(outlets: outlets.map((o) => (n == 0 || o.n == n) ? o.copyWith(on: on) : o).toList());

  Strip withOutletState(Map<int, bool> overrides) =>
      _with(outlets: outlets.map((o) => overrides.containsKey(o.n) ? o.copyWith(on: overrides[o.n]) : o).toList());

  Strip withLabel(int n, String value) => n == 0
      ? _with(label: value)
      : _with(outlets: outlets.map((o) => o.n == n ? o.copyWith(label: value) : o).toList());

  Strip withLock(int n, bool locked) =>
      _with(outlets: outlets.map((o) => o.n == n ? o.copyWith(locked: locked) : o).toList());
}
