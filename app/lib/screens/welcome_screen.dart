import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'account_screen.dart';

/// First screen: Google account or no account, plus joining with an invite code.
class WelcomeScreen extends StatefulWidget {
  final AppState state;
  const WelcomeScreen({super.key, required this.state});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with TickerProviderStateMixin {
  AppState get s => widget.state;
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  late final AnimationController _flow = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _intro.forward();
    _flow.repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _intro.value = 1;
      _flow.stop();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _flow.dispose();
    super.dispose();
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _google() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final err = await s.googleSignIn();
      if (err != null) {
        _snack(err);
        return;
      }
      if (await s.googleHasData() && mounted) {
        if (await confirmDialog(context, t('g_found_t'), t('g_found_b'), ok: t('g_restore'))) {
          _snack(await s.restoreFromGoogle() ?? t('g_restored'));
          return;
        }
      }
      _snack(await s.syncNow() ?? t('g_synced'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _local() async {
    if (_busy) return;
    setState(() => _busy = true);
    await s.useLocalAccount();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final intro = CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic);
    return Scaffold(
      backgroundColor: C.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // logo: a socket face whose ring is drawn in, then current runs along the wire under it
                Center(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_intro, _flow]),
                    builder: (_, __) => CustomPaint(
                      size: const Size(112, 112),
                      painter: _SocketLogo(progress: intro.value, glow: 0.5 + 0.5 * math.sin(_flow.value * 2 * math.pi)),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: AnimatedBuilder(
                    animation: _flow,
                    builder: (_, __) => CustomPaint(size: const Size(150, 10), painter: _Wire(t: _flow.value)),
                  ),
                ),
                const SizedBox(height: 14),
                FadeTransition(
                  opacity: intro,
                  child: Column(children: [
                    Text('Fisha',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 44, fontWeight: FontWeight.w700, letterSpacing: -1.2, height: 1, color: C.text)),
                    const SizedBox(height: 6),
                    Text('فيشة', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: C.muted, height: 1.2)),
                  ]),
                ),
                const SizedBox(height: 26),
                SlideTransition(
                  position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(intro),
                  child: FadeTransition(opacity: intro, child: _card()),
                ),
                const SizedBox(height: 18),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.lock_outline, size: 15, color: C.accent),
                  const SizedBox(width: 6),
                  Flexible(child: Text(t('wel_secure'), textAlign: TextAlign.center, style: TextStyle(color: C.muted, fontSize: 12))),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card() => Container(
        clipBehavior: Clip.antiAlias,
        decoration: cardBox(radius: 26),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // the card's top edge carries the same current as the wire
          AnimatedBuilder(
            animation: _flow,
            builder: (_, __) => CustomPaint(size: const Size(double.infinity, 3), painter: _EdgeCurrent(t: _flow.value)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(t('wel_title'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(t('wel_sub'), style: TextStyle(color: C.textSoft, fontSize: 14, height: 1.55)),
              const SizedBox(height: 20),
              _googleButton(),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: Divider(color: C.border)),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(t('wel_or'), style: TextStyle(color: C.faint, fontSize: 12))),
                Expanded(child: Divider(color: C.border)),
              ]),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _busy ? null : _local,
                icon: const Icon(Icons.phone_android, size: 20),
                label: Text(t('wel_local'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: C.text,
                  side: BorderSide(color: C.border),
                  minimumSize: const Size(0, 54),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
              ),
              const SizedBox(height: 6),
              Text(t('wel_local_sub'), textAlign: TextAlign.center, style: TextStyle(color: C.muted, fontSize: 12, height: 1.5)),
              const SizedBox(height: 18),
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _busy ? null : () => joinWithInviteDialog(context, s),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: C.accentBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.tileOnBorder.withValues(alpha: 0.5))),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.group_add_outlined, color: C.accent, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t('wel_invite'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        const SizedBox(height: 3),
                        Text(t('wel_invite_sub'), style: TextStyle(color: C.textSoft, fontSize: 12, height: 1.5)),
                      ]),
                    ),
                  ]),
                ),
              ),
            ]),
          ),
        ]),
      );

  Widget _googleButton() => Material(
        color: C.dark ? const Color(0xFFF7F9FC) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: C.dark ? Colors.transparent : C.border)),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: _busy ? null : _google,
          child: SizedBox(
            height: 56,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (_busy)
                const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Color(0xFF4285F4)))
              else
                CustomPaint(size: const Size(22, 22), painter: _GoogleG()),
              const SizedBox(width: 12),
              Text(t('wel_google'), style: const TextStyle(color: Color(0xFF1F1F1F), fontWeight: FontWeight.w600, fontSize: 16)),
            ]),
          ),
        ),
      );
}

