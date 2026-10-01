import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../theme.dart';

class SettingsScreen extends StatefulWidget {
  final AppState state;
  const SettingsScreen({super.key, required this.state});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _hub, _host, _port, _user, _pass, _local, _localPort;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
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
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final s = HubSettings(
      hubId: _hub.text.trim().toUpperCase(),
      brokerHost: _host.text.trim(),
      brokerPort: int.tryParse(_port.text.trim()) ?? 8883,
      username: _user.text.trim(),
      password: _pass.text,
      localHost: _local.text.trim(),
      localPort: int.tryParse(_localPort.text.trim()) ?? 8080,
    );
    FocusScope.of(context).unfocus();
    await widget.state.saveSettings(s);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('saved'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    return SafeArea(
      child: ListenableBuilder(
        listenable: st,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 24),
          children: [
            Text(t('settings'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            _section(t('sec_look'), [
              Text(t('theme'), style: TextStyle(color: C.textSoft)),
              _segmented<ThemePref>(
                value: st.themePref,
                items: {ThemePref.system: t('th_system'), ThemePref.dark: t('th_dark'), ThemePref.light: t('th_light')},
                onChanged: st.setThemePref,
              ),
              const SizedBox(height: 4),
              Text(t('language'), style: TextStyle(color: C.textSoft)),
              _segmented<LangPref>(
                value: st.langPref,
                items: {LangPref.system: t('th_system'), LangPref.ar: 'العربية', LangPref.en: 'English'},
                onChanged: st.setLangPref,
              ),
            ]),
            const SizedBox(height: 16),
            _section(t('conn_status'), [
              _status(t('st_local'), st.mode == ConnMode.local),
              _status(t('st_cloud'), st.mqttConnected),
              _status(t('st_hub'), st.hubOnline),
              if (st.hubFw != null) _kv(t('hub_fw'), st.hubFw!),
            ]),
            const SizedBox(height: 16),
            _section(t('sec_local'), [
              _field(_local, t('f_local'), hint: '192.168.1.110', ltr: true),
              _field(_localPort, t('f_port'), hint: '8080', ltr: true, number: true),
            ]),
            const SizedBox(height: 16),
            _section(t('sec_cloud'), [
              _field(_hub, t('f_hubid'), hint: '80F3DA40F674', ltr: true),
              _field(_host, t('f_host'), hint: 'xxxx.emqxsl.com', ltr: true),
              _field(_port, t('f_port'), hint: '8883', ltr: true, number: true),
              _field(_user, t('f_user'), hint: 'stripe_app', ltr: true),
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
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                backgroundColor: C.accent,
                foregroundColor: C.onAccent,
                minimumSize: const Size(0, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(t('save_reconnect'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            const SizedBox(height: 16),
            _section(t('sec_privacy'), [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: st.showMac,
                onChanged: st.setShowMac,
                activeTrackColor: C.accent,
                title: Text(t('show_mac')),
                subtitle: Text(t('show_mac_sub'), style: TextStyle(color: C.muted, fontSize: 12)),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _segmented<T>({required T value, required Map<T, String> items, required ValueChanged<T> onChanged}) {
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
                child: Container(
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: e.key == value ? C.accentBg : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: e.key == value ? C.tileOnBorder : Colors.transparent),
                  ),
                  child: Text(e.value,
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

  Widget _section(String title, List<Widget> children) => Container(
        padding: const EdgeInsets.all(16),
        decoration: cardBox(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: TextStyle(fontSize: 13, color: C.muted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            for (final c in children) Padding(padding: const EdgeInsets.only(bottom: 10), child: c),
          ],
        ),
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
