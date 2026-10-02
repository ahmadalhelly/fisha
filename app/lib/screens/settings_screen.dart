import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'connection_screen.dart';
import 'firmware_screen.dart';
import 'notifications_screen.dart';
import 'wifi_screen.dart';

String _tr(String ar, String en) => Tr.isAr ? ar : en;

const appVersion = '1.3.0';

/// Settings home: short, grouped, every detail lives one tap deeper.
class SettingsScreen extends StatelessWidget {
  final AppState state;
  const SettingsScreen({super.key, required this.state});

  void _open(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final st = state;
    return SafeArea(
      child: ListenableBuilder(
        listenable: st,
        builder: (context, _) {
          final conn = switch (st.mode) {
            ConnMode.local => t('mode_local'),
            ConnMode.cloud => t('mode_cloud'),
            ConnMode.offline => t('mode_offline'),
          };
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 28),
            children: [
              Text(t('settings'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
              const SizedBox(height: 18),
              _group(_tr('الـ Hub', 'Hub'), [
                _row(context, Icons.wifi, C.accent2, _tr('شبكة الواي فاي', 'Wi-Fi network'), st.hubSsid.isEmpty ? '—' : st.hubSsid,
                    () => _open(context, WifiScreen(state: st))),
                _row(context, Icons.link, C.accent, _tr('الاتصال', 'Connection'), conn, () => _open(context, ConnectionScreen(state: st)),
                    dot: st.mode == ConnMode.offline ? C.danger : C.green),
                _row(context, Icons.notifications_outlined, C.warn, t('notif_title'),
                    st.ntfyTopic.isEmpty ? t('notif_off_state') : t('notif_on_state'), () => _open(context, NotificationsScreen(state: st))),
                _row(context, Icons.system_update_alt, C.accent, t('fw_title'), 'v${st.hubFw ?? '—'}', () => _open(context, FirmwareScreen(state: st)),
                    last: true),
              ]),
              const SizedBox(height: 18),
              _group(t('sec_look'), [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                  child: Segmented<ThemePref>(
                    value: st.themePref,
                    items: {ThemePref.system: t('th_system'), ThemePref.dark: t('th_dark'), ThemePref.light: t('th_light')},
                    onChanged: st.setThemePref,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
                  child: Segmented<LangPref>(
                    value: st.langPref,
                    items: {LangPref.system: t('th_system'), LangPref.ar: 'العربية', LangPref.en: 'English'},
                    onChanged: st.setLangPref,
                  ),
                ),
              ]),
              const SizedBox(height: 18),
              _group(t('sec_privacy'), [
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                  value: st.showMac,
                  onChanged: st.setShowMac,
                  activeTrackColor: C.accent,
                  title: Text(t('show_mac')),
                  subtitle: Text(t('show_mac_sub'), style: TextStyle(color: C.muted, fontSize: 12)),
                ),
              ]),
              const SizedBox(height: 26),
              Column(children: [
                const BrandMark(size: 56),
                const SizedBox(height: 6),
                Text('${t('app_name')} · Fisha', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                Text('${t('version')} $appVersion', style: TextStyle(color: C.muted, fontSize: 12)),
                const SizedBox(height: 2),
                Text(t('by'), textDirection: TextDirection.ltr, style: TextStyle(color: C.warn, fontSize: 13, fontWeight: FontWeight.w700)),
              ]),
            ],
          );
        },
      ),
    );
  }

  Widget _group(String title, List<Widget> children) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 6, bottom: 8),
          child: Text(title, style: TextStyle(fontSize: 12.5, color: C.muted, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: cardBox(radius: 20),
          child: Column(children: children),
        ),
      ]);

  Widget _row(BuildContext context, IconData icon, Color color, String title, String value, VoidCallback onTap, {Color? dot, bool last = false}) =>
      InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: C.border))),
          child: Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 19, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500))),
            if (dot != null) ...[Container(width: 7, height: 7, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)), const SizedBox(width: 6)],
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 130),
              child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.muted, fontSize: 13)),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, color: C.faint, size: 20),
          ]),
        ),
      );
}
