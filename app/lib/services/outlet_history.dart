import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

/// One outlet's numbers for one local day, recorded by the app from live state updates.
class OutletDay {
  double wh; // integrated from live watts while the app received state
  int peakW; // highest live watts seen that day
  int peakAt; // epoch seconds of [peakW] (0 = unknown)
  OutletDay([this.wh = 0, this.peakW = 0, this.peakAt = 0]);

  List<num> toJson() => [double.parse(wh.toStringAsFixed(3)), peakW, peakAt];
  factory OutletDay.fromJson(Object? v) {
    if (v is! List || v.length < 3) return OutletDay();
    num n(Object? x) => x is num ? x : 0;
    return OutletDay(n(v[0]).toDouble(), n(v[1]).toInt(), n(v[2]).toInt());
  }
}

/// The hub keeps per-outlet daily Wh but only a per-strip daily peak (no time). This records,
/// on the phone, a per-outlet daily peak (W + when) and an app-side kWh estimate, from the live
/// watts in every state update. Kept for [keepDays] days in shared_preferences.
class OutletHistory {
  OutletHistory._();
  static final OutletHistory instance = OutletHistory._();

  static const _prefKey = 'outletHist1';
  static const keepDays = 90;
  static const _minGap = Duration(seconds: 5); // sample throttle
  static const _maxGap = Duration(minutes: 5); // longer gaps are not integrated (app was away)
  static const _saveEvery = Duration(seconds: 60);

  /// date (yyyymmdd) -> "MAC:n" -> day
  final Map<int, Map<String, OutletDay>> _days = {};
  final Map<String, ({DateTime at, double w})> _last = {};
  DateTime? _lastSample;
  DateTime? _lastSave;
  bool _loaded = false;
  bool _loading = false;

  static String key(String mac, int n) => '${mac.toUpperCase()}:$n';
  static int dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  Future<void> _load() async {
    if (_loaded || _loading) return;
    _loading = true;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_prefKey);
      if (raw != null && raw.isNotEmpty) {
        final j = jsonDecode(raw);
        if (j is Map) {
          j.forEach((dk, v) {
            final d = int.tryParse(dk.toString());
            if (d == null || v is! Map) return;
            final m = _days.putIfAbsent(d, () => {});
            v.forEach((k, e) {
              final old = OutletDay.fromJson(e);
              final cur = m[k.toString()];
              if (cur == null) {
                m[k.toString()] = old;
              } else {
                // samples taken before the load finished are merged into what was stored
                cur.wh += old.wh;
                if (old.peakW > cur.peakW) {
                  cur.peakW = old.peakW;
                  cur.peakAt = old.peakAt;
                }
              }
            });
          });
        }
      }
    } catch (_) {}
    _loaded = true;
    _loading = false;
  }

  /// Called on every live state update; cheap and throttled.
  void sample(List<Strip> strips) {
    if (!_loaded) _load();
    final now = DateTime.now();
    if (_lastSample != null && now.difference(_lastSample!) < _minGap) return;
    _lastSample = now;
    final day = _days.putIfAbsent(dayKey(now), () => {});
    final ts = now.millisecondsSinceEpoch ~/ 1000;
    for (final s in strips) {
      if (!s.online) continue;
      for (final o in s.outlets) {
        final k = key(s.mac, o.n);
        final w = o.on ? math.max(0.0, o.powerW) : 0.0;
        final e = day.putIfAbsent(k, () => OutletDay());
        final prev = _last[k];
        if (prev != null) {
          final dt = now.difference(prev.at);
          if (dt > Duration.zero && dt <= _maxGap) {
            e.wh += (prev.w + w) / 2 * dt.inMilliseconds / 3600000.0;
          }
        }
        _last[k] = (at: now, w: w);
        final wi = w.round();
        if (wi > e.peakW) {
          e.peakW = wi;
          e.peakAt = ts;
        }
      }
    }
    if (_lastSave == null || now.difference(_lastSave!) >= _saveEvery) {
      _lastSave = now;
      _save();
    }
  }

  void _trim() {
    final cut = dayKey(DateTime.now().subtract(const Duration(days: keepDays)));
    _days.removeWhere((d, _) => d <= cut);
  }

  Future<void> _save() async {
    if (!_loaded) return; // never overwrite stored history before it has been read
    _trim();
    try {
      final p = await SharedPreferences.getInstance();
      final j = <String, Object>{
        for (final d in _days.entries) '${d.key}': {for (final e in d.value.entries) e.key: e.value.toJson()},
      };
      await p.setString(_prefKey, jsonEncode(j));
    } catch (_) {}
  }

  /// Days with recorded data, newest first.
  List<int> get dates => _days.keys.toList()..sort((a, b) => b.compareTo(a));

  OutletDay? get(int date, String mac, int n) => _days[date]?[key(mac, n)];

  /// Highest recorded peak of one outlet over the given dates.
  OutletDay? peakOver(Iterable<int> dates, String mac, int n) {
    OutletDay? best;
    for (final d in dates) {
      final e = get(d, mac, n);
      if (e != null && e.peakW > 0 && (best == null || e.peakW > best.peakW)) best = e;
    }
    return best;
  }

  /// App-recorded Wh of one outlet over the given dates.
  double whOver(Iterable<int> dates, String mac, int n) {
    var t = 0.0;
    for (final d in dates) {
      t += get(d, mac, n)?.wh ?? 0;
    }
    return t;
  }
}
