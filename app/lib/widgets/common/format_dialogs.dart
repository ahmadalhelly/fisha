part of '../common.dart';

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

/// Human uptime: e.g. "3 ي 4:12 س", "25 د", "45 ث"
String formatHumanDuration(int s) {
  if (s <= 0) return '—';
  final d = s ~/ 86400;
  final h = (s % 86400) ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  if (Tr.isAr) {
    if (d > 0) return '$d ي $h:${two(m)} س';
    if (h > 0) return '$h:${two(m)} س';
    if (m > 0) return '$m د';
    return '$sec ث';
  } else {
    if (d > 0) return '${d}d ${h}:${two(m)}h';
    if (h > 0) return '${h}:${two(m)}h';
    if (m > 0) return '${m}m';
    return '${sec}s';
  }
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
