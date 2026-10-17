part of '../strip_card.dart';

// ---------- moving colour on live numbers (header watts / temperature) ----------
/// Colours for the moving gradient on a watts figure, or null when nothing draws power.
List<Color>? loadFlowColors(double watts, double maxW) {
  if (watts <= 0) return null;
  return switch (loadLevel(watts, maxW)) {
    3 => C.dark ? const [Color(0xFFFF5A4E), Color(0xFFFF8A5B), Color(0xFFE5484D)] : const [Color(0xFFE5484D), Color(0xFFF97316), Color(0xFFDC2626)],
    2 => C.dark ? const [Color(0xFFFFB547), Color(0xFFFFD36B), Color(0xFFFF9A3D)] : const [Color(0xFFD97706), Color(0xFFF59E0B), Color(0xFFEA580C)],
    _ => C.dark ? [C.accent, const Color(0xFF38BDF8), const Color(0xFF8B7CFF)] : [C.accent, const Color(0xFF0A84FF), const Color(0xFF7C5CFF)],
  };
}

/// Colours for the moving gradient on a temperature: green < 40, yellow 40, orange 50, red 60+.
List<Color> tempFlowColors(int c) {
  if (c >= 60) return C.dark ? const [Color(0xFFFF5A4E), Color(0xFFFF8A5B), Color(0xFFE5484D)] : const [Color(0xFFE5484D), Color(0xFFF97316), Color(0xFFDC2626)];
  if (c >= 50) return C.dark ? const [Color(0xFFFF9A3D), Color(0xFFFFB547), Color(0xFFFF7F2A)] : const [Color(0xFFEA580C), Color(0xFFF59E0B), Color(0xFFC2410C)];
  if (c >= 40) return C.dark ? const [Color(0xFFF5C542), Color(0xFFFFE07A), Color(0xFFE6B325)] : const [Color(0xFFCA8A04), Color(0xFFEAB308), Color(0xFFA16207)];
  return C.dark ? const [Color(0xFF3DDC97), Color(0xFF5BE3B5), Color(0xFF2EC4A0)] : const [Color(0xFF1E9E5A), Color(0xFF0E9F7E), Color(0xFF13804A)];
}

/// Paints [child] (text) with a gradient that slowly flows sideways; red levels flow faster.
class FlowColor extends StatefulWidget {
  final List<Color>? colors;
  final Widget child;
  const FlowColor({super.key, required this.colors, required this.child});

  @override
  State<FlowColor> createState() => _FlowColorState();
}

class _FlowColorState extends State<FlowColor> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);

  Duration get _period {
    final c = widget.colors;
    final hot = c != null && (c.first == const Color(0xFFFF5A4E) || c.first == const Color(0xFFE5484D));
    return Duration(milliseconds: hot ? 1800 : 4000);
  }

  void _sync() {
    if (widget.colors == null) {
      _c.stop();
    } else if (!_c.isAnimating || _c.duration != _period) {
      _c.duration = _period;
      _c.repeat();
    }
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(FlowColor old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cols = widget.colors;
    if (cols == null) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (r) => LinearGradient(
          colors: [...cols, cols.first],
          tileMode: TileMode.repeated,
          transform: _SlideGradient(_c.value),
        ).createShader(Rect.fromLTWH(0, 0, r.width * 1.6, r.height)),
        child: child,
      ),
    );
  }
}

class _SlideGradient extends GradientTransform {
  final double t;
  const _SlideGradient(this.t);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) => Matrix4.translationValues(bounds.width * t, 0, 0);
}
