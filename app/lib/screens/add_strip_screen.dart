import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/common.dart';

enum _Step { intro, sending, running, waiting, done, error }

String provErrorText(String code) {
  if (code == 'no_ap') return t('prov_no_ap');
  if (code == 'join_failed') return t('prov_join');
  if (code == 'no_dial') return t('prov_no_dial');
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

  Future<void> _start() async {
    _sawActive = false;
    setState(() {
      _step = _Step.sending;
      _error = '';
    });
    final r = await s.startProvision();
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _step = _Step.error;
        _error = provErrorText(r.error ?? '');
      });
      return;
    }
    _sawActive = true; // the hub accepted the request: its state is "queued" now
    _startedAt = DateTime.now();
    setState(() => _step = _Step.running);
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onState());
  }

  void _onState() {
    if (!mounted || (_step != _Step.running && _step != _Step.waiting)) return;
    final st = s.provState;
    if (_sawActive && st == 'error') return _finish(_Step.error, provErrorText(s.provMsg));
    if (_sawActive && st == 'connected') return _finish(_Step.done, '');
    if (st == 'waiting' && _step != _Step.waiting) setState(() => _step = _Step.waiting);
    if (_startedAt != null && DateTime.now().difference(_startedAt!) > const Duration(seconds: 150)) {
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
        ]),
      ),
    );
  }

  Widget _stepper() {
    final idx = switch (_step) {
      _Step.intro => 0,
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
          primaryButton(t('add_start'), s.mode == ConnMode.offline ? null : _start, icon: Icons.wifi_tethering),
          if (s.mode == ConnMode.offline) ...[
            const SizedBox(height: 8),
            Text(t('err_no_conn'), style: TextStyle(color: C.danger, fontSize: 13)),
          ],
        ]);
      case _Step.sending:
        return _progress(t('add_sending'));
      case _Step.running:
        return _progress(t('add_running'));
      case _Step.waiting:
        return _progress(t('add_wait'));
      case _Step.done:
        return _box(Icons.check_circle_outline, C.green, t('add_done_t'), t('add_done_b'),
            [const SizedBox(height: 16), primaryButton(t('add_close'), () => Navigator.of(context).pop())]);
      case _Step.error:
        return _box(Icons.error_outline, C.danger, t('add_error_t'), _error,
            [const SizedBox(height: 16), primaryButton(t('add_retry'), () => setState(() => _step = _Step.intro))]);
    }
  }

  Widget _progress(String text) => _box(Icons.sync, null, text, t('add_tip'), [
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
