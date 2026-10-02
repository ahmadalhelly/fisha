import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../i18n.dart';
import '../theme.dart';

// ---------- formatting ----------
String fmtDuration(int seconds) {
  if (seconds < 60) return '$seconds ${t('sec')}';
  if (seconds < 3600) {
    final m = seconds ~/ 60, s = seconds % 60;
    return s == 0 ? '$m ${t('min')}' : '$m:${s.toString().padLeft(2, '0')} ${t('min')}';
  }
  final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60;
  return m == 0 ? '$h ${t('hour')}' : '$h ${t('hour')} $m ${t('min')}';
}

String two(int v) => v.toString().padLeft(2, '0');

// ---------- dialogs ----------
Future<String?> askName(BuildContext context, String title, String current) {
  final ctrl = TextEditingController(text: current);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: C.surface,
      title: Text(title, style: const TextStyle(fontSize: 18)),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLength: 32,
        textInputAction: TextInputAction.done,
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'), style: TextStyle(color: C.muted))),
        TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(t('save'))),
      ],
    ),
  );
}

Future<bool> confirmDialog(BuildContext context, String title, String body, {String? ok, bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: C.surface,
      title: Text(title, style: const TextStyle(fontSize: 18)),
      content: Text(body, style: TextStyle(color: C.textSoft, height: 1.5)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'), style: TextStyle(color: C.muted))),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok ?? t('confirm'), style: TextStyle(color: danger ? C.danger : C.accent, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return r == true;
}

/// A bottom sheet that lets the user pick one value from a list.
Future<T?> pickOne<T>(BuildContext context, String title, List<MapEntry<T, String>> items, T? current) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          for (final e in items)
            ListTile(
              title: Text(e.value),
              trailing: e.key == current ? Icon(Icons.check, color: C.accent) : null,
              onTap: () => Navigator.pop(ctx, e.key),
            ),
        ],
      ),
    ),
  );
}

// ---------- building blocks ----------
Widget section(String title, List<Widget> children, {Widget? trailing}) => Container(
      padding: const EdgeInsets.all(16),
      decoration: cardBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: Text(title, style: TextStyle(fontSize: 13, color: C.muted, fontWeight: FontWeight.w600))),
            if (trailing != null) trailing,
          ]),
          const SizedBox(height: 12),
          for (final c in children) Padding(padding: const EdgeInsets.only(bottom: 10), child: c),
        ],
      ),
    );

class Segmented<T> extends StatelessWidget {
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;
  const Segmented({super.key, required this.value, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          for (final e in items.entries)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(11),
                onTap: () => onChanged(e.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: e.key == value ? C.accentBg : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: e.key == value ? C.tileOnBorder : Colors.transparent),
                  ),
                  child: Text(e.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: e.key == value ? FontWeight.w600 : FontWeight.w400,
                        color: e.key == value ? C.accent : C.textSoft,
                      )),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Widget primaryButton(String label, VoidCallback? onTap, {IconData? icon}) => FilledButton.icon(
      onPressed: onTap,
      icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 20),
      style: FilledButton.styleFrom(
        backgroundColor: C.accent,
        foregroundColor: C.onAccent,
        disabledBackgroundColor: C.surface2,
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
    );

Widget emptyCard(String text, {IconData icon = Icons.info_outline}) => Container(
      padding: const EdgeInsets.all(18),
      decoration: cardBox(),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: C.muted),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: TextStyle(color: C.textSoft, height: 1.6))),
      ]),
    );

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

// ---------- duration picker: hours / minutes / seconds drop-downs ----------
/// Three drop-downs (h, m, s). [value] and [onChanged] are in seconds.
class DurationPicker extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final bool showHours, showSeconds;
  final int maxHours;
  const DurationPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.showHours = true,
    this.showSeconds = true,
    this.maxHours = 23,
  });

  @override
  Widget build(BuildContext context) {
    final h = value ~/ 3600, m = (value % 3600) ~/ 60, sec = value % 60;
    Widget box(String label, int v, int max, ValueChanged<int> set) => Expanded(
          child: InputDecorator(
            decoration: InputDecoration(labelText: label, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: v.clamp(0, max),
                isExpanded: true,
                menuMaxHeight: 320,
                dropdownColor: C.surface2,
                items: [for (var i = 0; i <= max; i++) DropdownMenuItem(value: i, child: Text(two(i), textDirection: TextDirection.ltr, style: mono(16)))],
                onChanged: (x) => set(x ?? 0),
              ),
            ),
          ),
        );
    return Row(children: [
      if (showHours) ...[box(t('dur_h'), h, maxHours, (x) => onChanged(x * 3600 + m * 60 + sec)), const SizedBox(width: 8)],
      box(t('dur_m'), m, 59, (x) => onChanged(h * 3600 + x * 60 + sec)),
      if (showSeconds) ...[const SizedBox(width: 8), box(t('dur_s'), sec, 59, (x) => onChanged(h * 3600 + m * 60 + x))],
    ]);
  }
}

/// Dialog with a [DurationPicker]; returns seconds, or null when cancelled.
Future<int?> durationDialog(BuildContext context, String title, int initial,
    {bool showHours = true, bool showSeconds = true, int maxHours = 23, int minSeconds = 0, String? hint, String? clearLabel}) {
  var v = initial;
  return showDialog<int>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        backgroundColor: C.surface,
        title: Text(title, style: const TextStyle(fontSize: 18)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (hint != null) ...[Text(hint, style: TextStyle(color: C.muted, fontSize: 13, height: 1.5)), const SizedBox(height: 12)],
          DurationPicker(value: v, showHours: showHours, showSeconds: showSeconds, maxHours: maxHours, onChanged: (x) => setLocal(() => v = x)),
          if (v < minSeconds) ...[const SizedBox(height: 8), Text(t('dur_min', {'x': fmtDuration(minSeconds)}), style: TextStyle(color: C.danger, fontSize: 12))],
        ]),
        actions: [
          if (clearLabel != null) TextButton(onPressed: () => Navigator.pop(ctx, 0), child: Text(clearLabel, style: TextStyle(color: C.danger))),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'), style: TextStyle(color: C.muted))),
          TextButton(onPressed: v < minSeconds ? null : () => Navigator.pop(ctx, v), child: Text(t('save'))),
        ],
      ),
    ),
  );
}
