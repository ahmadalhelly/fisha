import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../screens/energy_screen.dart' show valUnit;
import '../theme.dart';
import 'common.dart';

String _tr(String ar, String en) => Tr.isAr ? ar : en;

class _LinkDay {
  final int day; // days since 1970-01-01 (hub local date)
  final int hubS, upS, drops, longS;
  final int? min, avg;
  const _LinkDay(this.day, this.hubS, this.upS, this.drops, this.longS, this.min, this.avg);
  double get up => hubS <= 0 ? 0 : (upS / hubS * 100).clamp(0, 100).toDouble();
  DateTime get date => DateTime.utc(1970).add(Duration(days: day));
}

/// the strip's link over the last 7 days: % connected, drops, longest drop and signal per day.
class LinkCard extends StatefulWidget {
  final AppState state;
  final String mac;
  const LinkCard({super.key, required this.state, required this.mac});

  @override
  State<LinkCard> createState() => _LinkCardState();
}

class _LinkCardState extends State<LinkCard> {
  bool _loading = true, _supported = true;
  List<_LinkDay?> _days = const []; // oldest → newest, 7 slots, null = no record
  int? _rssi;
  String _ip = '';
  int _lastDrop = 0, _downSince = 0;
  int _sel = 6;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.state.api('link', {'mac': widget.mac});
    if (!mounted) return;
    final j = r.data;
    if (!r.ok || j == null || j['days'] is! List) {
      setState(() {
        _loading = false;
        _supported = false;
      });
      return;
    }
    final byDay = <int, _LinkDay>{};
    for (final m in (j['days'] as List).whereType<Map<String, dynamic>>()) {
      int n(String k) => (m[k] as num?)?.toInt() ?? 0;
      final d = _LinkDay(n('day'), n('hub_s'), n('up_s'), n('drops'), n('long_s'), (m['min'] as num?)?.toInt(), (m['avg'] as num?)?.toInt());
      byDay[d.day] = d;
    }
    final newest = byDay.isEmpty ? DateTime.now().difference(DateTime(1970)).inDays : byDay.keys.reduce((a, b) => a > b ? a : b);
    setState(() {
      _loading = false;
      _days = [for (var i = 6; i >= 0; i--) byDay[newest - i]];
      _rssi = (j['rssi'] as num?)?.toInt();
      _ip = (j['ip'] ?? '').toString();
      _lastDrop = (j['last_drop'] as num?)?.toInt() ?? 0;
      _downSince = (j['down_since'] as num?)?.toInt() ?? 0;
      _sel = 6;
      while (_sel > 0 && _days[_sel] == null) {
        _sel--;
      }
    });
  }

  String _dur(int s) {
    if (s <= 0) return '—';
    if (s < 60) return Tr.isAr ? '$s ث' : '${s}s';
    if (s < 3600) return Tr.isAr ? '${s ~/ 60} د' : '${s ~/ 60}m';
    return Tr.isAr ? '${s ~/ 3600} س ${(s % 3600) ~/ 60} د' : '${s ~/ 3600}h ${(s % 3600) ~/ 60}m';
  }

  String _wd(DateTime d) {
    const ar = ['ن', 'ث', 'ر', 'خ', 'ج', 'س', 'ح'];
    const en = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return (Tr.isAr ? ar : en)[d.weekday - 1];
  }

  String _dayName(int i) {
    final d = _days[i];
    if (d == null) return '';
    if (i == 6) return _tr('النهارده', 'Today');
    if (i == 5) return _tr('امبارح', 'Yesterday');
    return '${d.date.day}/${d.date.month}';
  }

  String _when(int epochS) {
    final d = DateTime.fromMillisecondsSinceEpoch(epochS * 1000);
    final now = DateTime.now();
    final day = DateTime(d.year, d.month, d.day), today = DateTime(now.year, now.month, now.day);
    final label = day == today ? _tr('النهارده', 'Today') : (today.difference(day).inDays == 1 ? _tr('امبارح', 'Yesterday') : '${d.day}/${d.month}');
    return '$label · ${fmtTime12(d.hour, d.minute)}';
  }

  (String, Color) _signal(int? r) {
    if (r == null) return ('—', C.muted);
    if (r >= -60) return (_tr('ممتازة', 'Excellent'), C.accent);
    if (r >= -67) return (_tr('جيدة', 'Good'), C.accent);
    if (r >= -75) return (_tr('مقبولة', 'Fair'), C.warn);
    return (_tr('ضعيفة', 'Weak'), C.danger);
  }

  Color _dropColor(int drops) => drops == 0 ? C.accent : (drops < 3 ? C.warn : C.danger);

  Widget _kpi(String k, Widget v, String sub) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(k, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: C.muted)),
            const SizedBox(height: 4),
            Align(alignment: AlignmentDirectional.centerEnd, child: v),
            const SizedBox(height: 2),
            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: C.faint)),
          ]),
        ),
      );

  Widget _bars() {
    return SizedBox(
      height: 96,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < 7; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _days[i] == null ? null : () => setState(() => _sel = i),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  if (_days[i] != null && _days[i]!.drops > 0)
                    Text('${_days[i]!.drops}', style: mono(10, color: C.textSoft, weight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  _bar(i),
                  const SizedBox(height: 5),
                  Text(_days[i] == null ? '' : _wd(_days[i]!.date),
                      style: TextStyle(fontSize: 10, color: i == _sel ? C.text : C.faint, fontWeight: i == _sel ? FontWeight.w700 : FontWeight.w400)),
                ]),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _bar(int i) {
    final d = _days[i];
    const maxH = 60.0;
    if (d == null) {
      // no record that day (hub off, or before it was tracking): the slot stays, as an outline
      return Container(
        height: maxH * 0.3,
        decoration: BoxDecoration(
          color: C.surface2,
          border: Border.all(color: C.muted.withValues(alpha: 0.7)),
          borderRadius: BorderRadius.circular(6),
        ),
      );
    }
    final h = maxH * ((d.up - 97) / 3).clamp(0.18, 1.0); // 97–100 % spread out, so small losses show
    final color = _dropColor(d.drops);
    final today = i == 6;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      height: h,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(6), bottom: Radius.circular(3)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color, Color.lerp(color, Colors.black, 0.22)!],
        ),
        // today keeps the full colour and is marked by a ring instead of being faded out
        border: today ? Border.all(color: Colors.white.withValues(alpha: 0.75), width: 1.4) : null,
        boxShadow: i == _sel ? [BoxShadow(color: C.bg, spreadRadius: 2), BoxShadow(color: C.textSoft, spreadRadius: 3.5)] : null,
      ),
    );
  }

  Widget _signalStrip() {
    double y(int v) => ((v + 85) / 35).clamp(0.0, 1.0);
    return SizedBox(
      height: 46,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(children: [
          for (var i = 0; i < 7; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: LayoutBuilder(builder: (_, c) {
                final d = _days[i];
                if (d == null || d.min == null || d.avg == null) return const SizedBox();
                final lo = y(d.min!) * c.maxHeight, hi = y(d.avg!) * c.maxHeight;
                return Stack(children: [
                  Positioned(left: c.maxWidth * 0.3, right: c.maxWidth * 0.3, bottom: lo, height: (hi - lo).clamp(2.0, c.maxHeight),
                      child: DecoratedBox(decoration: BoxDecoration(color: C.blue.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(4)))),
                  Positioned(left: c.maxWidth * 0.18, right: c.maxWidth * 0.18, bottom: hi - 1, height: 2,
                      child: DecoratedBox(decoration: BoxDecoration(color: C.blue, borderRadius: BorderRadius.circular(1)))),
                ]);
              }),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _detail() {
    final d = _days[_sel];
    if (d == null) return const SizedBox();
    Widget r(String k, String v) => Row(children: [
          Expanded(child: Text(k, style: TextStyle(fontSize: 11.5, color: C.muted))),
          Text(v, textDirection: TextDirection.ltr, style: mono(11.5, weight: FontWeight.w600)),
        ]);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(_dayName(_sel), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: r(_tr('الاتصال', 'Connected'), '${d.up.toStringAsFixed(1)}%')),
          const SizedBox(width: 14),
          Expanded(child: r(_tr('الانقطاعات', 'Drops'), '${d.drops}')),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: r(_tr('أطول انقطاع', 'Longest'), _dur(d.longS))),
          const SizedBox(width: 14),
          Expanded(child: r(_tr('أدنى إشارة', 'Lowest'), d.min == null ? '—' : '${d.min} dBm')),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: r(_tr('متوسط الإشارة', 'Average'), d.avg == null ? '—' : '${d.avg} dBm')),
          const SizedBox(width: 14),
          const Expanded(child: SizedBox()),
        ]),
      ]),
    );
  }

  Widget _legend() {
    Widget item(Color c, String l, {bool outline = false}) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: outline ? null : c, border: outline ? Border.all(color: c) : null, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 4),
          Text(l, style: TextStyle(fontSize: 10.5, color: C.muted)),
        ]);
    return Wrap(spacing: 12, runSpacing: 4, children: [
      item(C.accent, _tr('مفيش انقطاع', 'No drops')),
      item(C.warn, _tr('1-2 انقطاع', '1-2 drops')),
      item(C.danger, _tr('3 أو أكتر', '3 or more')),
      item(C.muted, _tr('مفيش بيانات', 'No data'), outline: true),
    ]);
  }

  Widget _foot(String k, String v) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(children: [
          Expanded(child: Text(k, style: TextStyle(fontSize: 11.5, color: C.muted))),
          Text(v, textDirection: TextDirection.ltr, style: mono(12, color: C.textSoft, weight: FontWeight.w600)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        height: 80,
        decoration: cardBox(),
        alignment: Alignment.center,
        child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: C.accent)),
      );
    }
    if (!_supported) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: cardBox(),
        child: Text(_tr('سجل الاتصال محتاج تحديث فيرموير الهاب.', 'Link history needs a hub firmware update.'),
            style: TextStyle(color: C.muted, fontSize: 12.5)),
      );
    }
    final have = _days.whereType<_LinkDay>().toList();
    final hubS = have.fold<int>(0, (a, d) => a + d.hubS), upS = have.fold<int>(0, (a, d) => a + d.upS);
    final pct = hubS <= 0 ? null : (upS / hubS * 100).clamp(0, 100).toDouble();
    final drops = have.fold<int>(0, (a, d) => a + d.drops);
    final longest = have.fold<int>(0, (a, d) => d.longS > a ? d.longS : a);
    final (sigLabel, sigColor) = _signal(_rssi);
    final (grade, gradeColor) = pct == null
        ? ('', C.muted)
        : (pct >= 99.5 && drops <= 1)
            ? (_tr('مستقر', 'Stable'), C.accent)
            : (pct >= 97 || drops <= 5)
                ? (_tr('متقطع', 'Patchy'), C.warn)
                : (_tr('ضعيف', 'Poor'), C.danger);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardBox(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: C.blue.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.wifi, size: 17, color: C.blue),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(_tr('الشبكة والاتصال', 'Network & connection'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
          if (grade.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: gradeColor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
              child: Text(grade, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: gradeColor)),
            ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          _kpi(_tr('نسبة الاتصال', 'Connected'), pct == null ? Text('—', style: mono(16)) : valUnit(pct.toStringAsFixed(1), '%', size: 16, weight: FontWeight.w700),
              _tr('آخر 7 أيام', 'Last 7 days')),
          const SizedBox(width: 8),
          _kpi(_tr('الانقطاعات', 'Drops'), Text('$drops', style: mono(16, weight: FontWeight.w700)),
              longest > 0 ? '${_tr('أطولها', 'Longest')} ${_dur(longest)}' : _tr('مفيش', 'None')),
          const SizedBox(width: 8),
          _kpi(_tr('الإشارة الآن', 'Signal now'),
              _rssi == null ? Text('—', style: mono(16)) : valUnit('$_rssi', 'dBm', size: 16, weight: FontWeight.w700), sigLabel),
        ]),
        if (have.isEmpty) ...[
          const SizedBox(height: 12),
          Text(_tr('لسه بنجمع البيانات. الأرقام هتظهر هنا مع الوقت.', 'Collecting data. Numbers will show up here over time.'),
              style: TextStyle(color: C.muted, fontSize: 12)),
        ] else ...[
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: Text(_tr('الاتصال يوم بيوم', 'Day by day'), style: TextStyle(fontSize: 11, color: C.muted))),
            Text(_dayName(_sel), style: TextStyle(fontSize: 11, color: C.muted)),
          ]),
          const SizedBox(height: 6),
          _bars(),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: Text(_tr('الإشارة (أدنى ← متوسط)', 'Signal (lowest → average)'), style: TextStyle(fontSize: 11, color: C.muted))),
            Text('dBm', style: TextStyle(fontSize: 11, color: C.muted)),
          ]),
          const SizedBox(height: 4),
          _signalStrip(),
          const SizedBox(height: 10),
          _detail(),
          const SizedBox(height: 10),
          _legend(),
        ],
        const SizedBox(height: 6),
        Divider(color: C.border, height: 16),
        _foot(_tr('عنوان IP', 'IP address'), _ip.isEmpty ? '—' : _ip),
        if (_downSince > 0)
          _foot(_tr('مفصول من', 'Offline since'), _when(_downSince))
        else
          _foot(_tr('آخر انقطاع', 'Last drop'), _lastDrop > 0 ? _when(_lastDrop) : _tr('لم يحدث', 'None')),
      ]),
    );
  }
}
