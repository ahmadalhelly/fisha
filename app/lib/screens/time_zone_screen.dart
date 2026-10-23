import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../i18n.dart';
import '../services/tz_zones.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'schedules_screen.dart' show daysText;

String _tr(String ar, String en) => Tr.isAr ? ar : en;

/// Time and time zone: where the zone comes from (the phone, or a city picked by hand), summer time, and the clocks
/// of the phone, the hub and each strip side by side, with a button that sends the time to every strip now.
class TimeZoneScreen extends StatefulWidget {
  final AppState state;
  const TimeZoneScreen({super.key, required this.state});

  @override
  State<TimeZoneScreen> createState() => _TimeZoneScreenState();
}

class _TimeZoneScreenState extends State<TimeZoneScreen> {
  AppState get s => widget.state;
  bool _auto = true;
  String _zoneId = ''; // the last zone chosen here: the summer-time switch stays on screen after it was turned off
  bool _busy = false;
  String _q = '';
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // the screen opens on "automatic" when the hub's zone is the one the phone is in
    final phone = _phoneZone();
    _zoneId = s.tzZone;
    _auto = phone != null && s.tzZone == phone.id;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  TzZoneInfo? _phoneZone() {
    final y = DateTime.now().year;
    return TzZones.detect(DateTime(y, 1, 1).timeZoneOffset.inMinutes, DateTime(y, 7, 1).timeZoneOffset.inMinutes);
  }

  Future<void> _run(Future<void> Function() f) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await f();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  String _hm(DateTime d, {bool secs = false}) {
    String p(int n) => n.toString().padLeft(2, '0');
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ap = Tr.isAr ? (d.hour >= 12 ? 'م' : 'ص') : (d.hour >= 12 ? 'PM' : 'AM');
    return '$h:${p(d.minute)}${secs ? ':${p(d.second)}' : ''} $ap';
  }

  Future<void> _pick(TzZoneInfo z) => _run(() async {
        _zoneId = z.id;
        await s.setTimeZone(z.id);
        _snack(_tr('اتبعتت المنطقة للهاب والمشتركات', 'The zone was sent to the hub and the strips'));
      });

  Future<void> _setDst(bool on) => _run(() async {
        final z = TzZones.byId(_zoneId);
        if (z == null) return;
        if (on) {
          await s.setTimeZone(z.id);
        } else {
          await s.setFixedOffset(z.stdMin);          // summer time off: the standard offset, fixed
        }
      });

