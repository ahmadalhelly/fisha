import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../theme.dart';
import '../models.dart';
import '../services/hub_setup.dart';
import '../widgets/common.dart';
import '../widgets/hub_setup_sheet.dart';
import 'about_screen.dart';
import 'account_screen.dart';
import 'sync_screen.dart';
import 'connection_screen.dart';
import 'firmware_screen.dart';
import 'guide_screen.dart';
import 'manual_screen.dart';
import 'users_screen.dart';
import 'notifications_screen.dart';
import 'rooms_screen.dart';
import 'strip_firmware_screen.dart';
import 'update_center_screen.dart';
import 'lock_screen.dart';
import '../services/update_service.dart';
import 'wifi_screen.dart';

String _tr(String ar, String en) => Tr.isAr ? ar : en;

const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

/// Settings home: short, grouped, every detail lives one tap deeper.
class SettingsScreen extends StatelessWidget {
  final AppState state;
  const SettingsScreen({super.key, required this.state});

  void _open(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  Future<void> _editName(BuildContext context, AppState st) async {
    final ctrl = TextEditingController(text: st.userName);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        title: Text(_tr('اسمك', 'Your name'), style: const TextStyle(fontSize: 18)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: _tr('اكتب اسمك عشان الترحيب', 'Enter your name for the greeting')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'), style: TextStyle(color: C.muted))),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(t('save'))),
        ],
      ),
    );
    if (v != null) await st.setUserName(v);
  }

  @override
  Widget build(BuildContext context) {
    final st = state;
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: st,
        builder: (context, _) {
          final conn = switch (st.mode) {
            ConnMode.local => t('mode_local'),
            ConnMode.cloud => t('mode_cloud'),
            ConnMode.offline => t('mode_offline'),
          };
          return ListView(
            padding: EdgeInsets.fromLTRB(18, 20, 18, navInset(context) + 20),
            children: [
              Text(t('settings'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
              const SizedBox(height: 18),
              // your account on top (Google photo, name, email, role); below it only what your role allows
              _profileCard(context, st),
              const SizedBox(height: 18),
              _group(_tr('الحساب', 'Account'), [
                if (st.isOwner)
                  _row(
                    context,
                    Icons.group_outlined,
                    C.accent2,
                    t('users_title'),
                    st.usersCount == 0 ? '—' : '${st.usersCount}',
                    () => _open(context, UsersScreen(state: st)),
                  ),
                _row(
                  context,
                  Icons.person_outline,
                  C.accent,
                  _tr('اسمك', 'Your name'),
                  st.userName.isEmpty ? _tr('غير محدد', 'Not set') : st.userName,
                  () => _editName(context, st),
                  last: !st.canAdmin,
                ),
                if (st.canAdmin)
                  _row(
                  context,
                  Icons.meeting_room_outlined,
                  C.accent2,
                  _tr('الغرف', 'Rooms'),
                  _tr('${st.rooms.length} غرف', '${st.rooms.length} rooms'),
                  () => _open(context, RoomsScreen(state: st)),
                  last: true,
                ),
              ]),
              const SizedBox(height: 18),
              _group(_tr('الـ Hub', 'Hub'), [
                // Wi-Fi change and firmware upload need the hub's home-network page: not on the web build (WEB.md)
                if (!kIsWeb && st.can(Perm.wifi))
                  _row(context, Icons.wifi, C.accent2, _tr('شبكة الواي فاي', 'Wi-Fi network'), st.hubSsid.isEmpty ? '—' : st.hubSsid,
                    () => _open(context, WifiScreen(state: st))),
                // set up a new hub (or one whose Wi-Fi changed) from inside the app
                if (HubSetup.supported && st.isOwner)
                  _row(context, Icons.add_circle_outline, C.accent, _tr('إضافة هاب', 'Add a hub'), _tr('هاب جديد أو اتغيّرت شبكته', 'New hub, or its Wi-Fi changed'),
                      () => showHubSetup(context, st)),
                _row(context, Icons.link, C.accent, _tr('الاتصال', 'Connection'), conn, () => _open(context, ConnectionScreen(state: st)),
                    dot: st.mode == ConnMode.offline ? C.danger : C.green),
                _row(context, Icons.notifications_outlined, C.warn, t('notif_title'),
                    st.ntfyTopic.isEmpty ? t('notif_off_state') : t('notif_on_state'), () => _open(context, NotificationsScreen(state: st))),
                // latest hub and app builds, with how many are newer than what runs here
                if (!kIsWeb)
                  ListenableBuilder(
                    listenable: UpdateService.instance,
                    builder: (context, _) {
                      final u = UpdateService.instance;
                      final n = (u.newer('app', appVersion) != null ? 1 : 0) + (st.can(Perm.hubFw) && u.newer('hub', st.hubFw) != null ? 1 : 0);
                      return _row(context, Icons.cloud_download_outlined, C.accent, _tr('مركز التحديثات', 'Update center'),
                          n == 0 ? _tr('آخر نسخة', 'Up to date') : _tr('$n جديد', '$n new'), () => _open(context, UpdateCenterScreen(state: st)),
                          dot: n > 0 ? C.danger : null);
                    },
                  ),
                // hub lock (owner only)
                if (st.isOwner)
                  _row(context, st.hubClaimed == true ? Icons.lock_outline : Icons.lock_open_outlined, st.hubClaimed == false ? C.warn : C.accent,
                      _tr('قفل الهاب', 'Hub lock'),
                      st.hubClaimed == true ? _tr('مقفول', 'Locked') : st.hubClaimed == false ? _tr('مفتوح', 'Open') : '—',
                      () => _open(context, HubLockScreen(state: st)),
                      dot: st.hubClaimed == false ? C.warn : null),
                if (!kIsWeb && st.can(Perm.hubFw))
                  _row(context, Icons.system_update_alt, C.accent, t('fw_title'), 'v${st.hubFw ?? '—'}', () => _open(context, FirmwareScreen(state: st))),
                if (!kIsWeb && st.can(Perm.stripFw))
                  _row(context, Icons.electrical_services, C.accent2, t('sfw_title'), '', () => _open(context, StripFirmwareScreen(state: st))),
                if (st.canAdmin)
                  _row(context, Icons.restart_alt, C.danger, t('reboot_title'), st.hubReset.isEmpty ? '' : t('reboot_last', {'x': t('reset_${st.hubReset}')}),
                      () => _reboot(context, st)),
                if (st.canAdmin)
                  _row(context, Icons.settings_backup_restore, C.accent2, t('sync_title'), '', () => _open(context, SyncScreen(state: st))),
              ]),
              const SizedBox(height: 18),
              _group(t('sec_look'), [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 14, 10, 8),
                  child: Wrap(alignment: WrapAlignment.center, runSpacing: 10, children: [
                    for (final (p, label, a, b) in [
                      (ThemePref.system, t('th_system'), const Color(0xFF1A4FA0), const Color(0xFFB9D8F6)),
                      (ThemePref.midnight, _tr('زجاج داكن', 'Midnight'), const Color(0xFF1A4FA0), const Color(0xFF3EE0C0)),
                      (ThemePref.pearl, _tr('زجاج فاتح', 'Pearl'), const Color(0xFFB9D8F6), const Color(0xFF0E9F7E)),
                      (ThemePref.dark, t('th_dark'), const Color(0xFF070D19), const Color(0xFF2EE6B0)),
                      (ThemePref.graphite, _tr('جرافيت', 'Graphite'), const Color(0xFF25292F), const Color(0xFF4FD8B8)),
                      (ThemePref.light, t('th_light'), const Color(0xFFF1F6FA), const Color(0xFF079E7D)),
                      (ThemePref.saffron, _tr('زعفران', 'Saffron'), const Color(0xFFF8F1E4), const Color(0xFFC27803)),
                    ])
                      SizedBox(width: 74, child: _swatch(label, a, b, st.themePref == p, () => st.setThemePref(p))),
                  ]),
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
              _group(_tr('مساعدة', 'Help'), [
                _row(context, Icons.help_outline, C.accent, _tr('دليل الاستخدام', 'User guide'), _tr('كل ميزة وتشغيلها', 'Every feature, briefly'),
                    () => _open(context, const ManualScreen())),
                _row(context, Icons.menu_book_outlined, C.accent2, _tr('طريقة التوصيل', 'Setup guide'), _tr('من الأول للآخر', 'Start to finish'),
                    () => _open(context, const GuideScreen())),
                _row(context, Icons.info_outline, C.accent, _tr('عن التطبيق', 'About'), appVersion, () => _open(context, AboutScreen(state: st)), last: true),
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
                const LoopLogo(size: 56),
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

  Widget _profileCard(BuildContext context, AppState st) {
    final name = st.userName.isNotEmpty ? st.userName : (st.isShared ? st.settings.sharedName : '');
    final sub = st.googleEmail.isNotEmpty ? st.googleEmail : (st.isShared ? t('shared_short') : t('acc_local'));
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => _open(context, AccountScreen(state: st)),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: cardBox(radius: 20),
        child: Row(children: [
          Avatar(photo: st.googlePhoto, name: name.isEmpty ? sub : name, size: 50, ring: roleColor(st.myRole)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name.isEmpty ? t('acc_title') : name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(sub, textDirection: st.googleEmail.isNotEmpty ? TextDirection.ltr : null, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: C.muted, fontSize: 12)),
            ]),
          ),
          const SizedBox(width: 8),
          roleChip(st.myRole),
        ]),
      ),
    );
  }

  Widget _swatch(String label, Color bg, Color accent, bool selected, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(colors: [bg, bg, accent, bg]),
                border: Border.all(color: selected ? C.accent : C.border, width: selected ? 3 : 1),
              ),
              child: selected ? Icon(Icons.check, size: 18, color: accent) : null,
            ),
            const SizedBox(height: 6),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: selected ? C.accent : C.textSoft, fontWeight: selected ? FontWeight.w700 : FontWeight.w400)),
          ]),
        ),
      );

  Future<void> _reboot(BuildContext context, AppState st) async {
    if (!await confirmDialog(context, t('reboot_title'), t('reboot_body'), ok: t('reboot_btn'), danger: true)) return;
    final r = await st.rebootHub();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.ok ? t('reboot_ok') : (r.error ?? t('err_failed')))));
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
            // a long value (email, last reboot reason) goes under the title in full instead of being cut
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                if (value.length > 16) ...[
                  const SizedBox(height: 2),
                  Text(value, style: TextStyle(color: C.muted, fontSize: 12.5)),
                ],
              ]),
            ),
            if (dot != null) ...[Container(width: 7, height: 7, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)), const SizedBox(width: 6)],
            if (value.length <= 16) Text(value, style: TextStyle(color: C.muted, fontSize: 13)),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, color: C.faint, size: 20),
          ]),
        ),
      );
}
