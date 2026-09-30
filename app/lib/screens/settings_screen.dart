import 'package:flutter/material.dart';

import '../app_state.dart';
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اتحفظ، وجاري إعادة الاتصال')));
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
            const Text('الإعدادات', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            _section('حالة الاتصال', [
              _status('محلي (نفس الشبكة)', st.mode == ConnMode.local),
              _status('السيرفر (من برا البيت)', st.mqttConnected),
              _status('الـ Hub متصل بالسيرفر', st.hubOnline),
              if (st.hubFw != null) _kv('فيرموير الـ Hub', st.hubFw!),
            ]),
            const SizedBox(height: 16),
            _section('الـ Hub المحلي', [
              _field(_local, 'عنوان الـ Hub', hint: '192.168.1.110', ltr: true),
              _field(_localPort, 'البورت', hint: '8080', ltr: true, number: true),
            ]),
            const SizedBox(height: 16),
            _section('السيرفر (التحكم من برا البيت)', [
              _field(_hub, 'Hub ID', hint: '80F3DA40F674', ltr: true),
              _field(_host, 'عنوان السيرفر', hint: 'xxxx.emqxsl.com', ltr: true),
              _field(_port, 'البورت', hint: '8883', ltr: true, number: true),
              _field(_user, 'اسم المستخدم', hint: 'stripe_app', ltr: true),
              TextField(
                controller: _pass,
                obscureText: _obscure,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: 'الباسورد',
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'إظهار' : 'إخفاء',
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
              child: const Text('حفظ وإعادة الاتصال', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            const SizedBox(height: 16),
            _section('الخصوصية', [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: st.showMac,
                onChanged: st.setShowMac,
                activeTrackColor: C.accent,
                title: const Text('إظهار الـ MAC'),
                subtitle: const Text('مخفي افتراضيًا عشان تقدر تاخد سكرين شوت وتشاركها بأمان',
                    style: TextStyle(color: C.muted, fontSize: 12)),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => Container(
        padding: const EdgeInsets.all(16),
        decoration: cardBox(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontSize: 13, color: C.muted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            for (final c in children) Padding(padding: const EdgeInsets.only(bottom: 10), child: c),
          ],
        ),
      );

  Widget _field(TextEditingController c, String label, {String? hint, bool ltr = false, bool number = false}) =>
      TextField(
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
        Text(ok ? 'متصل' : 'غير متصل', style: TextStyle(color: ok ? C.greenText : C.muted, fontSize: 12)),
      ]);

  Widget _kv(String k, String v) => Row(children: [
        Text(k, style: const TextStyle(color: C.muted)),
        const Spacer(),
        Text(v, textDirection: TextDirection.ltr, style: mono(13, color: C.textSoft, weight: FontWeight.w500)),
      ]);
}