  Widget _card(List<Widget> children) => Container(
        padding: const EdgeInsets.all(14),
        decoration: cardBox(radius: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  Widget _seg(String label, bool on, VoidCallback tap) => Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: tap,
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: on ? C.accent : Colors.transparent, borderRadius: BorderRadius.circular(11)),
            child: Text(label, style: TextStyle(color: on ? C.onAccent : C.muted, fontWeight: FontWeight.w700, fontSize: 13.5)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final phone = _phoneZone();
        final now0 = DateTime.now();
        final cur = TzZones.byId(s.tzZone.isNotEmpty ? s.tzZone : _zoneId);
        final now = DateTime.now();
        final hubNow = now.toUtc().add(Duration(minutes: s.tzOffsetMin));
        final q = _q.trim().toLowerCase();
        final list = [
          for (final z in TzZones.all)
            if (q.isEmpty || z.ar.contains(q) || z.en.toLowerCase().contains(q) || z.country.toLowerCase().contains(q)) z
        ];
        return Scaffold(
          backgroundColor: C.bg,
          appBar: AppBar(
            backgroundColor: C.bg,
            surfaceTintColor: Colors.transparent,
            title: Text(_tr('الوقت والمنطقة الزمنية', 'Time and time zone'), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          body: SafeArea(
            child: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 28), children: [
              Text(_tr('مصدر المنطقة الزمنية', 'Where the zone comes from'), style: TextStyle(color: C.muted, fontSize: 12.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  _seg(_tr('تلقائي من الموبايل', 'From the phone'), _auto, () {
                    setState(() => _auto = true);
                    if (phone != null) {
                      if (s.tzZone != phone.id) _pick(phone);
                    } else {
                      _run(() => s.setFixedOffset(now0.timeZoneOffset.inMinutes));   // a zone that is not in the list: its offset as it is now
                    }
                  }),
                  _seg(_tr('يدوي', 'Manual'), !_auto, () => setState(() => _auto = false)),
                ]),
              ),
              const SizedBox(height: 12),
              if (_auto)
                _card([
                  Row(children: [
                    Icon(Icons.public, color: C.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(phone == null ? TzZones.offsetText(now.timeZoneOffset.inMinutes) : (Tr.isAr ? phone.ar : phone.en), textDirection: phone == null ? TextDirection.ltr : null, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        Text(
                            phone == null
                                ? _tr('منطقة مش في القايمة، بنستخدم فرقها الحالي من غير توقيت صيفي.', 'A zone that is not in the list: its current offset, without summer time.')
                                : '${TzZones.offsetText(now.timeZoneOffset.inMinutes)}${phone.dst ? (Tr.isAr ? ' · فيها توقيت صيفي' : ' · with summer time') : ''}',
                            textDirection: TextDirection.ltr,
                            style: TextStyle(color: C.muted, fontSize: 12)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Text(_tr('بناخد المنطقة من إعدادات الموبايل وبنبعتها للهاب والمشتركات.', 'The zone comes from the phone settings and is sent to the hub and the strips.'),
                      style: TextStyle(color: C.muted, fontSize: 12, height: 1.5)),
                ])
              else ...[
                TextField(
                  onChanged: (v) => setState(() => _q = v),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: _tr('دوّر على مدينة أو دولة', 'Search a city or country'),
                  ),
                ),
                const SizedBox(height: 10),
                _card([
                  for (final z in list)
                    InkWell(
                      onTap: _busy ? null : () => _pick(z),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        child: Row(children: [
                          CircleAvatar(
                            radius: 17,
                            backgroundColor: z.id == s.tzZone ? C.accent : C.surface2,
                            child: Text(z.country, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: z.id == s.tzZone ? C.onAccent : C.textSoft)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(Tr.isAr ? z.ar : z.en, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, color: z.id == s.tzZone ? C.accent : C.text)),
                              Text(TzZones.offsetText(z.stdMin) + (z.dst ? (Tr.isAr ? ' · فيها صيفي' : ' · summer time') : ''),
                                  textDirection: TextDirection.ltr, style: TextStyle(color: C.muted, fontSize: 11.5)),
                            ]),
                          ),
                          if (z.id == s.tzZone) Icon(Icons.check, color: C.accent),
                        ]),
                      ),
                    ),
                  if (list.isEmpty) Text(_tr('مفيش نتيجة', 'No match'), style: TextStyle(color: C.muted)),
                ]),
              ],
              if (cur != null && cur.dst) ...[
                const SizedBox(height: 12),
                _card([
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_tr('التوقيت الصيفي تلقائي', 'Summer time by itself'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                        Text(
                            cur.id == 'cairo'
                                ? _tr('في مصر بيبدأ آخر جمعة في أبريل ويخلص آخر خميس في أكتوبر. الهاب بيقدّم ويأخّر الساعة لوحده ويبلّغ المشتركات.',
                                    'In Egypt it starts the last Friday of April and ends the last Thursday of October. The hub moves the clock and tells the strips.')
                                : _tr('الهاب بيقدّم ويأخّر الساعة لوحده ويبلّغ المشتركات.', 'The hub moves the clock by itself and tells the strips.'),
                            style: TextStyle(color: C.muted, fontSize: 12, height: 1.5)),
                      ]),
                    ),
                    Switch(value: s.tzZone.isNotEmpty, activeTrackColor: C.accent, onChanged: _busy ? null : _setDst),
                  ]),
                ]),
              ],
              const SizedBox(height: 16),
              Text(_tr('الساعات دلوقتي', 'The clocks now'), style: TextStyle(color: C.muted, fontSize: 12.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              _card([
                Row(children: [
                  Expanded(child: _clock(_tr('الموبايل', 'Phone'), _hm(now, secs: true), '')),
                  const SizedBox(width: 10),
                  Expanded(child: _clock(_tr('الهاب', 'Hub'), s.hubTimeOk ? _hm(hubNow, secs: true) : '—', TzZones.offsetText(s.tzOffsetMin))),
                ]),
                const SizedBox(height: 12),
                for (final st in s.allStrips.where((x) => x.online))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      Icon(Icons.power_outlined, size: 18, color: C.muted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(s.stripName(st), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          Text(
                              st.tackS >= 0
                                  ? _tr('آخر مزامنة ناجحة من ${_ago(st.tackS)}', 'Last confirmed sync ${_ago(st.tackS)} ago')
                                  : st.tsyncS < 0
                                      ? _tr('لسه ما اتبعتلوش الوقت', 'Time not sent yet')
                                      : _tr('آخر إرسال من ${_ago(st.tsyncS)}', 'Last sent ${_ago(st.tsyncS)} ago'),
                              style: TextStyle(color: C.muted, fontSize: 11.5)),
                          if (st.osched.isNotEmpty)
                            Text(_oschedText(st), style: TextStyle(color: C.textSoft, fontSize: 11.5)),
                        ]),
                      ),
                      // did the strip take the time it was sent last
                      if (st.tsyncSt.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (st.tsyncSt == 'ok' ? C.green : st.tsyncSt == 'fail' ? C.danger : C.accent).withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            if (st.tsyncSt == 'wait') SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.6, color: C.accent)),
                            if (st.tsyncSt != 'wait') Icon(st.tsyncSt == 'ok' ? Icons.check_circle : Icons.error_outline, size: 14, color: st.tsyncSt == 'ok' ? C.green : C.danger),
                            const SizedBox(width: 4),
                            Text(st.tsyncSt == 'ok' ? _tr('نجحت', 'Done') : st.tsyncSt == 'fail' ? _tr('ماوصلش رد', 'No answer') : _tr('بيزامن', 'Syncing'),
                                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: st.tsyncSt == 'ok' ? C.green : st.tsyncSt == 'fail' ? C.danger : C.accent)),
                          ]),
                        ),
                    ]),
                  ),
                const SizedBox(height: 8),
                primaryButton(_busy ? _tr('بيزامن…', 'Syncing…') : _tr('زامن دلوقتي', 'Sync now'), _busy
                    ? null
                    : () => _run(() async {
                          await s.syncTimeNow();
                          _snack(_tr('اتبعت الوقت للمشتركات', 'The time was sent to the strips'));
                        }), icon: Icons.sync),
              ]),
              const SizedBox(height: 12),
              Text(_tr('المواعيد المتسجلة جوه المشترك بتشتغل على ساعته هو، حتى لو الهاب فاصل. الهاب بيزامن الساعة بعد كل اتصال وكل ساعة.',
                  'Schedules stored inside the strip run on its own clock, even when the hub is offline. The hub sets the clock after every connection and every hour.'),
                  style: TextStyle(color: C.muted, fontSize: 12, height: 1.6)),
            ]),
          ),
        );
      },
    );
  }

  /// the schedule the strip holds by itself ("386:20:18:30" = on, outlet 2, Tue and Thu, 18:30)
  String _oschedText(Strip st) {
    final p = st.osched.split(':').map((x) => int.tryParse(x) ?? 0).toList();
    if (p.length < 4 || (p[0] >> 8) == 0) return _tr('مفيش ميعاد جوه المشترك', 'No schedule inside the strip');
    final on = (p[0] >> 7) & 1 == 1, n = p[0] & 7;
    final what = on ? _tr('تشغيل', 'on') : _tr('إيقاف', 'off');
    final who = n == 0 ? _tr('المشترك كله', 'whole strip') : s.outletName(st, n);
    return _tr('جوه المشترك: ${fmtTime12(p[2], p[3])} $what · $who · ${daysText(p[1])}', 'In the strip: ${fmtTime12(p[2], p[3])} $what · $who · ${daysText(p[1])}');
  }

  Widget _clock(String label, String time, String sub) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: C.tile, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: C.muted, fontSize: 12, fontWeight: FontWeight.w600)),
          Text(time, textDirection: TextDirection.ltr, style: mono(22, weight: FontWeight.w700)),
          if (sub.isNotEmpty) Text(sub, textDirection: TextDirection.ltr, style: TextStyle(color: C.muted, fontSize: 11)),
        ]),
      );

  String _ago(int secs) {
    if (secs < 90) return _tr('$secs ثانية', '${secs}s');
    final m = secs ~/ 60;
    if (m < 90) return _tr('$m دقيقة', '${m}m');
    return _tr('${m ~/ 60} ساعة', '${m ~/ 60}h');
  }
}
