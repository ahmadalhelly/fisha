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

class _DayStat {
  final int date; // yyyymmdd
  final int wh;
  final int peakW; // max peakW across strips (-1 if unknown)
  const _DayStat({required this.date, required this.wh, required this.peakW});
}

class _StripUse {
  final String name;
  final List<_Row> outlets;
  final int peakW;
  _StripUse(this.name, this.outlets, [this.peakW = -1]);
  int get wh => outlets.fold(0, (a, r) => a + r.wh);
}

String _tr(String ar, String en) => Tr.isAr ? ar : en;

class _EnergyScreenState extends State<EnergyScreen> {
  AppState get s => widget.state;
  int _range = 7;
  bool _byName = false; // sort strips by consumption (default) or by name
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

  // date (yyyymmdd) -> _DayStat, newest first, including today
  List<_DayStat> _daily() {
    final whMap = <int, int>{};
    final peakMap = <int, int>{};
    for (final e in _data) {
      if (e.today > 0) {
        whMap[e.today] = (whMap[e.today] ?? 0) + e.todayWh.fold(0, (a, b) => a + b);
        if (e.todayPeakW > 0) {
          peakMap[e.today] = math.max(peakMap[e.today] ?? -1, e.todayPeakW);
        }
      }
      for (final d in e.days) {
        whMap[d.date] = (whMap[d.date] ?? 0) + d.total;
        if (d.peakW > 0) {
          peakMap[d.date] = math.max(peakMap[d.date] ?? -1, d.peakW);
        }
      }
    }
    final keys = whMap.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final k in keys.take(_range))
        _DayStat(date: k, wh: whMap[k]!, peakW: peakMap[k] ?? -1)
    ];
  }

  List<_StripUse> _perStrip() {
    final out = <_StripUse>[];
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
      final rows = [
        for (var k = 0; k < 4; k++) _Row(strip == null ? t('default_outlet', {'n': k + 1}) : s.outletName(strip, k + 1), per[k]),
      ]..sort((a, b) => b.wh.compareTo(a.wh));

      var peak = e.todayPeakW;
      for (final d in e.days.take(_range - 1)) {
        if (d.peakW > peak) peak = d.peakW;
      }
      out.add(_StripUse(strip == null ? e.mac : s.stripName(strip), rows, peak));
    }
    out.sort(_byName ? (a, b) => a.name.compareTo(b.name) : (a, b) => b.wh.compareTo(a.wh));
    return out;
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
        final totalWh = daily.fold<int>(0, (a, e) => a + e.wh);
        final kwh = totalWh / 1000;
        return SafeArea(
          bottom: false,
          child: RefreshIndicator(
            color: C.accent,
            onRefresh: _load,
            child: ListView(padding: EdgeInsets.fromLTRB(18, 20, 18, navInset(context) + 20), children: [
              Text(t('energy_title'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              if (!s.hubV2)
                emptyCard(t('energy_old_fw'))
              else ...[
                Segmented<int>(
                  value: _range,
                  items: {
                    7: _tr('٧ أيام', '7 Days'),
                    14: _tr('أسبوعين', '2 Weeks'),
                    30: _tr('شهر', 'Month'),
                    90: _tr('٩٠ يوم', '90 Days'),
                  },
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
                  section(t('daily_usage'), [SizedBox(height: 190, child: _Bars(daily: daily.reversed.toList(), range: _range))]),
                  const SizedBox(height: 14),
                  section(_tr('استهلاك كل يوم', 'Daily Consumption'), [
                    _dailyList(daily),
                  ]),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(child: Text(_tr('حسب المشترك', 'By strip'), style: TextStyle(fontSize: 13, color: C.muted, fontWeight: FontWeight.w700))),
                    SizedBox(
                      width: 190,
                      child: Segmented<bool>(
                        value: _byName,
                        items: {false: _tr('الأعلى استهلاكًا', 'Most used'), true: _tr('بالاسم', 'By name')},
                        onChanged: (v) => setState(() => _byName = v),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  for (final st in _perStrip()) ...[_stripCard(st, totalWh), const SizedBox(height: 10)],
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

  Widget _stripCard(_StripUse st, int total) {
    final kwh = st.wh / 1000;
    final share = total == 0 ? 0.0 : st.wh / total;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardBox(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(st.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          Text('${kwh.toStringAsFixed(2)} kWh', textDirection: TextDirection.ltr, style: mono(15, color: C.accent)),
        ]),
        const SizedBox(height: 2),
        Row(children: [
          Text('${(share * 100).toStringAsFixed(0)}% ${_tr('من الإجمالي', 'of total')}', style: TextStyle(color: C.muted, fontSize: 12)),
          const Spacer(),
          Text('${(kwh * s.tariff).toStringAsFixed(2)} ${t('egp')}', style: TextStyle(color: C.muted, fontSize: 12)),
        ]),
        if (st.peakW > 0) ...[
          const SizedBox(height: 4),
          Row(children: [
            Text(_tr('أعلى استهلاك: ', 'Peak: '), style: TextStyle(color: C.muted, fontSize: 12)),
            Text('${st.peakW} W', textDirection: TextDirection.ltr, style: mono(12, color: C.textSoft)),
          ]),
        ],
        const SizedBox(height: 12),
        for (final r in st.outlets) Padding(padding: const EdgeInsets.only(bottom: 10), child: _outletRow(r, st.wh)),
      ]),
    );
  }

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

  Widget _dailyList(List<_DayStat> daily) {
    if (daily.isEmpty) return const SizedBox.shrink();
    final maxWh = daily.fold<int>(1, (a, e) => math.max(a, e.wh));
    return Column(
      children: [
        for (final d in daily) _dailyRow(d, maxWh),
      ],
    );
  }

  Widget _dailyRow(_DayStat d, int maxWh) {
    final kwh = d.wh / 1000;
    final cost = kwh * s.tariff;
    final ratio = maxWh > 0 ? (d.wh / maxWh).clamp(0.0, 1.0) : 0.0;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: C.border.withValues(alpha: 0.5)))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(_formatDate(d.date), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
              const Spacer(),
              Text('${kwh.toStringAsFixed(2)} kWh', textDirection: TextDirection.ltr, style: mono(13.5, color: C.accent, weight: FontWeight.w600)),
              const SizedBox(width: 10),
              Text('${cost.toStringAsFixed(2)} ${t('egp')}', style: TextStyle(fontSize: 12, color: C.muted)),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 6,
                    backgroundColor: C.surface2,
                    color: C.accent,
                  ),
                ),
              ),
              if (d.peakW > 0) ...[
                const SizedBox(width: 12),
                Text('⚡ ${d.peakW} W', textDirection: TextDirection.ltr, style: mono(11, color: C.textSoft)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(int k) {
    final y = k ~/ 10000;
    final m = (k ~/ 100) % 100;
    final d = k % 100;
    final now = DateTime.now();
    final todayK = now.year * 10000 + now.month * 100 + now.day;
    if (k == todayK) return _tr('اليوم', 'Today');
    final yest = now.subtract(const Duration(days: 1));
    final yestK = yest.year * 10000 + yest.month * 100 + yest.day;
    if (k == yestK) return _tr('أمس', 'Yesterday');
    return '$d/$m/$y';
  }
}

class _Bars extends StatefulWidget {
  final List<_DayStat> daily; // oldest first
  final int range;
  const _Bars({required this.daily, required this.range});

  @override
  State<_Bars> createState() => _BarsState();
}

class _BarsState extends State<_Bars> {
  int? _selectedDate;

  @override
  Widget build(BuildContext context) {
    if (widget.daily.isEmpty) return const SizedBox.shrink();
    final maxWh = widget.daily.fold<int>(1, (a, e) => math.max(a, e.wh));
    final gap = widget.daily.length > 40 ? 1.0 : (widget.daily.length > 10 ? 3.0 : 6.0);

    final selectedDay = widget.daily.firstWhere(
      (e) => e.date == _selectedDate,
      orElse: () => widget.daily.last,
    );

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
            child: Text(
              '${_d(selectedDay.date)} · ${(selectedDay.wh / 1000).toStringAsFixed(2)} kWh${selectedDay.peakW > 0 ? " · ⚡ ${selectedDay.peakW} W" : ""}',
              style: mono(12, color: C.accent),
              textDirection: TextDirection.ltr,
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final h = constraints.maxHeight;
              final showLabels = widget.range == 7;
              final maxBarH = showLabels ? math.max(10.0, h - 18) : math.max(10.0, h);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final e in widget.daily)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          setState(() => _selectedDate = e.date);
                        },
                        child: Tooltip(
                          message: '${_d(e.date)}: ${(e.wh / 1000).toStringAsFixed(2)} kWh${e.peakW > 0 ? " · ${e.peakW} W" : ""}',
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: gap / 2),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (showLabels) ...[
                                  Text(
                                    (e.wh / 1000).toStringAsFixed(1),
                                    style: mono(9, color: (e.date == selectedDay.date && widget.range != 7) ? C.accent : C.muted),
                                    textDirection: TextDirection.ltr,
                                    maxLines: 1,
                                    overflow: TextOverflow.clip,
                                  ),
                                  const SizedBox(height: 2),
                                ],
                                TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0, end: maxWh > 0 ? e.wh / maxWh : 0.0),
                                  duration: const Duration(milliseconds: 600),
                                  curve: Curves.easeOutCubic,
                                  builder: (_, v, __) {
                                    final barH = math.max(4.0, v * maxBarH);
                                    final isSelected = e.date == selectedDay.date;
                                    final isLatest = e == widget.daily.last;
                                    Color barColor;
                                    if (widget.range == 7) {
                                      barColor = isLatest ? C.accent : C.accent.withValues(alpha: 0.55);
                                    } else {
                                      barColor = isSelected ? C.accent : C.accent.withValues(alpha: 0.4);
                                    }
                                    return Container(
                                      height: barH,
                                      decoration: BoxDecoration(
                                        color: barColor,
                                        borderRadius: BorderRadius.circular(widget.daily.length > 40 ? 1 : 4),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Text(_d(widget.daily.first.date), style: TextStyle(fontSize: 11, color: C.muted)),
          const Spacer(),
          Text(t('today'), style: TextStyle(fontSize: 11, color: C.muted)),
        ]),
      ]),
    );
  }

  String _d(int k) => '${k % 100}/${(k ~/ 100) % 100}';
}
