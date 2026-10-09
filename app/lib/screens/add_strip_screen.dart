import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/common.dart';

String _tr(String ar, String en) => Tr.isAr ? ar : en;

enum _Step { intro, scanning, pick, sending, running, waiting, done, error }

class FoundStrip {
  final String ssid, id;
  final int rssi;
  final bool known;
  FoundStrip(this.ssid, this.id, this.rssi, this.known);
}

String provErrorText(String code) {
  if (code == 'no_ap') return t('prov_no_ap');
  if (code == 'join_failed:auth') {
    return _tr('المشترك رفض باسورد شبكة الإعداد بتاعته. غالباً الفيرموير بتاعه بيستخدم باسورد مختلف.',
        "The strip refused its setup network password. Its firmware likely uses a different one.");
  }
  if (code == 'join_failed:gone') {
    return _tr('شبكة المشترك اختفت وقت الإضافة. افصل أي موبايل أو لابتوب متوصل بيها، وتأكد إن لمبة المشترك لسه بترمش، وجرب تاني.',
        "The strip's network disappeared while joining. Disconnect any phone or laptop on it, check the strip is still blinking, and retry.");
  }
  if (code.startsWith('join_failed')) return '${t('prov_join')} (${code.substring(code.indexOf(':') + 1)})';
  if (code == 'hub_listener_unavailable') return t('prov_listener_unavailable');
  if (code == 'no_dial' || code == 'hub_tcp_no_client') return t('prov_tcp_no_client');
  if (code == 'still_setup') {
    return _tr('المشترك استلم الإعدادات بس لسه في وضع الإعداد. افصله من الكهربا 10 ثواني ورجّعه، وهو هيتصل بالـ Hub لوحده.',
        'The strip took the settings but is still in setup mode. Unplug it for 10 seconds and plug it back in; it will dial the hub by itself.');
  }
  if (code.startsWith('strip_said:')) return t('prov_said', {'x': code.substring(11)});
  if (code.startsWith('no answer on 30300')) return t('prov_said', {'x': code});
  return code.isEmpty ? t('add_timeout') : code;
}

class AddStripScreen extends StatefulWidget {
  final AppState state;
  const AddStripScreen({super.key, required this.state});

  @override
  State<AddStripScreen> createState() => _AddStripScreenState();
}

