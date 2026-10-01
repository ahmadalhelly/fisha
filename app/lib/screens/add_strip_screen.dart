import 'dart:async';

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
  if (code == 'join_failed') return t('prov_join');
  if (code == 'no_dial') return t('prov_no_dial');
  if (code == 'still_setup') {
    return _tr('المشترك استلم الإعدادات بس لسه في وضع الإعداد. افصله من الكهربا 10 ثواني ورجّعه، وهو هيتصل بالـ Hub لوحده.',
        'The strip took the settings but is still in setup mode. Unplug it for 10 seconds and plug it back in; it will dial the hub by itself.');
  }
  if (code.startsWith('strip_said:')) return t('prov_said', {'x': code.substring(11)});
  if (code == 'no answer on 30300') return t('prov_said', {'x': code});
  return code.isEmpty ? t('add_timeout') : code;
}

class AddStripScreen extends StatefulWidget {
  final AppState state;
  const AddStripScreen({super.key, required this.state});

  @override
  State<AddStripScreen> createState() => _AddStripScreenState();
}

class _AddStripScreenState extends State<AddStripScreen> {
  AppState get s => widget.state;
  _Step _step = _Step.intro;
  String _error = '';
  bool _sawActive = false;
  DateTime? _startedAt;
  Timer? _tick;
  List<FoundStrip> _found = [];
  FoundStrip? _chosen;

  @override
  void initState() {
    super.initState();
    s.addListener(_onState);
  }

  @override
  void dispose() {
    _tick?.cancel();
    s.removeListener(_onState);
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() => _step = _Step.scanning);
    final r = await s.api('scan');
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _step = _Step.error;
        _error = r.error == 'unknown action' ? t('err_old_fw') : (r.error ?? t('err_failed'));
      });
      return;
    }
    final raw = r.data?['found'];
    final list = <FoundStrip>[];
    if (raw is List) {
      for (final m in raw.whereType<Map<String, dynamic>>()) {
        list.add(FoundStrip('${m['ssid']}', '${m['id']}', (m['rssi'] as num?)?.toInt() ?? -100, m['known'] == true));
      }
    }
    list.sort((a, b) => b.rssi.compareTo(a.rssi));
    setState(() {
      _found = list;
      _step = _Step.pick;
    });
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
    if (_startedAt != null && DateTime.now().difference(_startedAt!) > const Duration(seconds: 180)) {
      _finish(_Step.error, t('add_timeout'));
    }
  }

  void _finish(_Step step, String error) {
    _tick?.cancel();
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
            child: Text('${t('hub_fw')}: ${s.hubFw ?? '—'}',
                textDirection: TextDirection.ltr, style: mono(11, color: C.faint, weight: FontWeight.w500)),
          ),
        ]),
      ),
    );
  }

  Widget _stepper() {
    final idx = switch (_step) {
      _Step.intro || _Step.scanning || _Step.pick => 0,
      _Step.sending || _Step.running => 1,
      _Step.waiting => 2,
      _Step.done => 3,
      _Step.error => -1,
    };
    return Row(children: [
      for (var i = 0; i < 3; i++) ...[
        Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: 6,
            decoration: BoxDecoration(
              color: idx < 0 ? C.danger.withValues(alpha: 0.5) : (i < idx || idx == 3 ? C.accent : (i == idx ? C.tileOnBorder : C.surface2)),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
        if (i < 2) const SizedBox(width: 6),
      ],
    ]);
  }

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
        return _progress(_tr('الـ Hub بيدوّر على مشتركات في وضع الإعداد…', 'The hub is looking for strips in setup mode…'));
      case _Step.pick:
        return _pick();
      case _Step.sending:
        return _progress(t('add_sending'));
      case _Step.running:
        return _progress(t('add_running'));
      case _Step.waiting:
        return _progress(t('add_wait'));
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
