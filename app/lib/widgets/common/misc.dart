part of '../common.dart';

/// The scenarios glyph: eight short rays around an empty centre.
class ScenesIcon extends StatelessWidget {
  final double size;
  final Color? color;
  const ScenesIcon({super.key, this.size = 22, this.color});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _RaysPainter(color ?? IconTheme.of(context).color ?? C.accent));
}

class _RaysPainter extends CustomPainter {
  final Color color;
  _RaysPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final p = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.09
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4 - math.pi / 2;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + d * (r * 0.38), c + d * (r * 0.82), p);
    }
  }

  @override
  bool shouldRepaint(_RaysPainter old) => old.color != color;
}

/// Scrolls itself into view and glows twice when [active]: a rule opened from an outlet's menu.
class FocusFlash extends StatefulWidget {
  final bool active;
  final double radius;
  final Widget child;
  const FocusFlash({super.key, required this.active, required this.child, this.radius = 20});

  @override
  State<FocusFlash> createState() => _FocusFlashState();
}

class _FocusFlashState extends State<FocusFlash> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(FocusFlash old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _start();
  }

  void _start() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await Scrollable.ensureVisible(context, alignment: 0.3, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
      if (mounted) _c.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) {
          final glow = _c.isAnimating ? math.sin(_c.value * math.pi * 4).abs() : 0.0;
          return DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              border: Border.all(color: C.accent.withValues(alpha: glow), width: 2.5),
            ),
            child: child,
          );
        },
      );
}

/// Role colours used on chips and avatar rings: 0 view · 1 control · 2 admin · 3 owner.
Color roleColor(int r) => switch (r) { 0 => C.blue, 1 => C.warn, 2 => const Color(0xFFA78BFA), _ => C.accent };

String roleName(int r) => switch (r) {
      0 => Tr.isAr ? 'مشاهدة' : 'View',
      1 => Tr.isAr ? 'تشغيل وتحكم' : 'Control',
      2 => Tr.isAr ? 'إدارة كاملة' : 'Full admin',
      _ => Tr.isAr ? 'المالك' : 'Owner',
    };

Widget roleChip(int r) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: roleColor(r).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(99)),
      child: Text(roleName(r), style: TextStyle(color: roleColor(r), fontSize: 11, fontWeight: FontWeight.w700)),
    );

/// A person's Google photo in a ring of their role colour; falls back to their initial when there is no photo.
class Avatar extends StatelessWidget {
  final String photo, name;
  final double size;
  final Color? ring;
  const Avatar({super.key, required this.photo, required this.name, this.size = 42, this.ring});

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    final fallback = Container(
      color: C.surface2,
      alignment: Alignment.center,
      child: Text(initial, style: TextStyle(color: ring ?? C.accent, fontWeight: FontWeight.w700, fontSize: size * 0.4)),
    );
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring ?? C.accent, width: 2)),
      child: ClipOval(
        child: photo.startsWith('https://')
            ? Image.network(photo, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback)
            : fallback,
      ),
    );
  }
}
