part of '../energy_screen.dart';

class _StackDay {
  final int date; // yyyymmdd
  final bool missing;
  final int peakW;
  final List<int> parts; // Wh per stacked part (strip or outlet)
  const _StackDay(this.date, this.missing, this.peakW, this.parts);
  int get wh => parts.fold(0, (a, b) => a + b);
}

String _dayLabel(int k) {
  final d = DateTime(k ~/ 10000, (k ~/ 100) % 100, k % 100);
  const ar = ['الاتنين', 'التلات', 'الأربع', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
  const en = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${Tr.isAr ? ar[d.weekday - 1] : en[d.weekday - 1]} ${d.day}/${d.month}';
}

/// 2.0.15: one bar per day, stacked by strip (or by outlet when a strip is picked), a dashed average line, an outlined
/// slot for a day with no record, and a detail box with the day's use and cost split by part.
class _StackBars extends StatefulWidget {
  final List<_StackDay> days; // oldest first
  final List<String> labels;
  final List<Color> colors;
  final double tariff;
  const _StackBars({super.key, required this.days, required this.labels, required this.colors, required this.tariff});

  @override
  State<_StackBars> createState() => _StackBarsState();
}

class _StackBarsState extends State<_StackBars> {
  int? _sel; // index into days

  static const _padL = 30.0, _labelH = 18.0;

  void _tap(Offset p, double w) {
    final n = widget.days.length;
    if (n == 0 || p.dx < _padL) return;
    final i = ((p.dx - _padL) / ((w - _padL) / n)).floor().clamp(0, n - 1);
    setState(() => _sel = _sel == i ? null : i);
  }

  @override
  Widget build(BuildContext context) {
    final days = widget.days;
    if (days.isEmpty) return const SizedBox.shrink();
    final anyMissing = days.any((d) => d.missing);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 180,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: LayoutBuilder(
            builder: (_, c) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _tap(d.localPosition, c.maxWidth),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 550),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => CustomPaint(
                  size: Size(c.maxWidth, c.maxHeight),
                  painter: _StackPainter(days, widget.colors, _sel, v, _padL, _labelH),
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 10),
      if (widget.labels.length > 1 || anyMissing)
        Wrap(spacing: 12, runSpacing: 6, children: [
          if (widget.labels.length > 1)
            for (var i = 0; i < widget.labels.length; i++) _legend(widget.colors[i], widget.labels[i]),
          if (anyMissing) _legend(null, Tr.isAr ? 'مفيش بيانات' : 'No data'),
        ]),
      const SizedBox(height: 10),
      _tip(),
    ]);
  }

  Widget _legend(Color? c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: c == null ? 14 : 9,
          height: 9,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(3),
            border: c == null ? Border.all(color: C.muted.withValues(alpha: .6)) : null,
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 11.5, color: C.textSoft)),
      ]);

  Widget _tip() {
    final box = BoxDecoration(color: C.surface2.withValues(alpha: .8), borderRadius: BorderRadius.circular(14));
    final i = _sel;
    if (i == null || i >= widget.days.length) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: box,
        child: Text(Tr.isAr ? 'دوس على يوم تشوف استهلاكه وتكلفته.' : 'Tap a day to see its use and cost.', style: TextStyle(color: C.muted, fontSize: 12)),
      );
    }
    final d = widget.days[i];
    final egp = t('egp');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: box,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 4, children: [
          Text(_dayLabel(d.date), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          if (d.missing)
            Text(Tr.isAr ? 'الـ Hub ماسجلش اليوم ده، ومش محسوب في المتوسط.' : 'The hub has no record for this day; it is left out of the average.',
                style: TextStyle(color: C.muted, fontSize: 12))
          else ...[
            valUnit((d.wh / 1000).toStringAsFixed(2), 'kWh', size: 12.5, color: C.accent),
            valUnit((d.wh / 1000 * widget.tariff).toStringAsFixed(2), egp, size: 12.5),
            if (d.peakW > 0) valUnit('${d.peakW}', 'W ⚡', size: 12, color: C.textSoft, weight: FontWeight.w500),
          ],
        ]),
        if (!d.missing && d.parts.length > 1) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 14, runSpacing: 6, children: [
            for (var k = 0; k < d.parts.length; k++)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: widget.colors[k], borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 5),
                Text('${widget.labels[k]} ', style: TextStyle(fontSize: 11.5, color: C.textSoft)),
                valUnit((d.parts[k] / 1000 * widget.tariff).toStringAsFixed(2), egp, size: 11.5, color: C.text, weight: FontWeight.w500),
              ]),
          ]),
        ],
      ]),
    );
  }
}

