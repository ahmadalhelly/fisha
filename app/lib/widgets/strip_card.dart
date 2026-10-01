import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
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
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(state.stripName(s),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    _badge(s.online),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text('${s.livePower.toStringAsFixed(1)} W', textDirection: TextDirection.ltr, style: mono(14, color: C.accent)),
              IconButton(
                tooltip: t('strip_settings'),
                icon: Icon(Icons.settings_outlined, color: C.muted, size: 20),
                onPressed: () => openStripSettings(context, state, s.mac),
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
                    side: BorderSide(color: C.tileOnBorder),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(t('all_on'), style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => state.setOutlet(s.mac, 0, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: C.textSoft,
                    minimumSize: const Size(0, 44),
                    side: BorderSide(color: C.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(t('all_off'), style: const TextStyle(fontWeight: FontWeight.w600)),
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
          Text(online ? t('online') : t('offline'), style: TextStyle(fontSize: 11, color: online ? C.greenText : C.muted)),
        ]),
      );
}

/// Bottom sheet with names, child lock and device info. Reads the live strip on every rebuild.
void openStripSettings(BuildContext context, AppState state, String mac) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => ListenableBuilder(
      listenable: state,
      builder: (ctx, _) {
        final s = state.live(mac);
        if (s == null) return const SizedBox(height: 120);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              children: [
                Text(state.stripName(s), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                Text(t('strip_settings'), style: TextStyle(color: C.muted)),
                const SizedBox(height: 14),
                _row(Icons.edit_outlined, t('rename_strip'), null, () async {
                  final v = await askName(ctx, t('strip_name'), state.stripName(s));
                  if (v != null) state.rename(s, 0, v);
                }),
                const SizedBox(height: 8),
                Text(t('outlets'), style: TextStyle(fontSize: 13, color: C.muted, fontWeight: FontWeight.w600)),
                for (final o in s.outlets) ...[
                  _row(Icons.label_outline, t('outlet_name', {'n': o.n}), state.outletName(s, o.n), () async {
                    final v = await askName(ctx, t('outlet_name', {'n': o.n}), state.outletName(s, o.n));
                    if (v != null) state.rename(s, o.n, v);
                  }),
                  SwitchListTile(
                    contentPadding: const EdgeInsetsDirectional.only(start: 52),
                    dense: true,
                    value: o.locked,
                    onChanged: (v) => state.setLock(s, o.n, v),
                    activeTrackColor: C.accent,
                    secondary: null,
                    title: Text(t('child_lock')),
                    subtitle: Text(t('child_lock_sub'), style: TextStyle(color: C.muted, fontSize: 12)),
                  ),
                ],
                Divider(color: C.border, height: 24),
                Text(t('device'), style: TextStyle(fontSize: 13, color: C.muted, fontWeight: FontWeight.w600)),
                _info(t('fw'), s.fw.isEmpty ? '—' : s.fw),
                _info(t('voltage'), s.voltage == null ? '—' : '${s.voltage!.toStringAsFixed(1)} V'),
                _info(t('rssi'), s.rssi == null ? '—' : '${s.rssi} dBm'),
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
      subtitle: sub == null ? null : Text(sub, style: TextStyle(color: C.muted)),
      onTap: onTap,
    );

Widget _info(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Text(k, style: TextStyle(color: C.muted)),
        const Spacer(),
        Text(v, textDirection: TextDirection.ltr, style: mono(13, color: C.textSoft, weight: FontWeight.w500)),
      ]),
    );

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
          final v = await askName(context, t('outlet_name', {'n': outlet.n}), name);
          if (v != null) state.rename(strip, outlet.n, v);
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
                  if (outlet.locked) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.lock_outline, color: C.muted, size: 15, semanticLabel: t('child_lock')),
                  ],
                  const Spacer(),
                  if (pending)
                    SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: C.accent))
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
                  Text(name,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(on ? '${outlet.powerW.toStringAsFixed(1)} W' : t('off'),
                          textDirection: TextDirection.ltr,
                          style: on ? mono(12, color: C.accent, weight: FontWeight.w500) : TextStyle(fontSize: 12, color: C.muted)),
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

  Color _tempColor(int c) => c >= 60 ? C.danger : (c >= 45 ? C.accent : C.muted);
}
