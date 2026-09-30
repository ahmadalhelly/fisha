import 'package:flutter/material.dart';

import '../app_state.dart';
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
      color: s.online ? C.surface : const Color(0xFF11161D),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: C.border),
      ),
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
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: s.online ? C.green : C.faint, shape: BoxShape.circle),
                ),
              ]),
              Text(s.online ? '${s.livePower.toStringAsFixed(1)} W' : '—',
                  textAlign: TextAlign.right,
                  textDirection: TextDirection.ltr,
                  style: mono(22, color: s.online ? C.accent : C.faint)),
              Row(
                children: [
                  for (final o in s.outlets) ...[
                    Expanded(
                      child: GestureDetector(
                        onTap: state.isPending(s.mac, o.n) ? null : () => state.setOutlet(s.mac, o.n, !o.on),
                        child: Container(
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: o.on ? C.accent : const Color(0xFF1F2733),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('${o.n}', style: mono(11, color: o.on ? C.onAccent : C.muted, weight: FontWeight.w500)),
                        ),
                      ),
                    ),
                    if (o.n != s.outlets.last.n) const SizedBox(width: 6),
                  ],
                ],
              ),
              Row(children: [
                Expanded(
                  child: Text(s.online ? '${s.onCount} من ${s.outlets.length} شغالين' : 'غير متصل',
                      style: const TextStyle(fontSize: 11, color: C.muted)),
                ),
                if (s.online)
                  Text('${s.maxTemp}°C',
                      textDirection: TextDirection.ltr, style: mono(11, color: C.muted, weight: FontWeight.w500)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