class _AddStripScreenState extends State<AddStripScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat();
  AppState get s => widget.state;
  _Step _step = _Step.intro;
  String _error = '';
  bool _sawActive = false;
  DateTime? _startedAt;
  Timer? _tick;
  List<FoundStrip> _found = [];
  FoundStrip? _chosen;
  int _scanRun = 0;
  int _scanLeft = 60;

  @override
  void initState() {
    super.initState();
    s.addListener(_onState);
  }

  @override
  void dispose() {
    _sweep.dispose();
    _scanRun++;
    _tick?.cancel();
    s.removeListener(_onState);
    super.dispose();
  }

  /// Keeps asking the hub to scan for up to 60 s: a strip that was just plugged in needs a while
  /// before its setup Wi-Fi shows up, so one short scan usually comes back empty.
  Future<void> _scan() async {
    final run = ++_scanRun;
    final until = DateTime.now().add(const Duration(seconds: 60));
    setState(() {
      _step = _Step.scanning;
      _scanLeft = 60;
    });
    var list = <FoundStrip>[];
    while (mounted && run == _scanRun) {
      final r = await s.api('scan');
      if (!mounted || run != _scanRun) return;
      if (!r.ok) {
        if (r.error == 'unknown action') {
          setState(() {
            _errAt = 1;
            _step = _Step.error;
            _error = t('err_old_fw');
          });
          return;
        }
      } else {
        final raw = r.data?['found'];
        list = <FoundStrip>[];
        if (raw is List) {
          for (final m in raw.whereType<Map<String, dynamic>>()) {
            list.add(FoundStrip('${m['ssid']}', '${m['id']}', (m['rssi'] as num?)?.toInt() ?? -100, m['known'] == true));
          }
        }
        if (list.isNotEmpty) break;
      }
      final left = until.difference(DateTime.now()).inSeconds;
      if (left <= 0) break;
      setState(() => _scanLeft = left);
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    if (!mounted || run != _scanRun) return;
    list.sort((a, b) => b.rssi.compareTo(a.rssi));
    setState(() {
      _found = list;
      _step = _Step.pick;
    });
  }

  void _stopScan() {
    _scanRun++;
    setState(() => _step = _Step.intro);
  }

  Future<void> _start(FoundStrip f) async {
    _chosen = f;
    _sawActive = false;
    setState(() {
      _step = _Step.sending;
      _error = '';
    });
    final r = await s.api('provision', {'ssid': f.ssid});
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _errAt = 2;
        _step = _Step.error;
        _error = provErrorText(r.error ?? '');
      });
      return;
    }
    s.provState = 'queued';
    _sawActive = true;
    _startedAt = DateTime.now();
    setState(() => _step = _Step.running);
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onState());
  }

  void _onState() {
    if (!mounted || (_step != _Step.running && _step != _Step.waiting)) return;
    final st = s.provState;
    if (_sawActive && st == 'error') return _finish(_Step.error, provErrorText(s.provMsg));
    // second guard: only the strip the user picked counts as success
    if (_sawActive && st == 'connected' && (_chosen == null || s.provMsg.toUpperCase().endsWith(_chosen!.id.toUpperCase()))) {
      return _finish(_Step.done, '');
    }
    if (st == 'waiting' && _step != _Step.waiting) setState(() => _step = _Step.waiting);
    if (_step == _Step.waiting) setState(() {});   // countdown ring
    if (_startedAt != null && DateTime.now().difference(_startedAt!) > const Duration(seconds: 180)) {
      _finish(_Step.error, t('add_timeout'));
    }
  }

  void _finish(_Step step, String error) {
    _tick?.cancel();
    if (step == _Step.error) _errAt = _step == _Step.waiting ? 3 : 2;
    setState(() {
      _step = step;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: C.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(t('add_strip'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 24), children: [
          _stepper(),
          const SizedBox(height: 14),
          AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: KeyedSubtree(key: ValueKey(_step), child: _card())),
          const SizedBox(height: 12),
          Center(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '${t('hub_fw')}: ', style: TextStyle(fontSize: 11.5, color: C.faint)),
                // the version reads left to right on its own, the label stays right to left
                TextSpan(text: '\u2066${s.hubFw == null ? '—' : 'v${s.hubFw}'}\u2069', style: mono(11, color: C.faint, weight: FontWeight.w500)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  /// Four named steps; the running one glows, finished ones get a tick.
  Widget _stepper() {
    final idx = switch (_step) {
      _Step.intro => 0,
      _Step.scanning || _Step.pick => 1,
      _Step.sending || _Step.running => 2,
      _Step.waiting => 3,
      _Step.done => 4,
      _Step.error => _errAt,
    };
    final names = [_tr('جهّز', 'Prepare'), _tr('دوّر', 'Search'), _tr('اربط', 'Link'), _tr('اتصل', 'Connect')];
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < 4; i++) ...[
        Expanded(
          child: Column(children: [
            Row(children: [
              Expanded(child: i == 0 ? const SizedBox() : Container(height: 2, color: i <= idx ? C.accent : C.border)),
              _bubble(i, idx),
              Expanded(child: i == 3 ? const SizedBox() : Container(height: 2, color: i < idx ? C.accent : C.border)),
            ]),
            const SizedBox(height: 6),
            Text(names[i],
                style: TextStyle(fontSize: 11.5, color: i == idx ? C.text : C.muted, fontWeight: i == idx ? FontWeight.w700 : FontWeight.w500)),
          ]),
        ),
      ],
    ]);
  }

  int _errAt = 2;

  Widget _bubble(int i, int idx) {
    final done = i < idx;
    final now = i == idx;
    final err = now && _step == _Step.error;
    final color = err ? C.danger : C.accent;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? C.accent : C.surface,
        border: Border.all(color: done || now ? color : C.border, width: 2),
        boxShadow: now ? [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 0, spreadRadius: 5)] : null,
      ),
      child: done
          ? Icon(Icons.check, size: 17, color: C.onAccent)
          : err
              ? Icon(Icons.close, size: 16, color: C.danger)
              : Text('${i + 1}', style: mono(13, color: now ? C.accent : C.faint, weight: FontWeight.w600)),
    );
  }

  /// Countdown ring around a radar sweep: seconds left inside, the ring empties as time runs out.
  Widget _ring(int left, int total) => SizedBox(
        width: 156,
        height: 156,
        child: Stack(alignment: Alignment.center, children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: ClipOval(
              child: Container(
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: C.border)),
                child: RotationTransition(
                  turns: _sweep,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: SweepGradient(colors: [Colors.transparent, Colors.transparent, C.accent.withValues(alpha: 0.35)], stops: const [0, 0.82, 1]),
                    ),
                  ),
                ),
              ),
            ),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(end: total == 0 ? 0 : (left / total).clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 900),
            builder: (context, v, child) => CustomPaint(size: const Size.square(156), painter: _RingPainter(v, C.accent, C.border)),
          ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$left', style: mono(34, color: C.text, weight: FontWeight.w600)),
            Text(_tr('ثانية', 'sec'), style: TextStyle(fontSize: 11, color: C.muted)),
          ]),
        ]),
      );

  Widget _stage(Widget visual, String title, String body, List<Widget> extra) => Container(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
        decoration: cardBox(),
        child: Column(children: [
          visual,
          const SizedBox(height: 10),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(body, textAlign: TextAlign.center, style: TextStyle(color: C.muted, fontSize: 13, height: 1.6)),
          ...extra,
        ]),
      );

  int get _waitLeft => _startedAt == null ? 0 : math.max(0, 180 - DateTime.now().difference(_startedAt!).inSeconds);

  Widget _card() {
    switch (_step) {
      case _Step.intro:
        return _box(Icons.touch_app_outlined, null, t('add_step1_t'), t('add_step1_b'), [
          const SizedBox(height: 12),
          emptyCard(t('add_tip')),
          const SizedBox(height: 16),
          primaryButton(_tr('دوّر على المشتركات', 'Search for strips'), s.mode == ConnMode.offline ? null : _scan, icon: Icons.radar),
          if (s.mode == ConnMode.offline) ...[
            const SizedBox(height: 8),
            Text(t('err_no_conn'), style: TextStyle(color: C.danger, fontSize: 13)),
          ],
        ]);
      case _Step.scanning:
        return _stage(_ring(_scanLeft, 60), _tr('بيدوّر على مشتركات', 'Looking for strips'),
            _tr('أول ما يلاقي مشترك في وضع الإعداد هيقف ويوريهولك.', 'It stops as soon as it finds a strip in setup mode.'), [
          const SizedBox(height: 8),
          TextButton(onPressed: _stopScan, child: Text(t('cancel'), style: TextStyle(color: C.muted))),
        ]);
      case _Step.pick:
        return _pick();
      case _Step.sending:
        return _progress(t('add_sending'));
      case _Step.running:
        return _stage(
            SizedBox(width: 44, height: 44, child: CircularProgressIndicator(color: C.accent, strokeWidth: 3)),
            t('add_running'),
            _tr('الـ Hub بيفصل عن شبكة البيت ثواني ويرجع لوحده، فالتطبيق ممكن يبان فاصل شوية.',
                'The hub leaves the home Wi-Fi for a few seconds and comes back by itself, so the app may look offline briefly.'),
            [
              const SizedBox(height: 12),
              for (final line in [
                _tr('يدخل شبكة المشترك', 'Joins the strip\'s network'),
                _tr('يبعتله شبكة البيت', 'Sends it the home Wi-Fi'),
                _tr('يعمله ريستارت', 'Restarts it'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    Icon(Icons.circle, size: 6, color: C.faint),
                    const SizedBox(width: 10),
                    Text(line, style: TextStyle(fontSize: 13, color: C.textSoft)),
                  ]),
                ),
              if (_chosen != null) Text('…${_chosen!.id}', textDirection: TextDirection.ltr, style: mono(12, color: C.faint)),
            ]);
      case _Step.waiting:
        return _stage(_ring(_waitLeft, 180), t('add_wait'),
            _tr('المشترك بيعمل ريستارت ويدخل على شبكة البيت.', 'The strip restarts and joins the home Wi-Fi.'), [
          if (_chosen != null) ...[const SizedBox(height: 6), Text('…${_chosen!.id}', textDirection: TextDirection.ltr, style: mono(12, color: C.faint))],
        ]);
      case _Step.done:
        final mac = s.provMsg;
        return _box(Icons.check_circle_outline, C.green, t('add_done_t'), t('add_done_b'), [
          if (mac.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('MAC: $mac', textDirection: TextDirection.ltr, style: mono(13, color: C.textSoft, weight: FontWeight.w500)),
          ],
          const SizedBox(height: 16),
          primaryButton(t('add_close'), () => Navigator.of(context).pop()),
        ]);
      case _Step.error:
        return _box(Icons.error_outline, C.danger, t('add_error_t'), _error,
            [const SizedBox(height: 16), primaryButton(t('add_retry'), () => setState(() => _step = _Step.intro))]);
    }
  }

  Widget _pick() {
    if (_found.isEmpty) {
      return _box(Icons.wifi_find, null, _tr('مالقيتش مشترك في وضع الإعداد', 'No strip in setup mode found'), t('prov_no_ap'), [
        const SizedBox(height: 16),
        primaryButton(_tr('دوّر تاني', 'Search again'), _scan, icon: Icons.refresh),
      ]);
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardBox(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(_tr('اختار المشترك', 'Pick a strip'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(_tr('الرقم هو آخر 7 خانات من الـ MAC، ومكتوب على الملصق تحت المشترك.', 'The ID is the last 7 digits of the MAC, printed on the label under the strip.'),
            style: TextStyle(color: C.muted, fontSize: 12, height: 1.5)),
        const SizedBox(height: 12),
        for (final f in _found)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: C.surface2,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _start(f),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    Icon(Icons.power_outlined, color: C.accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('…${f.id}', textDirection: TextDirection.ltr, style: mono(16)),
                        Text(f.ssid, textDirection: TextDirection.ltr, style: TextStyle(color: C.muted, fontSize: 11)),
                        if (f.known)
                          Text(_tr('متضاف بالفعل — هيتظبط من جديد', 'Already added — will be set up again'),
                              style: TextStyle(color: C.accent, fontSize: 11)),
                      ]),
                    ),
                    Text('${f.rssi} dBm', textDirection: TextDirection.ltr, style: mono(12, color: C.textSoft, weight: FontWeight.w500)),
                    const SizedBox(width: 6),
                    Icon(Icons.chevron_right, color: C.faint),
                  ]),
                ),
              ),
            ),
          ),
        const SizedBox(height: 4),
        TextButton.icon(onPressed: _scan, icon: const Icon(Icons.refresh), label: Text(_tr('دوّر تاني', 'Search again'))),
      ]),
    );
  }

  Widget _progress(String text) => _box(Icons.sync, null, text, _chosen == null ? t('add_tip') : '…${_chosen!.id}  ·  ${t('add_tip')}', [
        const SizedBox(height: 16),
        LinearProgressIndicator(color: C.accent, backgroundColor: C.surface2, minHeight: 6, borderRadius: BorderRadius.circular(3)),
      ]);

  Widget _box(IconData icon, Color? iconColor, String title, String body, List<Widget> extra) => Container(
        padding: const EdgeInsets.all(18),
        decoration: cardBox(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: C.accentBg, borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: iconColor ?? C.accent),
            ),
          ),
          const SizedBox(height: 14),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(body, style: TextStyle(color: C.textSoft, height: 1.6)),
          ...extra,
        ]),
      );
}

class _RingPainter extends CustomPainter {
  final double v;
  final Color color, track;
  _RingPainter(this.v, this.color, this.track);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(5, 5, size.width - 10, size.height - 10);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, p..color = track);
    if (v > 0) canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * v, false, p..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.v != v || old.color != color || old.track != track;
}
