import 'dart:math' as math;

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../models.dart';
import '../services/outlet_history.dart';
import '../services/report_export.dart';
import '../theme.dart';
import '../widgets/common.dart';

part 'energy/stack_chart.dart';

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
  final bool missing; // 2.0.10: a calendar day inside the history with no record (kept as an empty slot, not dropped)
  const _DayStat({required this.date, required this.wh, required this.peakW, this.missing = false});
}

/// "12.3 W": number and unit always together, left-to-right, the unit a little smaller (2.0.10)
Widget valUnit(String v, String unit, {double size = 13, Color? color, FontWeight weight = FontWeight.w600, Color? unitColor}) => Row(
      mainAxisSize: MainAxisSize.min,
      textDirection: TextDirection.ltr,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(v, style: mono(size, color: color ?? C.text, weight: weight)),
        SizedBox(width: size * 0.28),
        Text(unit, style: TextStyle(fontSize: size * 0.72, color: unitColor ?? C.muted, fontWeight: FontWeight.w500)),
      ],
    );

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

  /// the calendar days of the selected period, newest first (same for every filter, so shares add up). 2.0.10: a day
  /// with no record inside the history (e.g. one the hub could not save) stays in the list as a missing day.
  List<int> get _period {
    if (_allDates.isEmpty) return const [];
    final oldest = _allDates.last;
    var d = DateTime.now();
    final newestKey = OutletHistory.dayKey(d);
    if (_allDates.first > newestKey) d = DateTime(_allDates.first ~/ 10000, (_allDates.first ~/ 100) % 100, _allDates.first % 100);
    final out = <int>[];
    for (var i = 0; i < _range; i++) {
      final k = OutletHistory.dayKey(d);
      if (k < oldest) break;
      out.add(k);
      d = DateTime(d.year, d.month, d.day - 1);
    }
    return out;
  }

  // 2.0.22: the selected period as a CSV (Excel opens it): one row per day, strip and outlet, with kWh and cost
  Future<void> _export() async {
    final days = _period;
    if (days.isEmpty) return;
    final fmt = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final f in const [('pdf', Icons.picture_as_pdf_outlined, 'PDF'), ('docx', Icons.description_outlined, 'Word (DOCX)'), ('csv', Icons.table_chart_outlined, 'CSV / Excel')])
            ListTile(leading: Icon(f.$2, color: C.accent), title: Text(f.$3), onTap: () => Navigator.pop(ctx, f.$1)),
        ]),
      ),
    );
    if (fmt == null) return;
    final names = {for (final st in s.allStrips) st.mac.toUpperCase(): s.stripName(st)};
    String q(String v) => '"${v.replaceAll('"', '""')}"';
    String dateOf(int d) => '${d ~/ 10000}-${((d ~/ 100) % 100).toString().padLeft(2, '0')}-${(d % 100).toString().padLeft(2, '0')}';
    final rows = <List<String>>[];
    var total = 0.0;
    for (final d in days.reversed) {
      for (final m in _selMacs) {
        final wh = _whIdx[m]?[d];
        if (wh == null) continue;
        for (var o = 0; o < wh.length; o++) {
          if (_mac != null && _outlet != 0 && o + 1 != _outlet) continue;
          final kwh = wh[o] / 1000;
          total += kwh;
          rows.add([dateOf(d), names[m.toUpperCase()] ?? m, '${o + 1}', kwh.toStringAsFixed(3), (kwh * s.tariff).toStringAsFixed(2)]);
        }
      }
    }
    final header = [_tr('اليوم', 'Date'), _tr('المشترك', 'Strip'), _tr('المخرج', 'Outlet'), 'kWh', t('egp')];
    final totalRow = [_tr('الإجمالي', 'Total'), '', '', total.toStringAsFixed(3), (total * s.tariff).toStringAsFixed(2)];
    final base = 'fisha-energy-${days.last}-${days.first}';
    Uint8List bytes;
    try {
      if (fmt == 'csv') {
        final b = StringBuffer('\uFEFF${header.join(',')}\r\n');
        for (final r in rows) {
          b.write('${r[0]},${q(r[1])},${r[2]},${r[3]},${r[4]}\r\n');
        }
        b.write(',${q(totalRow[0])},,${totalRow[3]},${totalRow[4]}\r\n');
        bytes = Uint8List.fromList(utf8.encode(b.toString()));
      } else {
        final table = ReportTable(
          title: _tr('تقرير استهلاك الكهرباء', 'Energy report'),
          subtitle: '${dateOf(days.last)}  →  ${dateOf(days.first)}',
          header: header,
          rows: rows,
          total: totalRow,
          widths: const [0.2, 0.34, 0.12, 0.17, 0.17],
          rtl: Tr.isAr,
        );
        bytes = fmt == 'pdf' ? await buildPdf(table) : buildDocx(table);
      }
      final res = await FilePicker.platform.saveFile(fileName: '$base.$fmt', bytes: bytes);
      if (!mounted) return;
      if (res != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_tr('اتحفظ التقرير', 'Report saved'))));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('err_failed'))));
    }
  }

  bool _hasDay(int date) => _selMacs.any((m) => _whIdx[m]?.containsKey(date) ?? false);

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

  // 2.0.17: every series gets its own hue, never tones of one colour (they blur together in a stacked bar).
  // Strips: hues spread around the wheel. Outlets: the strip's hue plus 90°, 180° and 270° (tetradic).
  static const _palette = [
    Color(0xFF2EE6B0), // teal
    Color(0xFFFFB547), // amber
    Color(0xFF6AA8FF), // blue
    Color(0xFFF472B6), // pink
    Color(0xFF9BE564), // lime
    Color(0xFFA78BFA), // violet
    Color(0xFFFF7A5C), // coral
    Color(0xFF4DD9E8), // cyan
  ];
  List<String> get _macOrder => _whIdx.keys.toList()..sort((a, b) => _stripLabel(a).compareTo(_stripLabel(b)));
  Color _stripColor(String mac) => _palette[math.max(0, _macOrder.indexOf(mac)) % _palette.length];
  Color _outletColor(String mac, int n) {
    final h = HSLColor.fromColor(_stripColor(mac));
    // same brightness for all four, so no outlet reads as "the faint one"
    return h.withHue((h.hue + 90 * (n - 1)) % 360).withSaturation(0.72).withLightness(0.62).toColor();
  }

  /// the chart's stacked parts under the current filter: strips (all), outlets (one strip) or one outlet; days oldest first
  ({List<String> labels, List<Color> colors, List<_StackDay> days}) _stack(List<_DayStat> daily) {
    final labels = <String>[], colors = <Color>[], keys = <(String, int)>[];
    if (_mac == null) {
      for (final m in _macOrder) {
        labels.add(_stripLabel(m));
        colors.add(_stripColor(m));
        keys.add((m, -1));
      }
    } else if (_outlet == 0) {
      for (var n = 1; n <= 4; n++) {
        labels.add(_outletLabel(_mac!, n));
        colors.add(_outletColor(_mac!, n));
        keys.add((_mac!, n - 1));
      }
    } else {
      labels.add(_outletLabel(_mac!, _outlet));
      colors.add(_stripColor(_mac!));
      keys.add((_mac!, _outlet - 1));
    }
    final days = [
      for (final d in daily.reversed)
        _StackDay(d.date, d.missing, d.peakW, [for (final (m, k) in keys) k < 0 ? _stripWh(m, [d.date]) : _outletWh(m, d.date, k)]),
    ];
    return (labels: labels, colors: colors, days: days);
  }

  String get _filterTitle => _mac == null
      ? _tr('كل المشتركات', 'All strips')
      : _outlet == 0
          ? _stripLabel(_mac!)
          : '${_stripLabel(_mac!)} · ${_outletLabel(_mac!, _outlet)}';

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
      out.add(_DayStat(date: d, wh: wh, peakW: peak, missing: !_hasDay(d)));
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
              Row(children: [
                Expanded(child: Text(t('energy_title'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700))),
                if (s.hubV2 && s.can(Perm.export) && _whIdx.isNotEmpty)
                  IconButton(
                    tooltip: _tr('تصدير تقرير الاستهلاك', 'Export energy report'),
                    onPressed: _export,
                    icon: Icon(Icons.file_download_outlined, color: C.accent),
                  ),
              ]),
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
                // 2.0.15: the total cost first, then the use; the average day and how many days have data under them
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
                  child: Text('$_filterTitle · ${_tr('آخر', 'last')} $_range ${_tr('يوم', 'days')}',
                      style: TextStyle(color: C.textSoft, fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                Row(children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: _editTariff,
                      child: _bigStat(_tr('التكلفة الإجمالية', 'Total cost'), (kwh * s.tariff).toStringAsFixed(2), t('egp'),
                          foot: '${t('tariff')}: ${s.tariff.toStringAsFixed(2)} ✎'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _bigStat(t('total_used'), kwh.toStringAsFixed(2), 'kWh',
                          foot: _mac == null || allWh == 0 ? null : '${(totalWh * 100 / allWh).toStringAsFixed(0)}% ${_tr('من الإجمالي', 'of total')}')),
                ]),
                if (daily.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _summaryLine(daily, totalWh),
                ],
                const SizedBox(height: 14),
                if (_loading && _data.isEmpty) Center(child: Padding(padding: const EdgeInsets.all(24), child: CircularProgressIndicator(color: C.accent))),
                if (!_loading && daily.isEmpty) emptyCard(t('energy_empty'), icon: Icons.bar_chart),
                if (daily.isNotEmpty) ...[
                  _peakCard(daily, strips),
                  const SizedBox(height: 14),
                  Builder(builder: (_) {
                    final st = _stack(daily);
                    return section(t('daily_usage'), [
                      _StackBars(key: ValueKey('$_mac/$_outlet/$_range'), days: st.days, labels: st.labels, colors: st.colors, tariff: s.tariff),
                    ]);
                  }),
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
        valUnit('$w', 'W', size: big ? 22 : 16, color: C.accent),
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

  Widget _summaryLine(List<_DayStat> daily, int totalWh) {
    final withData = daily.where((d) => !d.missing).length;
    final avg = withData == 0 ? 0.0 : totalWh / withData / 1000;
    final st = TextStyle(color: C.muted, fontSize: 12);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(children: [
        Text('${_tr('متوسط اليوم', 'Daily avg')} ', style: st),
        valUnit(avg.toStringAsFixed(2), 'kWh', size: 12, color: C.textSoft, weight: FontWeight.w500),
        Text('  ·  ', style: st),
        valUnit((avg * s.tariff).toStringAsFixed(2), t('egp'), size: 12, color: C.textSoft, weight: FontWeight.w500),
        const Spacer(),
        Text('${_tr('أيام ببيانات', 'Days with data')} ', style: st),
        Text('$withData/${daily.length}', textDirection: TextDirection.ltr, style: mono(12, color: C.textSoft)),
      ]),
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
    final stripWh = _stripWh(st.mac, _period); // whole strip, whatever the outlet filter
    final kwh = stripWh / 1000;
    final share = total == 0 ? 0.0 : stripWh / total;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardBox(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: _mac == null ? () => _pick(st.mac) : null,
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(child: Text(st.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
            valUnit(kwh.toStringAsFixed(2), 'kWh', size: 18, color: C.accent),
          ]),
        ),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
            child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
              Text('${(share * 100).toStringAsFixed(0)}% ${_tr('من الإجمالي', 'of total')}', style: TextStyle(color: C.muted, fontSize: 12)),
              if (st.peakW > 0) ...[
                Text('·', style: TextStyle(color: C.muted, fontSize: 12)),
                Text(_tr('أعلى حمل', 'Peak'), style: TextStyle(color: C.muted, fontSize: 12)),
                valUnit('${st.peakW}', 'W', size: 12, color: C.textSoft, weight: FontWeight.w500),
              ],
            ]),
          ),
          valUnit((kwh * s.tariff).toStringAsFixed(2), t('egp'), size: 14, color: C.text, weight: FontWeight.w600),
        ]),
        const SizedBox(height: 6),
        for (final r in st.outlets) _outletRow(r, stripWh),
      ]),
    );
  }

  // 2.0.10: name + kWh, bar, then three fixed cells (share · now · peak with its day and time on a second line)
  Widget _outletRow(_Row r, int total) {
    final share = total == 0 ? 0.0 : r.wh / total;
    final p = r.peak;
    final selected = _mac == r.mac && _outlet == r.n;
    Widget cell(String label, Widget value, [Widget? sub]) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: TextStyle(color: C.muted, fontSize: 10.5)),
            const SizedBox(height: 3),
            value,
            if (sub != null) ...[const SizedBox(height: 2), sub],
          ]),
        );
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _pick(r.mac, selected ? 0 : r.n),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: C.border.withValues(alpha: 0.6)))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
            valUnit((r.wh / 1000).toStringAsFixed(2), 'kWh', size: 14),
            const SizedBox(width: 10),
            valUnit((r.wh / 1000 * s.tariff).toStringAsFixed(2), t('egp'), size: 13, color: C.textSoft, weight: FontWeight.w600),
          ]),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: share.clamp(0.0, 1.0), minHeight: 6, color: C.accent, backgroundColor: C.surface2),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: C.surface2.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(12)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              cell(_tr('النسبة', 'Share'), Text('${(share * 100).toStringAsFixed(0)}%', textDirection: TextDirection.ltr, style: mono(13, weight: FontWeight.w600))),
              cell(_tr('دلوقتي', 'Now'), valUnit(_w(r.liveW), 'W', color: r.liveW > 0 ? C.accent : C.text)),
              cell(
                _tr('أعلى حمل', 'Peak'),
                p != null && p.peakW > 0 ? valUnit('${p.peakW}', 'W') : Text('—', style: mono(13, color: C.muted)),
                p != null && p.peakW > 0 && p.peakAt > 0 ? _whenText(p.peakAt) : null,
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  String _w(double w) => w > 0 && w < 10 ? w.toStringAsFixed(1) : w.round().toString();

  /// "اليوم · 1:55 م" / "8/10 · 9:10 م" as one right-to-left line, digits kept left-to-right
  Widget _whenText(int epochS) {
    final d = DateTime.fromMillisecondsSinceEpoch(epochS * 1000);
    return Text('${_shortDate(OutletHistory.dayKey(d))} · ${fmtTime12(d.hour, d.minute)}',
        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.muted, fontSize: 10.5));
  }

  /// today / yesterday / d/m (d/m/yyyy only for another year)
  String _shortDate(int k) {
    final f = _formatDate(k);
    if (!f.contains('/')) return f;
    return k ~/ 10000 == DateTime.now().year ? '${k % 100}/${(k ~/ 100) % 100}' : f;
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

  // 2.0.10: date · bar · kWh on one line, peak and cost under it; a missing day keeps its row
  Widget _dailyRow(_DayStat d, int maxWh) {
    final kwh = d.wh / 1000;
    final ratio = maxWh > 0 ? (d.wh / maxWh).clamp(0.0, 1.0) : 0.0;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: C.border.withValues(alpha: 0.5)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          SizedBox(
            width: 72,
            child: Text(_shortDate(d.date), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: d.missing ? C.muted : C.text)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: d.missing
                  ? Container(height: 6, color: C.surface2)
                  : LinearProgressIndicator(value: ratio, minHeight: 6, backgroundColor: C.surface2, color: C.accent),
            ),
          ),
          const SizedBox(width: 12),
          d.missing
              ? Text(_tr('مفيش بيانات', 'No data'), style: TextStyle(fontSize: 12, color: C.muted))
              : valUnit(kwh.toStringAsFixed(2), 'kWh', size: 13.5, color: C.accent),
        ]),
        if (!d.missing) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 72),
            child: Row(children: [
              if (d.peakW > 0) ...[
                Text('${_tr('أعلى حمل', 'Peak')} ', style: TextStyle(fontSize: 11, color: C.muted)),
                valUnit('${d.peakW}', 'W', size: 11, color: C.textSoft, weight: FontWeight.w500),
              ],
              const Spacer(),
              valUnit((kwh * s.tariff).toStringAsFixed(2), t('egp'), size: 11, color: C.muted, weight: FontWeight.w500),
            ]),
          ),
        ],
      ]),
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
