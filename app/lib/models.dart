/// Data models matching the hub's JSON (GET /api/state and mttl/<hub>/state).
class Outlet {
  final int n;
  final bool on;
  final double powerW;
  final double energyKwh;
  final int tempC;

  const Outlet({
    required this.n,
    required this.on,
    required this.powerW,
    required this.energyKwh,
    required this.tempC,
  });

  factory Outlet.fromJson(Map<String, dynamic> j) => Outlet(
        n: (j['n'] as num?)?.toInt() ?? 0,
        on: j['on'] == true,
        powerW: (j['power_w'] as num?)?.toDouble() ?? 0,
        energyKwh: (j['energy_kwh'] as num?)?.toDouble() ?? 0,
        tempC: (j['temp_c'] as num?)?.toInt() ?? 0,
      );

  Outlet copyWith({bool? on}) => Outlet(
        n: n,
        on: on ?? this.on,
        powerW: powerW,
        energyKwh: energyKwh,
        tempC: tempC,
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
      outlets: outs,
    );
  }

  int get onCount => outlets.where((o) => o.on).length;
  bool get anyOn => outlets.any((o) => o.on);
  int get maxTemp => outlets.isEmpty ? 0 : outlets.map((o) => o.tempC).reduce((a, b) => a > b ? a : b);
  double get livePower => outlets.fold(0.0, (sum, o) => sum + (o.on ? o.powerW : 0));

  /// A copy with outlet [n] (or all when n == 0) switched to [on] — used for optimistic UI.
  Strip withOutlets(int n, bool on) => Strip(
        mac: mac,
        fw: fw,
        online: online,
        powerW: powerW,
        energyKwh: energyKwh,
        voltage: voltage,
        rssi: rssi,
        outlets: outlets.map((o) => (n == 0 || o.n == n) ? o.copyWith(on: on) : o).toList(),
      );

  Strip withOutletState(Map<int, bool> overrides) => Strip(
        mac: mac,
        fw: fw,
        online: online,
        powerW: powerW,
        energyKwh: energyKwh,
        voltage: voltage,
        rssi: rssi,
        outlets: outlets.map((o) => overrides.containsKey(o.n) ? o.copyWith(on: overrides[o.n]) : o).toList(),
      );
}