class _StackPainter extends CustomPainter {
  final List<_StackDay> days;
  final List<Color> colors;
  final int? sel;
  final double grow; // 0..1 entry animation
  final double padL, labelH;
  _StackPainter(this.days, this.colors, this.sel, this.grow, this.padL, this.labelH);

  void _text(Canvas c, String s, Offset at, Color color, {double size = 9.5, TextAlign align = TextAlign.center, bool ar = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: ar ? TextStyle(color: color, fontSize: size) : mono(size, color: color)),
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
    )..layout();
    final dx = align == TextAlign.center ? at.dx - tp.width / 2 : (align == TextAlign.right ? at.dx - tp.width : at.dx);
    tp.paint(c, Offset(dx, at.dy));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = days.length;
    final h = size.height - labelH;
    final ok = days.where((d) => !d.missing).toList();
    final top = ok.isEmpty ? 1 : ok.map((d) => d.wh).reduce(math.max);
    final max = math.max(1, top) * 1.12;
    final avg = ok.isEmpty ? 0.0 : ok.fold<int>(0, (a, d) => a + d.wh) / ok.length;
    double y(num v) => h - v / max * h;

    // grid at half and full of the top value, labelled in kWh
    final grid = Paint()
      ..color = C.border
      ..strokeWidth = 1;
    for (final f in [.5, 1.0]) {
      final v = top * f;
      canvas.drawLine(Offset(padL, y(v)), Offset(size.width, y(v)), grid);
      _text(canvas, (v / 1000).toStringAsFixed(v >= 10000 ? 1 : 2), Offset(0, y(v) - 6), C.faint, size: 9, align: TextAlign.left);
    }

    final bw = (size.width - padL) / n;
    final gap = math.min(6.0, bw * .28);
    final w = math.max(1.5, bw - gap);
    final r = Radius.circular(math.min(4.0, w / 3));
    final every = n <= 7 ? 1 : (n <= 14 ? 2 : (n <= 31 ? 5 : 15));
    for (var i = 0; i < n; i++) {
      final d = days[i];
      final x = padL + i * bw + gap / 2;
      final dim = sel != null && sel != i;
      if (d.missing) {
        final rect = RRect.fromRectAndCorners(Rect.fromLTWH(x, h * .45, w, h * .55), topLeft: r, topRight: r);
        canvas.drawRRect(
            rect,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1
              ..color = C.muted.withValues(alpha: sel == i ? .9 : .45));
      } else {
        var acc = 0;
        final last = d.parts.lastIndexWhere((p) => p > 0);
        for (var k = 0; k < d.parts.length; k++) {
          final v = d.parts[k];
          if (v <= 0) continue;
          final y1 = y((acc + v) * grow), y0 = y(acc * grow);
          final gapPx = d.parts.length > 1 && k != last ? 1.0 : 0.0;
          final rect = Rect.fromLTRB(x, y1, x + w, math.max(y1, y0 - gapPx));
          canvas.drawRRect(
            k == last ? RRect.fromRectAndCorners(rect, topLeft: r, topRight: r) : RRect.fromRectAndRadius(rect, const Radius.circular(1)),
            Paint()..color = colors[k].withValues(alpha: dim ? .32 : .95),
          );
          acc += v;
        }
      }
      if ((n - 1 - i) % every == 0) {
        _text(canvas, '${d.date % 100}', Offset(x + w / 2, h + 5), sel == i ? C.text : C.muted);
      }
    }

    // dashed average line with its value
    if (avg > 0) {
      final ay = y(avg * grow);
      final dash = Paint()
        ..color = C.warn
        ..strokeWidth = 1.2;
      for (var x = padL; x < size.width; x += 8) {
        canvas.drawLine(Offset(x, ay), Offset(math.min(x + 4, size.width), ay), dash);
      }
      _text(canvas, '${Tr.isAr ? 'المتوسط' : 'avg'} ${(avg / 1000).toStringAsFixed(2)}', Offset(padL + 2, ay - 14), C.warn,
          size: 9.5, align: TextAlign.left, ar: Tr.isAr);
    }
  }

  @override
  bool shouldRepaint(covariant _StackPainter o) => o.days != days || o.sel != sel || o.grow != grow || o.colors != colors;
}
