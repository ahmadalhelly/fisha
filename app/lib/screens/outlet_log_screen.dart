import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:shared_preferences/shared_preferences.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../services/report_export.dart';
import '../theme.dart';
import '../widgets/common.dart';

String _tr(String ar, String en) => Tr.isAr ? ar : en;

/// One finished (or running) on/off cycle of an outlet, as the hub logged it.
class OutletCycle {
  final int outlet;
  final DateTime on;
  final DateTime? off; // null = still on
  final int wh;
  final int src; // 0 = the strip's own button, 1 = a command from the hub (app, schedule, rule, timer)
  const OutletCycle(this.outlet, this.on, this.off, this.wh, this.src);

  factory OutletCycle.fromJson(Map<String, dynamic> j) {
    int n(Object? v) => v is num ? v.toInt() : 0;
    final off = n(j['off']);
    return OutletCycle(n(j['n']), DateTime.fromMillisecondsSinceEpoch(n(j['on']) * 1000), off > 0 ? DateTime.fromMillisecondsSinceEpoch(off * 1000) : null, n(j['wh']), n(j['src']));
  }

  Duration duration(DateTime now) => (off ?? now).difference(on);
}

/// The history of one outlet (or all outlets of a strip): summary tiles, a timeline per day, the daily energy and every
/// cycle, for the last 24 hours, 7 or 30 days. The log lives on the hub; the cost uses the tariff set in the energy page.
class OutletLogScreen extends StatefulWidget {
  final AppState state;
  final String mac;
  final int outlet; // 0 = every outlet of the strip
  /// tests hand the log in without a hub
  final Future<CmdResult> Function(Map<String, dynamic> body)? loader;
  const OutletLogScreen({super.key, required this.state, required this.mac, required this.outlet, this.loader});

  @override
  State<OutletLogScreen> createState() => _OutletLogScreenState();
}