/// Socket face: ring (drawn in by [progress]), two pin holes and the earth clips.
class _SocketLogo extends CustomPainter {
  final double progress, glow;
  _SocketLogo({required this.progress, required this.glow});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 6;
    canvas.drawCircle(c, r + 2, Paint()
      ..color = C.accent.withValues(alpha: 0.10 + 0.12 * glow * progress)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
    canvas.drawCircle(c, r, Paint()..color = C.surface);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, 2 * math.pi * progress, false,
        Paint()
          ..color = C.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round);
    final a = Curves.easeOut.transform(((progress - 0.45) / 0.55).clamp(0.0, 1.0));
    final face = Paint()..color = C.accent.withValues(alpha: a);
    final hole = r * 0.15;
    canvas.drawCircle(c + Offset(-r * 0.36, 0), hole, face);
    canvas.drawCircle(c + Offset(r * 0.36, 0), hole, face);
    final clip = Paint()
      ..color = C.accent.withValues(alpha: a * 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c + Offset(-r * 0.14, -r * 0.62), c + Offset(r * 0.14, -r * 0.62), clip);
    canvas.drawLine(c + Offset(-r * 0.14, r * 0.62), c + Offset(r * 0.14, r * 0.62), clip);
  }

  @override
  bool shouldRepaint(_SocketLogo o) => o.progress != progress || o.glow != glow;
}

/// A short wire with a pulse of current travelling along it.
class _Wire extends CustomPainter {
  final double t;
  _Wire({required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), Paint()
      ..color = C.border
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round);
    final x = size.width * t;
    final seg = size.width * 0.28;
    final rect = Rect.fromLTWH(x - seg, 0, seg, size.height);
    canvas.drawLine(Offset(math.max(0, x - seg), y), Offset(math.min(size.width, x), y), Paint()
      ..shader = LinearGradient(colors: [C.accent.withValues(alpha: 0), C.accent]).createShader(rect)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round);
    if (x <= size.width) {
      canvas.drawCircle(Offset(x, y), 3.2, Paint()
        ..color = C.accent
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5));
    }
  }

  @override
  bool shouldRepaint(_Wire o) => o.t != t;
}

class _EdgeCurrent extends CustomPainter {
  final double t;
  _EdgeCurrent({required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = C.border.withValues(alpha: 0.6));
    final w = size.width * 0.4;
    final x = (size.width + w) * t - w;
    final rect = Rect.fromLTWH(x, 0, w, size.height);
    canvas.drawRect(rect, Paint()
      ..shader = LinearGradient(colors: [C.accent.withValues(alpha: 0), C.accent, C.accent.withValues(alpha: 0)]).createShader(rect));
  }

  @override
  bool shouldRepaint(_EdgeCurrent o) => o.t != t;
}

/// The four-colour Google "G".
class _GoogleG extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final w = s * 0.2;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: (s - w) / 2);
    Paint p(int c) => Paint()
      ..color = Color(c)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w;
    double d(double deg) => deg * math.pi / 180;
    canvas.drawArc(rect, d(-40), d(-100), false, p(0xFFEA4335)); // red, top
    canvas.drawArc(rect, d(-140), d(-85), false, p(0xFFFBBC05)); // yellow, left
    canvas.drawArc(rect, d(135), d(-90), false, p(0xFF34A853)); // green, bottom
    canvas.drawArc(rect, d(45), d(-45), false, p(0xFF4285F4)); // blue, lower right
    canvas.drawRect(Rect.fromLTWH(s / 2, s / 2 - w / 2, s / 2 - w * 0.15, w), Paint()..color = const Color(0xFF4285F4));
  }

  @override
  bool shouldRepaint(_GoogleG o) => false;
}
