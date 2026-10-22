import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../models.dart';
import '../screens/outlet_sheet.dart';
import '../theme.dart';
import 'common.dart';
import 'notion_icon_picker.dart';
import 'wifi_arcs.dart';

part 'strip_card/guards.dart';
part 'strip_card/levels.dart';
part 'strip_card/sockets.dart';
part 'strip_card/flow.dart';

/// A strip drawn as the real thing: one body with four sockets that light up and show their load as a ring.
class StripCard extends StatelessWidget {
  final AppState state;
  final Strip strip;
  final Widget? dragHandle;
  const StripCard({super.key, required this.state, required this.strip, this.dragHandle});

  @override
  Widget build(BuildContext context) {
    final s = strip;
    final online = s.online;
    final stripBadges = badgesFor(state, s, null);
    final stripIcon = state.stripIcon(s.mac);
    final stripLevel = s.maxTemp >= 60 ? 3 : loadLevel(s.livePower, kStripMaxW);
    final stripTone = stripLevel == 0 ? C.accent : levelColor(stripLevel);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: online ? 1 : 0.6,
      child: Container(
        decoration: BoxDecoration(
          color: C.card,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            // a quiet edge and a soft drop shadow instead of a neon glow
            color: online && s.onCount > 0 ? stripTone.withValues(alpha: C.dark ? 0.30 : 0.26) : C.cardEdge,
            width: 1.0,
          ),
          boxShadow: online && s.onCount > 0
              ? [
                  BoxShadow(
                    color: stripTone.withValues(alpha: C.dark ? 0.07 : 0.06),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            if (dragHandle != null) dragHandle!,
            PulseDot(color: online ? C.green : C.faint, active: online),
            const SizedBox(width: 6),
            Expanded(
              child: InkWell(
                onTap: () => openStripSheet(context, state, s.mac),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    if (stripIcon.isNotEmpty) ...[
                      FishaIcon(icon: stripIcon, size: 17),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        state.stripName(s),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, height: 1.25),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Builder(builder: (_) {
                      final tip = s.rssi != null ? '${s.rssi} dBm' : (online ? '—' : t('offline'));
                      return Tooltip(
                        message: tip,
                        child: WifiArcs(rssi: s.rssi),
                      );
                    }),
                  ]),
                  const SizedBox(height: 5),
                  Row(children: [
                    Text(
                      online ? t('n_of_4', {'a': s.onCount, 'b': s.outlets.length}) : t('offline_kept'),
                      style: TextStyle(fontSize: 11.5, color: online ? C.textSoft : C.danger, fontWeight: FontWeight.w500),
                    ),
                    if (online) ...[
                      const SizedBox(width: 6),
                      Text('·', style: TextStyle(fontSize: 11, color: C.border)),
                      const SizedBox(width: 6),
                      Text('${s.maxTemp}°C', textDirection: TextDirection.ltr, style: TextStyle(fontSize: 11.5, color: tempColor(s.maxTemp), fontWeight: FontWeight.w600)),
                    ],
                    if (online && s.voltage != null) ...[
                      const SizedBox(width: 6),
                      Text('·', style: TextStyle(fontSize: 11, color: C.border)),
                      const SizedBox(width: 6),
                      Text('${s.voltage!.toStringAsFixed(0)} V', textDirection: TextDirection.ltr, style: TextStyle(fontSize: 11.5, color: voltColor(s.voltage!), fontWeight: FontWeight.w600)),
                    ],
                    if (stripBadges.isNotEmpty) ...[const SizedBox(width: 6), ...stripBadges],
                  ]),
                ]),
              ),
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  textDirection: TextDirection.ltr,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    AnimatedNumber(
                      value: online ? s.livePower : 0,
                      style: mono(18, color: online ? loadColor(s.livePower, kStripMaxW) : C.faint),
                    ),
                    const SizedBox(width: 2.5),
                    Text('W', style: mono(11, color: C.muted, weight: FontWeight.w500)),
                  ],
                ),
                if (online && s.voltage != null && s.voltage! > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${(s.livePower / s.voltage!).toStringAsFixed(2)}A',
                    textDirection: TextDirection.ltr,
                    style: mono(11, color: C.textSoft, weight: FontWeight.w600),
                  ),
                ],
              ],
            ),
            IconButton(
              tooltip: t('strip_settings'),
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.tune, color: C.muted, size: 20),
              onPressed: () => openStripSheet(context, state, s.mac),
            ),
          ]),
          if (state.showMac)
            Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: s.mac));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(Tr.isAr ? 'تم نسخ الماك آدرس: ${s.mac}' : 'MAC copied: ${s.mac}'),
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(s.mac, textDirection: TextDirection.ltr, style: mono(10, color: C.faint, weight: FontWeight.w500)),
                      const SizedBox(width: 4),
                      Icon(Icons.copy, size: 10, color: C.faint),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          // the strip body
          Container(
            padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: C.glass ? [C.well, C.well] : (C.dark ? [C.surface2, C.surface] : [C.surface, C.surface2]),
              ),
              border: Border.all(color: C.cardEdge),
            ),
            child: Column(children: [
              Row(children: [
                for (final o in s.outlets) Expanded(child: _Socket(state: state, strip: s, outlet: o)),
              ]),
              const SizedBox(height: 8),
              _MasterSocket(state: state, strip: s),
            ]),
          ),
        ]),
      ),
    );
  }
}
