import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../models.dart';
import '../services/outlet_history.dart';
import '../theme.dart';
import '../widgets/common.dart';

class EnergyScreen extends StatefulWidget {
  final AppState state;
  const EnergyScreen({super.key, required this.state});

  @override
  State<EnergyScreen> createState() => _EnergyScreenState();
}

class _Row {
  final String mac;
  final int n; // outlet number 1-4
  final String name;
  final int wh;
  final double liveW; // now, from the live state
  final OutletDay? peak; // app-recorded peak over the period
  _Row(this.mac, this.n, this.name, this.wh, {this.liveW = 0, this.peak});
}

class _DayStat {
  final int date; // yyyymmdd
  final int wh;
  final int peakW; // max peakW across strips (-1 if unknown)
  const _DayStat({required this.date, required this.wh, required this.peakW});
}

class _StripUse {
  final String mac;
  final String name;
  final List<_Row> outlets;
  final int peakW;
  _StripUse(this.mac, this.name, this.outlets, [this.peakW = -1]);
  int get wh => outlets.fold(0, (a, r) => a + r.wh);
}

String _tr(String ar, String en) => Tr.isAr ? ar : en;

class _EnergyScreenState extends State<EnergyScreen> {
  AppState get s => widget.state;
  OutletHistory get _hist => OutletHistory.instance;
  int _range = 7;
  bool _byName = false; // sort strips by consumption (default) or by name
  bool _loading = false;
  List<EnergyData> _data = [];
  int _lastTab = -1;
  String? _mac; // strip filter (null = all strips)
  int _outlet = 0; // outlet filter within [_mac] (0 = all outlets)

  // hub data indexed: mac -> date -> per-outlet Wh / strip peak W
  final Map<String, Map<int, List<int>>> _whIdx = {};
  final Map<String, Map<int, int>> _pkIdx = {};
  List<int> _allDates = []; // newest first

  Future<void> _load() async {
    if (!s.hubV2) return;
    setState(() => _loading = true);
    final d = await s.loadEnergy();
    if (!mounted) return;
    setState(() {
      _data = d;
      _index();
      if (_mac != null && !_whIdx.containsKey(_mac)) {
        _mac = null;
        _outlet = 0;
      }
      _loading = false;
    });
  }

  void _index() {
    _whIdx.clear();
    _pkIdx.clear();
    final dates = <int>{};
    for (final e in _data) {
      final wh = _whIdx.putIfAbsent(e.mac, () => {});
      final pk = _pkIdx.putIfAbsent(e.mac, () => {});
      if (e.today > 0) {
        wh[e.today] = e.todayWh;
        if (e.todayPeakW > 0) pk[e.today] = e.todayPeakW;
        dates.add(e.today);
      }
      for (final d in e.days) {
        wh[d.date] = d.wh;
        if (d.peakW > 0) pk[d.date] = d.peakW;
        dates.add(d.date);
      }
    }
    _allDates = dates.toList()..sort((a, b) => b.compareTo(a));
  }

  /// the dates of the selected period, newest first (same for every filter, so shares add up)
  List<int> get _period => _allDates.take(_range).toList();

  Iterable<String> get _selMacs => _mac == null ? _whIdx.keys : [if (_whIdx.containsKey(_mac)) _mac!];

  int _outletWh(String mac, int date, int k) {
    final l = _whIdx[mac]?[date];
    return l == null || k >= l.length ? 0 : l[k];
  }

  int _stripWh(String mac, Iterable<int> dates) {
    var t = 0;
    for (final d in dates) {
      for (var k = 0; k < 4; k++) {
        t += _outletWh(mac, d, k);
      }
    }
    return t;
  }

  String _stripLabel(String mac) {
    final st = s.live(mac);
    return st == null ? mac : s.stripName(st);
  }

  String _outletLabel(String mac, int n) {
    final st = s.live(mac);
    return st == null ? t('default_outlet', {'n': n}) : s.outletName(st, n);
  }

  double _liveW(String mac, int n) {
    final st = s.live(mac);
    if (st == null || !st.online) return 0;
    for (final o in st.outlets) {
      if (o.n == n) return o.on ? o.powerW : 0;
    }
    return 0;
  }

  // newest first, filtered by strip / outlet
  List<_DayStat> _daily() {
    final out = <_DayStat>[];
    for (final d in _period) {
      var wh = 0;
      var peak = -1;
      for (final mac in _selMacs) {
        if (_outlet == 0) {
          for (var k = 0; k < 4; k++) {
            wh += _outletWh(mac, d, k);
          }
          final p = _pkIdx[mac]?[d];
          if (p != null && p > peak) peak = p;
        } else {
          wh += _outletWh(mac, d, _outlet - 1);
          final p = _hist.get(d, mac, _outlet)?.peakW ?? 0;
          if (p > 0 && p > peak) peak = p;
        }
      }
      out.add(_DayStat(date: d, wh: wh, peakW: peak));
    }
    return out;
  }

