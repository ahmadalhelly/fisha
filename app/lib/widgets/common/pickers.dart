part of '../common.dart';

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
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(children: [
        if (showHours) ...[box(t('dur_h'), h, maxHours, (x) => onChanged(x * 3600 + m * 60 + sec)), const SizedBox(width: 8)],
        box(t('dur_m'), m, 59, (x) => onChanged(h * 3600 + x * 60 + sec)),
        if (showSeconds) ...[const SizedBox(width: 8), box(t('dur_s'), sec, 59, (x) => onChanged(h * 3600 + m * 60 + x))],
      ]),
    );
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

// ---------- 12-hour clock (AM/PM) ----------
String fmtTime12(int hh, int mm) {
  final h = hh % 12 == 0 ? 12 : hh % 12;
  final pm = hh >= 12;
  return '$h:${two(mm)} ${Tr.isAr ? (pm ? 'م' : 'ص') : (pm ? 'PM' : 'AM')}';
}

/// Time picker that always shows AM/PM.
Future<TimeOfDay?> pickTime12(BuildContext context, TimeOfDay initial) => showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: false), child: child!),
    );

// ---------- value stepper (replaces drag sliders) ----------
/// A − / + bar; tap the number to type it. Holding − / + keeps counting.
/// Nothing is sent while the user is still changing it: [onChanged] fires once, [commitDelay] after the last change.
class ValueStepper extends StatefulWidget {
  final double value, min, max, step;
  final String unit;
  final int decimals;
  final bool enabled;
  /// Label for a special value (e.g. 0 → "Off"); return null to show the number.
  final String? Function(double v)? special;
  /// Optional smart suggestion shown above the bar.
  final double? suggestion;
  final String? suggestionNote;
  final ValueChanged<double> onChanged;
  final Duration commitDelay;
  const ValueStepper({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.unit,
    required this.onChanged,
    this.decimals = 0,
    this.enabled = true,
    this.special,
    this.suggestion,
    this.suggestionNote,
    this.commitDelay = const Duration(milliseconds: 700),
  });

  @override
  State<ValueStepper> createState() => _ValueStepperState();
}

class _ValueStepperState extends State<ValueStepper> {
  late double _v = _clamp(widget.value);
  Timer? _commit, _hold, _repeat;
  bool _typing = false;
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _typing) _endTyping();
    });
  }

  double _clamp(double v) {
    final s = widget.step;
    return (((v.clamp(widget.min, widget.max)) / s).round() * s).clamp(widget.min, widget.max).toDouble();
  }

  @override
  void didUpdateWidget(ValueStepper old) {
    super.didUpdateWidget(old);
    // adopt the hub's value unless the user is mid-change
    if (_commit == null && !_typing && widget.value != old.value) _v = _clamp(widget.value);
  }

  @override
  void dispose() {
    _hold?.cancel();
    _repeat?.cancel();
    if (_commit != null) {
      _commit!.cancel();
      widget.onChanged(_v);
    }
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _set(double v, {bool now = false}) {
    final n = _clamp(v);
    if (n == _v) return;
    setState(() => _v = n);
    _commit?.cancel();
    _commit = Timer(now ? Duration.zero : widget.commitDelay, () {
      _commit = null;
      widget.onChanged(_v);
    });
  }

  void _startHold(double dir) {
    _set(_v + dir * widget.step);
    _hold = Timer(const Duration(milliseconds: 400), () {
      _repeat = Timer.periodic(const Duration(milliseconds: 80), (_) => _set(_v + dir * widget.step));
    });
  }

  void _stopHold() {
    _hold?.cancel();
    _repeat?.cancel();
    _hold = _repeat = null;
  }

  void _startTyping() {
    if (!widget.enabled) return;
    _ctrl.text = _isSpecial(_v) ? '' : _v.toStringAsFixed(widget.decimals);
    _ctrl.selection = TextSelection(baseOffset: 0, extentOffset: _ctrl.text.length);
    setState(() => _typing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _endTyping() {
    final n = double.tryParse(_ctrl.text.trim().replaceAll(',', '.'));
    setState(() => _typing = false);
    if (n != null) _set(n, now: true);
  }

  String _fmt(double v) => widget.special?.call(v) ?? v.toStringAsFixed(widget.decimals);
  bool _isSpecial(double v) => widget.special?.call(v) != null;

  Widget _btn(IconData icon, double dir) {
    final can = widget.enabled && (dir < 0 ? _v > widget.min : _v < widget.max);
    return GestureDetector(
      onTapDown: can ? (_) => _startHold(dir) : null,
      onTapUp: (_) => _stopHold(),
      onTapCancel: _stopHold,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 52,
        height: 46,
        decoration: BoxDecoration(
          color: can ? C.card : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: C.cardEdge),
        ),
        child: Icon(icon, size: 22, color: can ? C.text : C.faint),
      ),
    );
  }

  Widget _value() {
    if (_typing) {
      return Center(
        child: SizedBox(
          width: 110,
          child: TextField(
            controller: _ctrl,
            focusNode: _focus,
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: mono(26, color: C.accent, weight: FontWeight.w700),
            decoration: InputDecoration(
              isDense: true,
              filled: false,
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              suffixText: widget.unit,
              suffixStyle: mono(13, color: C.muted),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: C.accent, width: 2)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: C.accent, width: 2)),
            ),
            onSubmitted: (_) => _focus.unfocus(),
          ),
        ),
      );
    }
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: widget.enabled ? _startTyping : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: _isSpecial(_v)
            ? Text(_fmt(_v), textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: C.muted))
            : Text.rich(
                TextSpan(children: [
                  TextSpan(text: _fmt(_v), style: mono(28, color: C.accent, weight: FontWeight.w700)),
                  TextSpan(text: ' ${widget.unit}', style: mono(13, color: C.muted)),
                ]),
                textAlign: TextAlign.center,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.enabled;
    final sug = widget.suggestion;
    final showSug = on && sug != null && _clamp(sug) != _v;
    return Opacity(
      opacity: on ? 1 : 0.5,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (showSug) ...[
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _set(sug, now: true),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(colors: [C.accent.withValues(alpha: 0.16), C.accent.withValues(alpha: 0.04)]),
                  border: Border.all(color: C.accent.withValues(alpha: 0.35)),
                ),
                child: Row(children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: C.accent.withValues(alpha: 0.18), shape: BoxShape.circle),
                    child: Icon(Icons.auto_awesome, size: 17, color: C.accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${Tr.isAr ? 'اقتراح' : 'Suggested'}: ${_clamp(sug).toStringAsFixed(widget.decimals)} ${widget.unit}',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: C.text)),
                      if (widget.suggestionNote != null)
                        Text(widget.suggestionNote!, style: TextStyle(fontSize: 11, color: C.muted, height: 1.3)),
                    ]),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: C.accent, borderRadius: BorderRadius.circular(99)),
                    child: Text(Tr.isAr ? 'استخدم' : 'Use', style: TextStyle(color: C.onAccent, fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: C.well, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.cardEdge)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Row(children: [
              _btn(Icons.remove, -1),
              const SizedBox(width: 8),
              Expanded(child: _value()),
              const SizedBox(width: 8),
              _btn(Icons.add, 1),
            ]),
          ),
        ),
      ]),
    );
  }
}
