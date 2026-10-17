part of '../common.dart';

// ---------- live indicators ----------
/// A small dot that breathes while data is flowing.
class PulseDot extends StatefulWidget {
  final Color color;
  final bool active;
  const PulseDot({super.key, required this.color, this.active = true});

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 16,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final v = widget.active ? _c.value : 0.0;
          return Stack(alignment: Alignment.center, children: [
            Container(
              width: 8 + 8 * v,
              height: 8 + 8 * v,
              decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withValues(alpha: 0.35 * (1 - v))),
            ),
            Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color)),
          ]);
        },
      ),
    );
  }
}

/// A gentle moving wave whose height follows the current load.
class LiveWave extends StatefulWidget {
  final double level; // 0..1
  final Color color;
  const LiveWave({super.key, required this.level, required this.color});

  @override
  State<LiveWave> createState() => _LiveWaveState();
}

class _LiveWaveState extends State<LiveWave> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: widget.level.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (_, level, __) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(
          size: const Size(double.infinity, 34),
          painter: _WavePainter(phase: _c.value * 2 * math.pi, level: level, color: widget.color),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final double phase, level;
  final Color color;
  _WavePainter({required this.phase, required this.level, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final amp = 2.5 + 9 * level;
    for (var layer = 0; layer < 2; layer++) {
      final path = Path()..moveTo(0, size.height);
      for (double x = 0; x <= size.width; x += 4) {
        final y = size.height * 0.55 -
            amp * math.sin((x / size.width) * 2 * math.pi * (1.5 + layer * 0.6) + phase * (layer == 0 ? 1 : -1.3));
        path.lineTo(x, y);
      }
      path
        ..lineTo(size.width, size.height)
        ..close();
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: layer == 0 ? 0.22 : 0.12));
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => old.phase != phase || old.level != level || old.color != color;
}

/// Numbers that slide to their new value instead of jumping.
class AnimatedNumber extends StatelessWidget {
  final double value;
  final int decimals;
  final TextStyle style;
  const AnimatedNumber({super.key, required this.value, required this.style, this.decimals = 1});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => Text(v.toStringAsFixed(decimals), textDirection: TextDirection.ltr, style: style),
    );
  }
}

class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 56});

  @override
  Widget build(BuildContext context) => Image.asset('assets/brand/icon_fg.png', width: size, height: size);
}

class BoltPainter extends CustomPainter {
  final double v;
  const BoltPainter(this.v);

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 1024, sc = 0.95, cx = 512.0, y0 = 512 - 30 - 60 * sc;
    Offset pt(double dx, double dy) => Offset((cx + dx * sc) * k, (y0 + dy * sc) * k);
    final path = Path()
      ..moveTo(pt(18, 38).dx, pt(18, 38).dy)
      ..lineTo(pt(-52, 140).dx, pt(-52, 140).dy)
      ..lineTo(pt(-6, 140).dx, pt(-6, 140).dy)
      ..lineTo(pt(-24, 214).dx, pt(-24, 214).dy)
      ..lineTo(pt(54, 104).dx, pt(54, 104).dy)
      ..lineTo(pt(8, 104).dx, pt(8, 104).dy)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.85 * v)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5));
    canvas.drawPath(path, Paint()..color = const Color(0xFFEFFFF9).withValues(alpha: v));
  }

  @override
  bool shouldRepaint(BoltPainter old) => old.v != v;
}

/// The splash logo, looping softly: a mint glow breathes behind the plug and the bolt flickers once per cycle.
/// Static when the system asks for reduced motion.
class LoopLogo extends StatefulWidget {
  final double size;
  const LoopLogo({super.key, this.size = 32});

  @override
  State<LoopLogo> createState() => _LoopLogoState();
}

class _LoopLogoState extends State<LoopLogo> with SingleTickerProviderStateMixin {
  static const _mint = Color(0xFF2EE6B0);
  static const _ms = 4200;
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: _ms));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!MediaQuery.of(context).disableAnimations) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sz = widget.size;
    if (!_c.isAnimating) return BrandMark(size: sz);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final ms = _c.value * _ms;
          final glow = 0.5 + 0.5 * math.sin(_c.value * 2 * math.pi);
          final f = ms >= 300 && ms <= 550 ? (ms - 300) / 250 : 0.0; // the same flicker as the splash
          final bolt = f == 0 ? 0.0 : (f < .3 ? f / .3 : f < .45 ? .35 : f < .65 ? 1.0 : (1 - f) / .35);
          return SizedBox(
            width: sz,
            height: sz,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned(
                left: -sz * 0.4,
                top: -sz * 0.4,
                width: sz * 1.8,
                height: sz * 1.8,
                child: Opacity(
                  opacity: 0.35 + 0.55 * glow,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [_mint.withValues(alpha: 0.22), _mint.withValues(alpha: 0.06), _mint.withValues(alpha: 0)], stops: const [0, .45, 1]),
                    ),
                  ),
                ),
              ),
              Positioned.fill(child: BrandMark(size: sz)),
              if (bolt > 0) Positioned.fill(child: CustomPaint(painter: BoltPainter(bolt))),
            ]),
          );
        },
      ),
    );
  }
}