  List<_StripUse> _perStrip() {
    final dates = _period;
    final out = <_StripUse>[];
    for (final mac in _selMacs) {
      final rows = <_Row>[];
      for (var k = 0; k < 4; k++) {
        if (_outlet != 0 && _outlet != k + 1) continue;
        var wh = 0;
        for (final d in dates) {
          wh += _outletWh(mac, d, k);
        }
        rows.add(_Row(mac, k + 1, _outletLabel(mac, k + 1), wh, liveW: _liveW(mac, k + 1), peak: _hist.peakOver(dates, mac, k + 1)));
      }
      rows.sort((a, b) => b.wh.compareTo(a.wh));
      var peak = -1;
      for (final d in dates) {
        final p = _pkIdx[mac]?[d];
        if (p != null && p > peak) peak = p;
      }
      out.add(_StripUse(mac, _stripLabel(mac), rows, peak));
    }
    out.sort(_byName ? (a, b) => a.name.compareTo(b.name) : (a, b) => b.wh.compareTo(a.wh));
    return out;
  }

  void _pick(String? mac, [int outlet = 0]) => setState(() {
        _mac = mac;
        _outlet = mac == null ? 0 : outlet;
      });

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
        final strips = _perStrip();
        final totalWh = daily.fold<int>(0, (a, e) => a + e.wh);
        final allWh = _whIdx.keys.fold<int>(0, (a, m) => a + _stripWh(m, _period));
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
                    7: _tr('7 أيام', '7 Days'),
                    14: _tr('أسبوعين', '2 Weeks'),
                    30: _tr('شهر', 'Month'),
                    90: _tr('90 يوم', '90 Days'),
                  },
                  onChanged: (v) => setState(() => _range = v),
                ),
                if (_whIdx.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _filterCard(),
                ],
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                      child: _bigStat(t('total_used'), kwh.toStringAsFixed(2), 'kWh',
                          foot: _mac == null || allWh == 0 ? null : '${(totalWh * 100 / allWh).toStringAsFixed(0)}% ${_tr('من الإجمالي', 'of total')}')),
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
                  _peakCard(daily, strips),
                  const SizedBox(height: 14),
                  section(t('daily_usage'), [SizedBox(height: 190, child: _Bars(daily: daily.reversed.toList(), range: _range))]),
                  const SizedBox(height: 14),
                  section(_tr('استهلاك كل يوم', 'Daily Consumption'), [
                    _dailyList(daily),
                  ]),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                        child: Text(_mac == null ? _tr('حسب المشترك', 'By strip') : _tr('استهلاك كل مخرج', 'By outlet'),
                            style: TextStyle(fontSize: 13, color: C.muted, fontWeight: FontWeight.w700))),
                    if (_mac == null)
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
                  for (final st in strips) ...[_stripCard(st, allWh), const SizedBox(height: 10)],
                ],
              ],
            ]),
          ),
        );
      },
    );
  }

  // ---------- filter: strip, then outlet ----------
  Widget _chip(String label, bool sel, VoidCallback onTap) => ChoiceChip(
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        selected: sel,
        showCheckmark: false,
        selectedColor: C.dark ? Color.alphaBlend(C.accent.withValues(alpha: 0.32), C.surface2) : C.accentBg,
        backgroundColor: C.surface2,
        labelStyle: TextStyle(color: sel ? C.text : C.textSoft, fontWeight: sel ? FontWeight.w600 : FontWeight.w400, fontSize: 13),
        side: BorderSide(color: sel ? C.tileOnBorder : C.border),
        onSelected: (_) => onTap(),
      );

  Widget _filterCard() {
    final macs = _whIdx.keys.toList()..sort((a, b) => _stripLabel(a).compareTo(_stripLabel(b)));
    final all = _tr('الكل', 'All');
    return section(_tr('فلتر', 'Filter'), [
      Wrap(spacing: 6, runSpacing: 6, children: [
        _chip(all, _mac == null, () => _pick(null)),
        for (final m in macs) _chip(_stripLabel(m), _mac == m, () => _pick(m)),
      ]),
      if (_mac != null)
        Wrap(spacing: 6, runSpacing: 6, children: [
          _chip(_tr('كل المخارج', 'All outlets'), _outlet == 0, () => _pick(_mac, 0)),
          for (var n = 1; n <= 4; n++) _chip(_outletLabel(_mac!, n), _outlet == n, () => _pick(_mac, n)),
        ]),
    ]);
  }

  // ---------- peak ----------
  String _when(int epochS) {
    final d = DateTime.fromMillisecondsSinceEpoch(epochS * 1000);
    return '${_formatDate(OutletHistory.dayKey(d))} · ${fmtTime12(d.hour, d.minute)}';
  }

  Widget _peakLine(String label, int w, String sub, {bool big = false}) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: C.textSoft, fontSize: 13)),
            if (sub.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(sub, style: TextStyle(color: C.muted, fontSize: 12)),
            ],
          ]),
        ),
        const SizedBox(width: 10),
        Text('$w W', textDirection: TextDirection.ltr, style: mono(big ? 22 : 16, color: C.accent)),
      ]);

  Widget _peakCard(List<_DayStat> daily, List<_StripUse> strips) {
    final lines = <Widget>[];
    // hub: highest total load of a strip, per day (no time of day)
    if (_outlet == 0) {
      _DayStat? hp;
      for (final d in daily) {
        if (d.peakW > 0 && (hp == null || d.peakW > hp.peakW)) hp = d;
      }
      if (hp != null) {
        lines.add(_peakLine(_mac == null ? _tr('أعلى حمل لمشترك', 'Highest strip load') : _tr('أعلى حمل للمشترك', 'Strip peak load'), hp.peakW,
            _formatDate(hp.date), big: true));
      }
    }
    // app-recorded: highest single outlet, with time
    _Row? best;
    for (final st in strips) {
      for (final r in st.outlets) {
        final p = r.peak;
        if (p != null && (best == null || p.peakW > best.peak!.peakW)) best = r;
      }
    }
    if (best != null) {
      final p = best.peak!;
      final who = _mac == null ? '${_stripLabel(best.mac)} · ${best.name}' : best.name;
      lines.add(_peakLine(_outlet == 0 ? '${_tr('أعلى مخرج', 'Top outlet')}: $who' : who, p.peakW, p.peakAt > 0 ? _when(p.peakAt) : '', big: _outlet != 0));
    }
    if (_outlet != 0 && _mac != null) {
      lines.add(_peakLine(_tr('الحمل دلوقتي', 'Load now'), _liveW(_mac!, _outlet).round(), ''));
    }
    if (best == null) {
      lines.add(Text(
          _tr('ذروة كل مخرج بتتسجّل من التطبيق وهو متصل بالهاب، وهتظهر هنا مع الوقت.',
              'Per-outlet peaks are recorded by the app while it is connected to the hub, and will show up here over time.'),
          style: TextStyle(color: C.muted, fontSize: 12, height: 1.5)));
    }
    return section(_tr('أعلى استهلاك (Peak)', 'Peak'), lines);
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
    final stripWh = _stripWh(st.mac, _period); // whole strip, whatever the outlet filter
    final kwh = stripWh / 1000;
    final share = total == 0 ? 0.0 : stripWh / total;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardBox(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: _mac == null ? () => _pick(st.mac) : null,
          child: Row(children: [
            Expanded(child: Text(st.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            Text('${kwh.toStringAsFixed(2)} kWh', textDirection: TextDirection.ltr, style: mono(15, color: C.accent)),
          ]),
        ),
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
        for (final r in st.outlets) Padding(padding: const EdgeInsets.only(bottom: 10), child: _outletRow(r, stripWh)),
      ]),
    );
  }

  Widget _outletRow(_Row r, int total) {
    final share = total == 0 ? 0.0 : r.wh / total;
    final p = r.peak;
    final selected = _mac == r.mac && _outlet == r.n;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _pick(r.mac, selected ? 0 : r.n),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
          Text('${(r.wh / 1000).toStringAsFixed(2)} kWh', textDirection: TextDirection.ltr, style: mono(12, color: C.textSoft)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: share.clamp(0.0, 1.0), minHeight: 8, color: C.accent, backgroundColor: C.surface2),
        ),
        const SizedBox(height: 5),
        Row(children: [
          Text('${(share * 100).toStringAsFixed(0)}%', textDirection: TextDirection.ltr, style: mono(11, color: C.muted)),
          const SizedBox(width: 8),
          Text('${_tr('دلوقتي', 'Now')} ', style: TextStyle(color: C.muted, fontSize: 11)),
          Text('${r.liveW.round()} W', textDirection: TextDirection.ltr, style: mono(11, color: r.liveW > 0 ? C.accent : C.muted)),
          const SizedBox(width: 8),
          Expanded(
            child: p != null && p.peakW > 0
                ? Text('⚡ ${p.peakW} W${p.peakAt > 0 ? ' · ${_when(p.peakAt)}' : ''}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end, style: TextStyle(color: C.textSoft, fontSize: 11))
                : const SizedBox.shrink(),
          ),
        ]),
      ]),
    );
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
