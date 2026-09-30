import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../screens/home_screen.dart';
import '../theme.dart';

class StripCard extends StatelessWidget {
  final AppState state;
  final Strip strip;
  final Widget? dragHandle;
  const StripCard({super.key, required this.state, required this.strip, this.dragHandle});

  @override
  Widget build(BuildContext context) {
    final s = strip;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (dragHandle != null) dragHandle!,
              Flexible(
                child: Text(state.stripName(s),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              _badge(s.online),
              const Spacer(),
              Text('${s.livePower.toStringAsFixed(1)} W',
                  textDirection: TextDirection.ltr, style: mono(14, color: C.accent)),
              IconButton(
                tooltip: 'إعدادات المشترك',
                icon: const Icon(Icons.settings_outlined, color: C.muted, size: 20),
                onPressed: () => _openSettings(context),
              ),
            ],
          ),
          if (state.showMac)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(s.mac, textDirection: TextDirection.ltr, style: mono(11, color: C.faint, weight: FontWeight.w500)),
            ),
          const SizedBox(height: 6),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.45,
            children: s.outlets.map((o) => _OutletTile(state: state, strip: s, outlet: o)).toList(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => state.setOutlet(s.mac, 0, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: C.accentBg,
                    foregroundColor: C.accent,
                    minimumSize: const Size(0, 44),
                    side: const BorderSide(color: C.tileOnBorder),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('شغّل الكل', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => state.setOutlet(s.mac, 0, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: C.textSoft,
                    minimumSize: const Size(0, 44),
                    side: const BorderSide(color: C.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('اقفل الكل', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _badge(bool online) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: online ? C.greenBg : C.surface2, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 6, height: 6, decoration: BoxDecoration(color: online ? C.green : C.faint, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(online ? 'متصل' : 'غير متصل', style: TextStyle(fontSize: 11, color: online ? C.greenText : C.muted)),
        ]),
      );

  void _openSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => ListenableBuilder(
        listenable: state,
        builder: (ctx, _) {
          final s = state.allStrips.firstWhere((x) => x.mac == strip.mac, orElse: () => strip);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(state.stripName(s), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  const Text('إعدادات المشترك', style: TextStyle(color: C.muted)),
                  const SizedBox(height: 14),
                  _row(Icons.edit_outlined, 'تغيير اسم المشترك', null, () async {
                    final v = await askName(ctx, 'اسم المشترك', state.stripName(s));
                    if (v != null) state.renameStrip(s, v);
                  }),
                  for (final o in s.outlets)
                    _row(Icons.label_outline, 'اسم المخرج ${o.n}', state.outletName(s, o.n), () async {
                      final v = await askName(ctx, 'اسم المخرج ${o.n}', state.outletName(s, o.n));
                      if (v != null) state.renameOutlet(s, o.n, v);
                    }),
                  const Divider(color: C.border, height: 24),
                  _info('الفيرموير', s.fw.isEmpty ? '—' : s.fw),
                  _info('الفولت', s.voltage == null ? '—' : '${s.voltage!.toStringAsFixed(1)} V'),
                  _info('قوة الإشارة', s.rssi == null ? '—' : '${s.rssi} dBm'),
                  if (state.showMac) _info('MAC', s.mac),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _row(IconData icon, String title, String? sub, VoidCallback onTap) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: C.accentBg, borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: C.accent, size: 20),
        ),
        title: Text(title),
        subtitle: sub == null ? null : Text(sub, style: const TextStyle(color: C.muted)),
        onTap: onTap,
      );

  Widget _info(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Text(k, style: const TextStyle(color: C.muted)),
          const Spacer(),
          Text(v, textDirection: TextDirection.ltr, style: mono(13, color: C.textSoft, weight: FontWeight.w500)),
        ]),
      );
}

class _OutletTile extends StatelessWidget {
  final AppState state;
  final Strip strip;
  final Outlet outlet;
  const _OutletTile({required this.state, required this.strip, required this.outlet});

  @override
  Widget build(BuildContext context) {
    final on = outlet.on;
    final pending = state.isPending(strip.mac, outlet.n);
    final name = state.outletName(strip, outlet.n);
    return Material(
      color: on ? C.tileOn : C.tile,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: on ? C.tileOnBorder : C.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: pending ? null : () => state.setOutlet(strip.mac, outlet.n, !on),
        onLongPress: () async {
          final v = await askName(context, 'اسم المخرج ${outlet.n}', name);
          if (v != null) state.renameOutlet(strip, outlet.n, v);
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.power_outlined, color: on ? C.accent : C.faint, size: 24),
                  const Spacer(),
                  if (pending)
                    const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: C.accent))
                  else
                    SizedBox(
                      height: 28,
                      child: FittedBox(
                        child: Switch(
                          value: on,
                          onChanged: (v) => state.setOutlet(strip.mac, outlet.n, v),
                          activeTrackColor: C.accent,
                          inactiveTrackColor: C.switchOff,
                          thumbColor: WidgetStateProperty.resolveWith(
                              (st) => st.contains(WidgetState.selected) ? C.onAccent : C.muted),
                          trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
                        ),
                      ),
                    ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(on ? '${outlet.powerW.toStringAsFixed(1)} W' : 'مقفول',
                          textDirection: TextDirection.ltr,
                          style: on ? mono(12, color: C.accent, weight: FontWeight.w500) : const TextStyle(fontSize: 12, color: C.muted)),
                      const SizedBox(width: 8),
                      Text('${outlet.tempC}°C',
                          textDirection: TextDirection.ltr, style: mono(12, color: _tempColor(outlet.tempC), weight: FontWeight.w500)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _tempColor(int t) => t >= 60 ? C.danger : (t >= 45 ? C.accent : C.muted);
}
