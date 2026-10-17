import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../i18n.dart';
import '../theme.dart';

// authenticateBio(reason): local_auth on the phone, skipped on the web build (services/bio_auth*.dart)
export '../services/bio_auth.dart';

part 'common/format_dialogs.dart';
part 'common/motion.dart';
part 'common/pickers.dart';
part 'common/misc.dart';

/// Space the floating bottom bar takes over a tab page (0 on pages pushed above it).
double navInset(BuildContext c) => MediaQuery.paddingOf(c).bottom;

/// How far a tab page's add button must rise to clear the floating bottom bar.
double fabLift(BuildContext c) => math.max(0.0, MediaQuery.paddingOf(c).bottom - MediaQuery.viewPaddingOf(c).bottom);

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
