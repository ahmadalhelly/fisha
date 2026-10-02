import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'firmware_screen.dart';
import 'notifications_screen.dart';

const appVersion = '1.2.0';

class SettingsScreen extends StatefulWidget {
  final AppState state;
  const SettingsScreen({super.key, required this.state});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  TextEditingController? _hub, _host, _port, _user, _pass, _local, _localPort;
  bool _obscure = true;

  void _initCtrls() {
    if (_hub != null || !widget.state.ready) return;
    final s = widget.state.settings;
    _hub = TextEditingController(text: s.hubId);
    _host = TextEditingController(text: s.brokerHost);
    _port = TextEditingController(text: '${s.brokerPort}');
    _user = TextEditingController(text: s.username);
    _pass = TextEditingController(text: s.password);
    _local = TextEditingController(text: s.localHost);
    _localPort = TextEditingController(text: '${s.localPort}');
  }

  @override
  void dispose() {
    for (final c in [_hub, _host, _port, _user, _pass, _local, _localPort]) {
      c?.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final s = HubSettings(
      hubId: _hub!.text.trim().toUpperCase(),
      brokerHost: _host!.text.trim(),
      brokerPort: int.tryParse(_port!.text.trim()) ?? 8883,
      username: _user!.text.trim(),
      password: _pass!.text,
      localHost: _local!.text.trim(),
      localPort: int.tryParse(_localPort!.text.trim()) ?? 8080,
    );
    FocusScope.of(context).unfocus();
    await widget.state.saveSettings(s);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('saved'))));
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    _initCtrls();
    if (_hub == null) return const SizedBox.shrink();
    return SafeArea(
      child: ListenableBuilder(
        listenable: st,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 24),
          children: [
            Text(t('settings'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            section(t('sec_look'), [
              Text(t('theme'), style: TextStyle(color: C.textSoft)),
              Segmented<ThemePref>(
                value: st.themePref,
                items: {ThemePref.system: t('th_system'), ThemePref.dark: t('th_dark'), ThemePref.light: t('th_light')},
                onChanged: st.setThemePref,
              ),
              Text(t('language'), style: TextStyle(color: C.textSoft)),
              Segmented<LangPref>(
                value: st.langPref,
                items: {LangPref.system: t('th_system'), LangPref.ar: 'العربية', LangPref.en: 'English'},
                onChanged: st.setLangPref,
              ),
            ]),
            const SizedBox(height: 16),
            section(t('conn_status'), [
              _status(t('st_local'), st.mode == ConnMode.local),
              _status(t('st_live'), st.sseLive),
              _status(t('st_cloud'), st.mqttConnected),
              _status(t('st_hub'), st.hubOnline),
              if (st.hubFw != null) _kv(t('hub_fw'), st.hubFw!),
            ]),
            const SizedBox(height: 16),
            section(t('sec_hub'), [
              _nav(Icons.notifications_outlined, t('notif_title'), st.ntfyTopic.isEmpty ? t('notif_off_state') : t('notif_on_state'),
                  () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NotificationsScreen(state: st)))),
              _nav(Icons.system_update_alt, t('fw_title'), '${t('hub_fw')}: ${st.hubFw ?? '—'}',
                  () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FirmwareScreen(state: st)))),
            ]),
            const SizedBox(height: 16),
            section(t('sec_local'), [
              _field(_local!, t('f_local'), hint: '192.168.1.110', ltr: true),
              _field(_localPort!, t('f_port'), hint: '8080', ltr: true, number: true),
            ]),
            const SizedBox(height: 16),
            section(t('sec_cloud'), [
              _field(_hub!, t('f_hubid'), hint: '80F3DA40F674', ltr: true),
              _field(_host!, t('f_host'), hint: 'xxxx.emqxsl.com', ltr: true),
              _field(_port!, t('f_port'), hint: '8883', ltr: true, number: true),
              _field(_user!, t('f_user'), hint: 'stripe_app', ltr: true),
              TextField(
                controller: _pass,
                obscureText: _obscure,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: t('f_pass'),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? t('show') : t('hide'),
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: C.muted),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            primaryButton(t('save_reconnect'), _save, icon: Icons.sync),
            const SizedBox(height: 16),
            section(t('sec_privacy'), [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: st.showMac,
                onChanged: st.setShowMac,
                activeTrackColor: C.accent,
                title: Text(t('show_mac')),
                subtitle: Text(t('show_mac_sub'), style: TextStyle(color: C.muted, fontSize: 12)),
              ),
            ]),
            const SizedBox(height: 16),
            section(t('sec_about'), [
              Row(children: [
                const BrandMark(size: 52),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${t('app_name')} · Fisha', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    Text('${t('version')} $appVersion', style: TextStyle(color: C.muted, fontSize: 12)),
                    Text(t('by'), textDirection: TextDirection.ltr, style: TextStyle(color: C.warn, fontSize: 13, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ]),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _nav(IconData icon, String title, String sub, VoidCallback onTap) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: C.accentBg, borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: C.accent, size: 20),
        ),
        title: Text(title),
        subtitle: Text(sub, style: TextStyle(color: C.muted, fontSize: 12)),
        trailing: Icon(Icons.chevron_right, color: C.faint),
        onTap: onTap,
      );

  Widget _field(TextEditingController c, String label, {String? hint, bool ltr = false, bool number = false}) => TextField(
        controller: c,
        textDirection: ltr ? TextDirection.ltr : null,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        autocorrect: false,
        decoration: InputDecoration(labelText: label, hintText: hint),
      );

  Widget _status(String label, bool ok) => Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: ok ? C.green : C.faint, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
        Text(ok ? t('online') : t('offline'), style: TextStyle(color: ok ? C.greenText : C.muted, fontSize: 12)),
      ]);

  Widget _kv(String k, String v) => Row(children: [
        Text(k, style: TextStyle(color: C.muted)),
        const Spacer(),
        Text(v, textDirection: TextDirection.ltr, style: mono(13, color: C.textSoft, weight: FontWeight.w500)),
      ]);
}