class _OutletLogScreenState extends State<OutletLogScreen> {
  AppState get s => widget.state;
  int _days = 7;
  bool _loading = true;
  bool _failed = false;
  bool _more = false; // the hub sent only the newest cycles of this period
  List<OutletCycle> _cycles = const [];
  final GlobalKey _chartKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadSort();
    _load();
  }

  int _loadSeq = 0;

  Future<void> _load() async {
    final seq = ++_loadSeq;
    setState(() {
      _loading = true;
      _failed = false;
    });
    final body = {'mac': widget.mac, 'outlet': widget.outlet, 'days': _days};
    final r = widget.loader != null ? await widget.loader!(body) : await s.api('outlet_log', body);
    final l = r.data?['cycles'];
    if (!mounted || seq != _loadSeq) return;
    setState(() {
      _loading = false;
      _more = r.data?['more'] == true;
      if (!r.ok || l is! List) {
        _failed = true;
        _cycles = const [];
      } else {
        final from = DateTime.now().subtract(Duration(days: _days));
        _cycles = [
          for (final c in l)
            if (c is Map<String, dynamic>) OutletCycle.fromJson(c)
        ].where((c) => (c.off ?? DateTime.now()).isAfter(from)).toList();
      }
    });
  }

  String get _title {
    final st = s.allStrips.where((x) => x.mac.toUpperCase() == widget.mac.toUpperCase());
    final strip = st.isEmpty ? widget.mac : s.stripName(st.first);
    if (widget.outlet == 0) return strip;
    final name = st.isEmpty ? '' : s.outletName(st.first, widget.outlet);
    return name.isEmpty ? '$strip · ${_tr('مخرج', 'outlet')} ${widget.outlet}' : name;
  }

  String _hm(DateTime d) => fmtTime12(d.hour, d.minute);

  /// the outlet's own name (as set in the account) of a cycle
  String _outletOf(int n) {
    final st = s.allStrips.where((x) => x.mac.toUpperCase() == widget.mac.toUpperCase());
    return st.isEmpty ? '${_tr('مخرج', 'Outlet')} $n' : s.outletName(st.first, n);
  }

  /// "2 س 43 د" / "54 دقيقة" for the tiles, in full words
  String _durLong(Duration d) {
    final m = d.inMinutes;
    if (m < 60) return _tr('$m دقيقة', '$m min');
    final h = m ~/ 60, r = m % 60;
    return r == 0 ? _tr('$h ساعة', '$h h') : _tr('$h س $r د', '${h}h ${r}m');
  }

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
    if (diff == 0) return _tr('النهارده', 'Today');
    if (diff == 1) return _tr('امبارح', 'Yesterday');
    return '${d.day}/${d.month}';
  }

  /// each cycle cut at midnight into per-day pieces: day -> list of (startSecond, endSecond)
  Map<DateTime, List<(int, int)>> _perDay() {
    final out = <DateTime, List<(int, int)>>{};
    final now = DateTime.now();
    for (final c in _cycles) {
      var a = c.on;
      final b = c.off ?? now;
      while (a.isBefore(b)) {
        final day = DateTime(a.year, a.month, a.day);
        final next = DateTime(a.year, a.month, a.day + 1);   // calendar arithmetic: a day is 23 or 25 hours when the clock changes
      if (!next.isAfter(a)) break;
        final end = b.isBefore(next) ? b : next;
        out.putIfAbsent(day, () => []).add((a.difference(day).inSeconds, end.difference(day).inSeconds));
        a = next;
      }
    }
    return out;
  }

  Map<DateTime, double> _dailyKwh() {
    final out = <DateTime, double>{};
    for (final c in _cycles) {
      final d = DateTime(c.on.year, c.on.month, c.on.day);
      out[d] = (out[d] ?? 0) + c.wh / 1000;
    }
    return out;
  }

  Future<Uint8List?> _png() async {
    try {
      final b = _chartKey.currentContext?.findRenderObject();
      if (b is! RenderRepaintBoundary) return null;
      final img = await b.toImage(pixelRatio: 3);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> _export() async {
    final fmt = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: Icon(Icons.picture_as_pdf_outlined, color: C.accent), title: const Text('PDF'), subtitle: Text(_tr('الرسم والأرقام وكل الدورات', 'Chart, numbers and every cycle')), onTap: () => Navigator.pop(ctx, 'pdf')),
          ListTile(leading: Icon(Icons.table_chart_outlined, color: C.accent), title: const Text('CSV / Excel'), subtitle: Text(_tr('سطر لكل دورة', 'One row per cycle')), onTap: () => Navigator.pop(ctx, 'csv')),
          ListTile(leading: Icon(Icons.image_outlined, color: C.accent), title: Text(_tr('صورة الرسم (PNG)', 'Chart image (PNG)')), onTap: () => Navigator.pop(ctx, 'png')),
        ]),
      ),
    );
    if (fmt == null) return;
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    String dt(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)} ${fmtTime12(d.hour, d.minute)}';
    final base = 'fisha-history-${now.year}${two(now.month)}${two(now.day)}';
    try {
      Uint8List bytes;
      if (fmt == 'png') {
        final p = await _png();
        if (p == null) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('err_failed'))));
          return;
        }
        bytes = p;
      } else {
        final rows = [
          for (final c in _cycles)
            [dt(c.on), c.off == null ? _tr('شغال', 'running') : dt(c.off!), '${c.duration(now).inMinutes}', (c.wh / 1000).toStringAsFixed(3), (c.wh / 1000 * s.tariff).toStringAsFixed(2), c.src == 1 ? _tr('تطبيق/جدولة', 'app/schedule') : _tr('زرار', 'button')]
        ];
        final totalKwh = _cycles.fold<int>(0, (a, c) => a + c.wh) / 1000;
        if (fmt == 'csv') {
          final b = StringBuffer('﻿${[_tr('من', 'From'), _tr('إلى', 'To'), _tr('الدقايق', 'Minutes'), 'kWh', t('egp'), _tr('المصدر', 'Source')].join(',')}\r\n');
          for (final r in rows) {
            b.write('${r[0]},${r[1]},${r[2]},${r[3]},${r[4]},${r[5]}\r\n');
          }
          bytes = Uint8List.fromList(utf8.encode(b.toString()));
        } else {
          final kwh = _dailyKwh();
          final days = kwh.keys.toList()..sort();
          bytes = await buildPdf(ReportTable(
            title: _title,
            subtitle: _tr('سجل التشغيل لآخر $_days يوم', 'On/off history, last $_days days'),
            header: [_tr('من', 'From'), _tr('إلى', 'To'), _tr('دقيقة', 'Min'), 'kWh', t('egp'), _tr('المصدر', 'Source')],
            rows: rows,
            total: [_tr('الإجمالي', 'Total'), '', '${_cycles.fold<int>(0, (a, c) => a + c.duration(now).inMinutes)}', totalKwh.toStringAsFixed(3), (totalKwh * s.tariff).toStringAsFixed(2), ''],
            widths: const [0.22, 0.22, 0.1, 0.14, 0.14, 0.18],
            rtl: Tr.isAr,
            chart: [for (final d in days) ('${d.day}', kwh[d] ?? 0.0)],
            chartPng: await _png(),
            chartTitle: _tr('الاستهلاك اليومي (kWh)', 'Daily use (kWh)'),
          ));
        }
      }
      final r = await FilePicker.platform.saveFile(fileName: '$base.$fmt', bytes: bytes);
      if (mounted && r != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_tr('اتحفظ', 'Saved'))));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('err_failed'))));
    }
  }

  Widget _kpi(String label, String value, String sub) => Container(
        padding: const EdgeInsets.all(12),
        decoration: cardBox(radius: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(label, style: TextStyle(color: C.muted, fontSize: 11.5)),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
          const SizedBox(height: 2),
          Text(sub, style: TextStyle(color: C.muted, fontSize: 11.5)),
        ]),
      );

  /// a titled card: every section of the page stands on its own
  Widget _section(String title, Widget child) => Container(
        padding: const EdgeInsets.all(14),
        decoration: cardBox(radius: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: TextStyle(color: C.textSoft, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          child,
        ]),
      );

  // ---- the cycles, one card per outlet --------------------------------------------------------------------------
  static const _sorts = ['recent', 'time', 'energy', 'count', 'longest', 'shortest', 'name', 'manual'];
  String _sort = 'recent';
  List<int> _order = const []; // the hand-made order (outlet numbers), for "manual"
  final Set<int> _open = {};

  String _sortLabel(String k) => switch (k) {
        'recent' => _tr('الأحدث', 'Most recent'),
        'time' => _tr('الأطول تشغيلاً', 'Longest on'),
        'energy' => _tr('الأكثر استهلاكاً', 'Most energy'),
        'count' => _tr('الأكثر تشغيلاً (عدد المرات)', 'Most cycles'),
        'longest' => _tr('أطول دورة', 'Longest cycle'),
        'shortest' => _tr('أقصر دورة', 'Shortest cycle'),
        'name' => _tr('بالاسم', 'By name'),
        _ => _tr('ترتيبي (اسحب وأفلت)', 'My order (drag)'),
      };

  Future<void> _loadSort() async {
    try {
      final p = await SharedPreferences.getInstance();
      final k = p.getString('olog_sort') ?? 'recent';
      final o = p.getStringList('olog_order_${widget.mac.toUpperCase()}') ?? const [];
      if (!mounted) return;
      setState(() {
        _sort = _sorts.contains(k) ? k : 'recent';
        _order = [for (final x in o) int.tryParse(x) ?? 0];
      });
    } catch (_) {}
  }

  Future<void> _saveSort() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('olog_sort', _sort);
      await p.setStringList('olog_order_${widget.mac.toUpperCase()}', [for (final n in _order) '$n']);
    } catch (_) {}
  }

  /// the outlets of the log in the chosen order
  List<int> _sortedOutlets(Map<int, List<OutletCycle>> by, DateTime now) {
    int mins(int n) => by[n]!.fold<int>(0, (a, c) => a + c.duration(now).inMinutes);
    int wh(int n) => by[n]!.fold<int>(0, (a, c) => a + c.wh);
    Duration longest(int n) => by[n]!.map((c) => c.duration(now)).reduce((a, b) => a > b ? a : b);
    Duration shortest(int n) => by[n]!.map((c) => c.duration(now)).reduce((a, b) => a < b ? a : b);
    DateTime last(int n) => by[n]!.map((c) => c.on).reduce((a, b) => a.isAfter(b) ? a : b);
    final l = by.keys.toList()..sort();
    switch (_sort) {
      case 'time':
        l.sort((a, b) => mins(b).compareTo(mins(a)));
      case 'energy':
        l.sort((a, b) => wh(b).compareTo(wh(a)));
      case 'count':
        l.sort((a, b) => by[b]!.length.compareTo(by[a]!.length));
      case 'longest':
        l.sort((a, b) => longest(b).compareTo(longest(a)));
      case 'shortest':
        l.sort((a, b) => shortest(a).compareTo(shortest(b)));
      case 'name':
        l.sort((a, b) => _outletOf(a).compareTo(_outletOf(b)));
      case 'manual':
        int pos(int n) {
          final i = _order.indexOf(n);
          return i < 0 ? 100 + n : i;
        }
        l.sort((a, b) => pos(a).compareTo(pos(b)));
      default:
        l.sort((a, b) => last(b).compareTo(last(a)));
    }
    return l;
  }

  List<Widget> _outletCards(DateTime now) {
    final by = <int, List<OutletCycle>>{};
    for (final c in _cycles) {
      by.putIfAbsent(c.outlet, () => []).add(c);
    }
    final order = _sortedOutlets(by, now);
    Widget card(int n, {Widget? handle}) {
      final list = by[n]!;
      final mins = list.fold<int>(0, (a, c) => a + c.duration(now).inMinutes);
      final wh = list.fold<int>(0, (a, c) => a + c.wh);
      final open = _open.contains(n);
      return Container(
        key: ValueKey('o$n'),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: cardBox(radius: 16),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            onTap: () => setState(() => open ? _open.remove(n) : _open.add(n)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_outletOf(n), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(
                        '${_durLong(Duration(minutes: mins))} · ${list.length == 1 ? _tr('دورة واحدة', '1 cycle') : _tr('${list.length} دورات', '${list.length} cycles')} · $wh Wh',
                        style: TextStyle(color: C.muted, fontSize: 12)),
                  ]),
                ),
                if (list.any((c) => c.off == null))
                  Padding(padding: const EdgeInsetsDirectional.only(end: 6), child: Icon(Icons.circle, size: 9, color: C.green)),
                if (handle != null) handle,
                Icon(open ? Icons.expand_less : Icons.expand_more, color: C.muted),
              ]),
            ),
          ),
          if (open) ...[
            Divider(height: 1, color: C.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _dayList(list, now, boxed: false)),
            ),
          ],
        ]),
      );
    }

    return [
      Row(children: [
        Expanded(child: Text(_tr('المخارج', 'Outlets'), style: TextStyle(color: C.muted, fontSize: 12.5, fontWeight: FontWeight.w700))),
        PopupMenuButton<String>(
          initialValue: _sort,
          color: C.surface2,
          onSelected: (k) {
            setState(() {
              _sort = k;
              if (k == 'manual' && _order.isEmpty) _order = List.of(order);
            });
            _saveSort();
          },
          itemBuilder: (_) => [for (final k in _sorts) PopupMenuItem(value: k, child: Text(_sortLabel(k)))],
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.sort, size: 18, color: C.accent),
              const SizedBox(width: 6),
              Text(_sortLabel(_sort), style: TextStyle(color: C.accent, fontSize: 12.5, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ]),
      const SizedBox(height: 6),
      if (_sort == 'manual')
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorder: (from, to) {
            setState(() {
              final l = List.of(order);
              final x = l.removeAt(from);
              l.insert(to > from ? to - 1 : to, x);
              _order = [...l, ..._order.where((n) => !l.contains(n))]; // outlets not in this period keep their place after
            });
            _saveSort();
          },
          children: [
            for (var i = 0; i < order.length; i++)
              card(order[i], handle: ReorderableDragStartListener(index: i, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.drag_indicator, color: C.muted)))),
          ],
        )
      else
        for (final n in order) card(n),
    ];
  }

  /// cycles by day, newest day first; [boxed] puts each day in its own card (one outlet's page)
  List<Widget> _dayList(List<OutletCycle> list, DateTime now, {bool boxed = true}) {
    final byDay = <DateTime, List<OutletCycle>>{};
    for (final c in list) {
      byDay.putIfAbsent(DateTime(c.on.year, c.on.month, c.on.day), () => []).add(c);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    Widget row(OutletCycle c) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(children: [
            Icon(c.src == 1 ? Icons.phone_android : Icons.touch_app_outlined, size: 18, color: C.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                    c.off == null
                        ? _tr('من ${_hm(c.on)} · شغال دلوقتي', 'From ${_hm(c.on)} · on now')
                        : _tr('من ${_hm(c.on)} إلى ${_hm(c.off!)}', '${_hm(c.on)} to ${_hm(c.off!)}'),
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: c.off == null ? C.green : null)),
                Text('${_durLong(c.duration(now))} · ${c.src == 1 ? _tr('من التطبيق أو الجدولة', 'app or schedule') : _tr('من زرار المشترك', 'strip button')}',
                    style: TextStyle(color: C.muted, fontSize: 11.5)),
              ]),
            ),
            Text('${c.wh} Wh', textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ]),
        );
    final out = <Widget>[];
    for (final d in days) {
      final l = byDay[d]!..sort((a, b) => b.on.compareTo(a.on));
      final wh = l.fold<int>(0, (a, c) => a + c.wh);
      out.add(Padding(
        padding: EdgeInsets.fromLTRB(boxed ? 4 : 0, boxed ? 8 : 10, boxed ? 4 : 0, boxed ? 6 : 2),
        child: Row(children: [
          Expanded(child: Text(_dayLabel(d), style: TextStyle(fontWeight: FontWeight.w800, color: C.textSoft, fontSize: boxed ? 14 : 13))),
          Text('$wh Wh · ${(wh / 1000 * s.tariff).toStringAsFixed(2)} ${t('egp')}', style: TextStyle(color: C.muted, fontSize: 12)),
        ]),
      ));
      final rows = Column(children: [
        for (var i = 0; i < l.length; i++) ...[
          if (i > 0) Divider(height: 1, color: C.border.withValues(alpha: 0.5)),
          row(l[i]),
        ],
      ]);
      out.add(boxed ? Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2), margin: const EdgeInsets.only(bottom: 4), decoration: cardBox(radius: 16), child: rows) : rows);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final totalWh = _cycles.fold<int>(0, (a, c) => a + c.wh);
    final totalMin = _cycles.fold<int>(0, (a, c) => a + c.duration(now).inMinutes);
    final longest = _cycles.isEmpty ? Duration.zero : _cycles.map((c) => c.duration(now)).reduce((a, b) => a > b ? a : b);
    final perDay = _perDay();
    final days = perDay.keys.toList()..sort((a, b) => b.compareTo(a));
    final kwh = _dailyKwh();
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: C.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(_title, style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [IconButton(onPressed: _cycles.isEmpty ? null : _export, icon: const Icon(Icons.ios_share), tooltip: _tr('تصدير', 'Export'))],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: C.accent,
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.fromLTRB(18, 4, 18, 28), children: [
            Row(children: [
              for (final d in const [1, 7, 30])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: ChoiceChip(
                      label: SizedBox(width: double.infinity, child: Text(d == 1 ? _tr('24 ساعة', '24 h') : _tr('$d يوم', '$d days'), textAlign: TextAlign.center)),
                      selected: _days == d,
                      onSelected: (_) {
                        setState(() => _days = d);
                        _load();
                      },
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 12),
            if (_loading) const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
            else if (_failed) emptyCard(_tr('الهاب مش بيرد على السجل. حدّث الهاب لآخر نسخة وجرّب تاني.', 'The hub does not answer the log. Update the hub and try again.'), icon: Icons.history)
            else if (_cycles.isEmpty) emptyCard(_tr('مفيش دورات متسجلة في الفترة دي.', 'No cycles logged in this period.'), icon: Icons.history)
            else ...[
              if (_more)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(_tr('فيه دورات أقدم ما اتعرضتش. اختار فترة أقصر عشان الأرقام تبقى كاملة.', 'Older cycles are not shown. Pick a shorter period for complete numbers.'),
                      style: TextStyle(color: C.warn, fontSize: 12)),
                ),
              for (final row in [
                [
                  _kpi(_tr('مدة التشغيل', 'Time on'), _durLong(Duration(minutes: totalMin)), _tr('مجموع كل الدورات', 'all cycles together')),
                  _kpi(_tr('عدد الدورات', 'Cycles'), _cycles.length == 1 ? _tr('دورة واحدة', '1 cycle') : _tr('${_cycles.length} دورات', '${_cycles.length} cycles'),
                      '${_tr('أطولها', 'longest')} ${_durLong(longest)}'),
                ],
                [
                  _kpi(_tr('الاستهلاك', 'Energy'), '${(totalWh / 1000).toStringAsFixed(2)} kWh', _tr('في الفترة دي', 'in this period')),
                  _kpi(_tr('التكلفة', 'Cost'), '${(totalWh / 1000 * s.tariff).toStringAsFixed(2)} ${t('egp')}', _tr('حسب سعر الكيلو', 'at your tariff')),
                ],
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: IntrinsicHeight(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: row[0]), const SizedBox(width: 10), Expanded(child: row[1])]),
                  ),
                ),
              const SizedBox(height: 14),
              RepaintBoundary(
                key: _chartKey,
                child: ColoredBox(
                  color: C.bg,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _section(
                      _tr('مواعيد التشغيل', 'On times'),
                      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        for (final d in days.take(_days == 1 ? 2 : (_days == 7 ? 7 : 30)))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(children: [
                              SizedBox(width: 62, child: Text(_dayLabel(d), style: TextStyle(color: C.muted, fontSize: 11.5))),
                              // the band and its hours are drawn left to right in both languages: 12 AM is on the left
                              Expanded(
                                child: Directionality(
                                  textDirection: TextDirection.ltr,
                                  child: SizedBox(height: 14, child: CustomPaint(painter: _DayBand(perDay[d]!, C.surface2, C.accent))),
                                ),
                              ),
                            ]),
                          ),
                        const SizedBox(height: 4),
                        Row(children: [
                          const SizedBox(width: 62),
                          Expanded(
                            child: Directionality(
                              textDirection: TextDirection.ltr,
                              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                for (final h in Tr.isAr ? const ['12ص', '6ص', '12م', '6م', '12ص'] : const ['12AM', '6AM', '12PM', '6PM', '12AM'])
                                  Text(h, style: TextStyle(color: C.muted, fontSize: 10)),
                              ]),
                            ),
                          ),
                        ]),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    _section(
                      _tr('الاستهلاك اليومي (kWh)', 'Daily use (kWh)'),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: SizedBox(height: 120, child: CustomPaint(painter: _DayBars(kwh, C.accent, C.muted))),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 18),
              if (widget.outlet == 0) ..._outletCards(now) else ..._dayList(_cycles, now),
            ],
          ]),
        ),
      ),
    );
  }
}

