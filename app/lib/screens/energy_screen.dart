import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

class EnergyScreen extends StatefulWidget {
  final AppState state;
  const EnergyScreen({super.key, required this.state});

  @override
  State<EnergyScreen> createState() => _EnergyScreenState();
}

class _Row {
  final String name;
  final int wh;
  _Row(this.name, this.wh);
}

class _EnergyScreenState extends State<EnergyScreen> {
  AppState get s => widget.state;
  int _range = 7;
  bool _loading = false;
  List<EnergyData> _data = [];
  int _lastTab = -1;

  Future<void> _load() async {
    if (!s.hubV2) return;
    setState(() => _loading = true);
    final d = await s.loadEnergy();
    if (!mounted) return;
    setState(() {
      _data = d;
      _loading = false;
    });
  }

  // date (yyyymmdd) -> total Wh, newest first, including today
  List<MapEntry<int, int>> _daily() {
    final map = <int, int>{};
    for (final e in _data) {
      if (e.today > 0) map[e.today] = (map[e.today] ?? 0) + e.todayWh.fold(0, (a, b) => a + b);
      for (final d in e.days) {
        map[d.date] = (map[d.date] ?? 0) + d.total;
      }
    }
    final keys = map.keys.toList()..sort((a, b) => b.compareTo(a));
    return [for (final k in keys.take(_range)) MapEntry(k, map[k]!)];
  }

  List<_Row> _byOutlet() {
    final rows = <_Row>[];
    for (final e in _data) {
      final strip = s.live(e.mac);
      final per = List<int>.filled(4, 0);
      for (var k = 0; k < 4 && k < e.todayWh.length; k++) {
        per[k] += e.todayWh[k];
      }
      for (final d in e.days.take(_range - 1)) {
        for (var k = 0; k < 4 && k < d.wh.length; k++) {
          per[k] += d.wh[k];
        }
      }
      for (var k = 0; k < 4; k++) {
        final name = strip == null ? t('default_outlet', {'n': k + 1}) : '${s.stripName(strip)} · ${s.outletName(strip, k + 1)}';
        rows.add(_Row(name, per[k]));
      }
    }
    rows.sort((a, b) => b.wh.compareTo(a.wh));
    return rows;
  }

  Future<void> _editTariff() async {
    final ctrl = TextEditingController(text: s.tariff.toStringAsFixed(2));
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        title: Text(t('tariff'), style: const TextStyle(fontSize: 18)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(t('tariff_hint'), style: TextStyle(color: C.muted, fontSize: 13)),
          const SizedBox(height: 10),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(suffixText: '${t('egp')}/kWh'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'), style: TextStyle(color: C.muted))),
          TextButton(onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text.trim())), child: Text(t('save'))),
        ],
      ),
    );
    if (v != null && v >= 0) s.setTariff(v);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        if (s.tab == 2 && _lastTab != 2) WidgetsBinding.instance.addPostFrameCallback((_) => _load());
        _lastTab = s.tab;
        final daily = _daily();
        final totalWh = daily.fold<int>(0, (a, e) => a + e.value);
        final kwh = totalWh / 1000;
        return SafeArea(
          child: RefreshIndicator(
            color: C.accent,
            onRefresh: _load,
            child: ListView(padding: const EdgeInsets.fromLTRB(18, 20, 18, 24), children: [
              Text(t('energy_title'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              if (!s.hubV2)
                emptyCard(t('energy_old_fw'))
              else ...[
                Segmented<int>(
                  value: _range,
                  items: {7: t('range_days', {'n': 7}), 30: t('range_days', {'n': 30}), 90: t('range_days', {'n': 90})},
                  onChanged: (v) => setState(() => _range = v),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _bigStat(t('total_used'), kwh.toStringAsFixed(2), 'kWh')),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: _editTariff,
                      child: _bigStat(t('est_cost'), (kwh * s.tariff).toStringAsFixed(2), t('egp'),
                          foot: '${t('tariff')}: ${s.tariff.toStringAsFixed(2)} ✎'),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                if (_loading && _data.isEmpty) Center(child: Padding(padding: const EdgeInsets.all(24), child: CircularProgressIndicator(color: C.accent))),
                if (!_loading && daily.isEmpty) emptyCard(t('energy_empty'), icon: Icons.bar_chart),
                if (daily.isNotEmpty) ...[
                  section(t('daily_usage'), [SizedBox(height: 180, child: _Bars(daily: daily.reversed.toList()))]),
                  const SizedBox(height: 14),
                  section(t('by_outlet'), [for (final r in _byOutlet().where((r) => r.wh > 0)) _outletRow(r, totalWh)]),
                ],
              ],
            ]),
          ),
        );
      },
    );
  }

  Widget _bigStat(String label, String value, String unit, {String? foot}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: cardBox(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: C.muted, fontSize: 13)),
          const SizedBox(height: 6),
          Row(textDirection: TextDirection.ltr, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Flexible(child: Text(value, overflow: TextOverflow.ellipsis, style: mono(26, color: C.accent))),
            const SizedBox(width: 4),
            Text(unit, style: TextStyle(color: C.muted, fontSize: 12)),
          ]),
          if (foot != null) ...[const SizedBox(height: 4), Text(foot, style: TextStyle(color: C.muted, fontSize: 11))],
        ]),
      );

  Widget _outletRow(_Row r, int total) {
    final share = total == 0 ? 0.0 : r.wh / total;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
        Text('${(r.wh / 1000).toStringAsFixed(2)} kWh', textDirection: TextDirection.ltr, style: mono(12, color: C.textSoft)),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: share.clamp(0.0, 1.0), minHeight: 8, color: C.accent, backgroundColor: C.surface2),
      ),
    ]);
  }
}

class _Bars extends StatelessWidget {
  final List<MapEntry<int, int>> daily; // oldest first
  const _Bars({required this.daily});

  @override
  Widget build(BuildContext context) {
    final maxWh = daily.fold<int>(1, (a, e) => math.max(a, e.value));
    final gap = daily.length > 40 ? 1.0 : 4.0;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(children: [
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final e in daily)
              Expanded(
                child: Tooltip(
                  message: '${e.key % 100}/${(e.key ~/ 100) % 100}: ${(e.value / 1000).toStringAsFixed(2)} kWh',
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: gap / 2),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: e.value / maxWh),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutCubic,
                      builder: (_, v, __) => FractionallySizedBox(
                        heightFactor: math.max(0.02, v),
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          decoration: BoxDecoration(
                            color: e == daily.last ? C.accent : C.accent.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Text(_d(daily.first.key), style: TextStyle(fontSize: 11, color: C.muted)),
          const Spacer(),
          Text(t('today'), style: TextStyle(fontSize: 11, color: C.muted)),
        ]),
      ]),
    );
  }

  String _d(int k) => '${k % 100}/${(k ~/ 100) % 100}';
}
