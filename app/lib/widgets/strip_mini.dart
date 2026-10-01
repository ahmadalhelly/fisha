import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme.dart';

class StripMini extends StatelessWidget {
  final AppState state;
  final Strip strip;
  final VoidCallback onTap;
  const StripMini({super.key, required this.state, required this.strip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = strip;
    return Material(
      color: s.online ? C.surface : C.surface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: C.border)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Expanded(
                  child: Text(state.stripName(s),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                if (s.lockedCount > 0) Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: Icon(Icons.lock_outline, size: 14, color: C.muted),
                ),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: s.online ? C.green : C.faint, shape: BoxShape.circle),
                ),
              ]),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(s.online ? '${s.livePower.toStringAsFixed(1)} W' : '—',
                    textDirection: TextDirection.ltr, style: mono(22, color: s.online ? C.accent : C.faint)),
              ),
              Row(
                children: [
                  for (var i = 0; i < s.outlets.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Expanded(
                      child: GestureDetector(
                        onTap: state.isPending(s.mac, s.outlets[i].n)
                            ? null
                            : () => state.setOutlet(s.mac, s.outlets[i].n, !s.outlets[i].on),
                        child: Container(
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: s.outlets[i].on ? C.accent : C.miniOff,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('${s.outlets[i].n}',
                              style: mono(11, color: s.outlets[i].on ? C.onAccent : C.muted, weight: FontWeight.w500)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              Row(children: [
                Expanded(
                  child: Text(s.online ? t('n_of_4', {'a': s.onCount, 'b': s.outlets.length}) : t('offline'),
                      style: TextStyle(fontSize: 11, color: C.muted)),
                ),
                if (s.online)
                  Text('${s.maxTemp}°C', textDirection: TextDirection.ltr, style: mono(11, color: C.muted, weight: FontWeight.w500)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