/// one day as a band 00:00 -> 24:00 from the left, the on pieces filled
class _DayBand extends CustomPainter {
  final List<(int, int)> pieces;
  final Color back, fill;
  _DayBand(this.pieces, this.back, this.fill);

  @override
  void paint(Canvas c, Size size) {
    c.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(3)), Paint()..color = back);
    if (size.width < 4) return; // the clamps below need room for a 2 px piece
    for (final p in pieces) {
      // at least 2 px wide and inside the band, also for a cycle in the last minute of the day
      final x1 = (p.$1 / 86400 * size.width).clamp(0.0, size.width - 2);
      final x2 = (p.$2 / 86400 * size.width).clamp(x1 + 2, size.width);
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(x1, 0, x2, size.height), const Radius.circular(2)), Paint()..color = fill);
    }
  }

  @override
  bool shouldRepaint(covariant _DayBand old) => old.pieces != pieces || old.fill != fill;
}

/// bars of the kWh of each day, oldest on the left
class _DayBars extends CustomPainter {
  final Map<DateTime, double> kwh;
  final Color bar, text;
  _DayBars(this.kwh, this.bar, this.text);

  @override
  void paint(Canvas c, Size size) {
    final days = kwh.keys.toList()..sort();
    if (days.isEmpty) return;
    final maxV = kwh.values.fold<double>(0, (a, b) => b > a ? b : a);
    final slot = size.width / days.length;
    final bw = (slot * 0.6).clamp(3.0, 26.0);
    final base = size.height - 16;
    for (var i = 0; i < days.length; i++) {
      final v = kwh[days[i]]!;
      final h = maxV <= 0 ? 0.0 : v / maxV * (base - 14);
      final x = slot * i + (slot - bw) / 2;
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, base - h, bw, h), const Radius.circular(3)), Paint()..color = bar);
      if (days.length <= 10) _label(c, v.toStringAsFixed(1), Offset(slot * i, base - h - 13), slot);
      if (days.length <= 10 || i % (days.length / 8).ceil() == 0) _label(c, '${days[i].day}', Offset(slot * i, base + 2), slot);
    }
  }

  void _label(Canvas c, String t, Offset at, double w) {
    final tp = TextPainter(text: TextSpan(text: t, style: TextStyle(color: text, fontSize: 10)), textDirection: TextDirection.ltr)..layout(minWidth: w, maxWidth: w);
    tp.paint(c, at);
  }

  @override
  bool shouldRepaint(covariant _DayBars old) => old.kwh != kwh;
}
