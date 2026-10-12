import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/common.dart';

String _tr(String ar, String en) => Tr.isAr ? ar : en;

/// How the app reaches the hub: on the home Wi-Fi, and through the server when away.
class ConnectionScreen extends StatefulWidget {
  final AppState state;
  const ConnectionScreen({super.key, required this.state});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  late final _s = widget.state.settings;
  late final _hub = TextEditingController(text: _s.hubId);
  late final _host = TextEditingController(text: _s.brokerHost);
  late final _port = TextEditingController(text: '${_s.brokerPort}');
  late final _user = TextEditingController(text: _s.username);
  late final _pass = TextEditingController(text: _s.password);
  late final _local = TextEditingController(text: _s.localHost);
  late final _localPort = TextEditingController(text: '${_s.localPort}');
  late final _hubPass = TextEditingController(text: _s.hubPass);
  bool _obscure = true;
  bool _obscureHub = true;
  bool _advanced = false;

  @override
  void dispose() {
    for (final c in [_hub, _host, _port, _user, _pass, _local, _localPort, _hubPass]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final oldLocal = _s.localHost;
    final s = HubSettings(
      hubId: _hub.text.trim().toUpperCase(),
      brokerHost: _host.text.trim(),
      brokerPort: int.tryParse(_port.text.trim()) ?? 8883,
      username: _user.text.trim(),
      password: _pass.text,
      localHost: _local.text.trim(),
      localPort: int.tryParse(_localPort.text.trim()) ?? 8080,
      hubPass: _hubPass.text,
      sharedUser: _s.sharedUser,
      sharedName: _s.sharedName,
      sharedRole: _s.sharedRole,
      ownerKey: _s.ownerKey,   // 2.0.18: keep this phone's hub key
    );
    FocusScope.of(context).unfocus();
    await widget.state.saveSettings(s);
    if (!s.isShared && s.localHost != oldLocal && s.localHost.isNotEmpty) await widget.state.pushHubLocalIp(s.localHost);
    var msg = t('saved');
    if (!kIsWeb && s.hubPass.isNotEmpty && !s.isShared) {
      // give the local link a moment after the restart, then hand the hub its server password
      for (var i = 0; i < 6 && widget.state.mode != ConnMode.local; i++) {
        await Future.delayed(const Duration(milliseconds: 700));
      }
      if (widget.state.mode == ConnMode.local) {
        final r = await widget.state.pushHubPass(force: true);
        msg = r.ok ? t('cloud_pass_sent') : (r.error ?? t('err_failed'));
      } else {
        msg = t('cloud_pass_later');
      }
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(backgroundColor: C.bg, surfaceTintColor: Colors.transparent, title: Text(_tr('الاتصال', 'Connection'), style: const TextStyle(fontWeight: FontWeight.w700))),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: st,
          builder: (context, _) => ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 24), children: [
            section(t('conn_status'), [
              // the web build is cloud-only: the hub's http LAN API is blocked on an https page (WEB.md)
              if (kLocalCapable) _status(t('st_local'), st.mode == ConnMode.local),
              if (!kIsWeb) _status(t('st_live'), st.sseLive),
              _status(t('st_cloud'), st.mqttConnected),
              _status(t('st_hub'), st.hubOnline),
              if (st.hubCloudUp == false && st.hubCloudErr.isNotEmpty)
                Text(t('cloud_err_${st.hubCloudErr}'), style: TextStyle(color: C.warn, fontSize: 12, height: 1.5)),
              if (st.hubUptimeS != null && st.hubUptimeS! > 0)
                Row(children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: C.accent, shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_tr('وقت تشغيل الـ Hub', 'Hub uptime'))),
                  Text(formatHumanDuration(st.hubUptimeS!), textDirection: TextDirection.ltr, style: mono(12, color: C.textSoft, weight: FontWeight.w500)),
                ]),
            ]),
            const SizedBox(height: 14),
            if (st.isShared) ...[
              emptyCard(t('shared_banner', {'x': st.settings.sharedName.isEmpty ? st.settings.sharedUser : st.settings.sharedName}), icon: Icons.group_outlined),
              const SizedBox(height: 14),
            ],
            if (kLocalCapable) ...[
              section(t('sec_local'), [
                _field(_local, t('f_local'), hint: '192.168.1.100'),
              ]),
              const SizedBox(height: 14),
            ],
            section(t('sec_cloud'), [
              _field(_user, t('f_user'), hint: 'stripe_app'),
              TextField(
                controller: _pass,
                obscureText: _obscure,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: t('f_pass'),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: C.muted),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              if (!st.isShared)
                TextField(
                  controller: _hubPass,
                  obscureText: _obscureHub,
                  textDirection: TextDirection.ltr,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: t('f_hub_pass'),
                    helperText: t('f_hub_pass_sub'),
                    helperMaxLines: 3,
                    suffixIcon: IconButton(
                      icon: Icon(_obscureHub ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: C.muted),
                      onPressed: () => setState(() => _obscureHub = !_obscureHub),
                    ),
                  ),
                ),
              InkWell(
                onTap: () => setState(() => _advanced = !_advanced),
                child: Row(children: [
                  Icon(_advanced ? Icons.expand_less : Icons.expand_more, color: C.muted, size: 20),
                  const SizedBox(width: 4),
                  Text(_tr('إعدادات متقدمة', 'Advanced'), style: TextStyle(color: C.muted, fontSize: 13)),
                ]),
              ),
              if (_advanced) ...[
                _field(_hub, t('f_hubid'), hint: '80F3DA40F674'),
                _field(_host, t('f_host'), hint: 'xxxx.emqxsl.com'),
                // web always uses wss://<host>:8084/mqtt, so neither port applies there
                if (!kIsWeb)
                  Row(children: [
                    Expanded(child: _field(_port, '${t('f_port')} (MQTT)', hint: '8883', number: true)),
                    const SizedBox(width: 10),
                    Expanded(child: _field(_localPort, '${t('f_port')} (${t('mode_local')})', hint: '8080', number: true)),
                  ]),
              ],
            ]),
            const SizedBox(height: 16),
            primaryButton(t('save_reconnect'), _save, icon: Icons.sync),
          ]),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, {String? hint, bool number = false}) => TextField(
        controller: c,
        textDirection: TextDirection.ltr,
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
}
