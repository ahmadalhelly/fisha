import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../theme.dart';

enum _Step { intro, sending, running, waiting, done, error }

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
  Set<String> _before = {};
  int _countBefore = 0;
  DateTime? _startedAt;
  DateTime? _doneAt;
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
    _before = s.macs;
    _countBefore = _before.length;
    _doneAt = null;
    setState(() {
      _step = _Step.sending;
      _error = '';
    });
    final r = await s.startProvision();
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _step = _Step.error;
        _error = r.error ?? t('err_failed');
      });
      return;
    }
    _startedAt = DateTime.now();
    setState(() => _step = _Step.running);
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onState());
  }

  void _onState() {
    if (!mounted) return;
    if (_step != _Step.running && _step != _Step.waiting) return;
    final now = DateTime.now();

    if (s.provState == 'error') {
      _finish(_Step.error, s.provMsg.isNotEmpty ? s.provMsg : t('add_timeout'));
      return;
    }
    if (s.provState == 'done' && _step == _Step.running) {
      _doneAt = now;
      setState(() => _step = _Step.waiting);
    }
    if (_step == _Step.waiting) {
      final added = s.macs.difference(_before).isNotEmpty;
      // re-provisioning a strip we already knew: it drops and comes back with the same MAC
      final cameBack = _doneAt != null && now.difference(_doneAt!) > const Duration(seconds: 15) && s.macs.length >= _countBefore && _countBefore > 0;
      if (added || cameBack) {
        _finish(_Step.done, '');
        return;
      }
    }
    if (_startedAt != null && now.difference(_startedAt!) > const Duration(seconds: 120)) {
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
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          children: [
            _stepCard(),
          ],
        ),
      ),
    );
  }

  Widget _stepCard() {
    switch (_step) {
      case _Step.intro:
        return _card(
          icon: Icons.touch_app_outlined,
          title: t('add_step1_t'),
          body: t('add_step1_b'),
          extra: [
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(14)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline, size: 18, color: C.muted),
                const SizedBox(width: 8),
                Expanded(child: Text(t('add_tip'), style: TextStyle(color: C.textSoft, fontSize: 13, height: 1.5))),
              ]),
            ),
            const SizedBox(height: 16),
            _primary(t('add_start'), s.mode == ConnMode.offline ? null : _start),
            if (s.mode == ConnMode.offline) ...[
              const SizedBox(height: 8),
              Text(t('err_no_conn'), style: TextStyle(color: C.danger, fontSize: 13)),
            ],
          ],
        );
      case _Step.sending:
        return _progress(t('add_sending'));
      case _Step.running:
        return _progress(t('add_running'));
      case _Step.waiting:
        return _progress(t('add_wait'));
      case _Step.done:
        return _card(
          icon: Icons.check_circle_outline,
          iconColor: C.green,
          title: t('add_done_t'),
          body: t('add_done_b'),
          extra: [const SizedBox(height: 16), _primary(t('add_close'), () => Navigator.of(context).pop())],
        );
      case _Step.error:
        return _card(
          icon: Icons.error_outline,
          iconColor: C.danger,
          title: t('add_error_t'),
          body: _error,
          extra: [
            const SizedBox(height: 16),
            _primary(t('add_retry'), () => setState(() => _step = _Step.intro)),
          ],
        );
    }
  }

  Widget _progress(String text) => _card(
        icon: Icons.sync,
        title: text,
        body: t('add_tip'),
        extra: [
          const SizedBox(height: 16),
          LinearProgressIndicator(color: C.accent, backgroundColor: C.surface2, minHeight: 6, borderRadius: BorderRadius.circular(3)),
        ],
      );

  Widget _card({required IconData icon, Color? iconColor, required String title, required String body, List<Widget> extra = const []}) =>
      Container(
        padding: const EdgeInsets.all(18),
        decoration: cardBox(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
          ],
        ),
      );

  Widget _primary(String label, VoidCallback? onTap) => FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: C.accent,
          foregroundColor: C.onAccent,
          disabledBackgroundColor: C.surface2,
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      );
}
