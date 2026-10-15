import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/common.dart';

String _tr(String ar, String en) => Tr.isAr ? ar : en;
String _trx(String ar, String en, Map<String, Object?> args) {
  var v = Tr.isAr ? ar : en;
  args.forEach((k, val) => v = v.replaceAll('{$k}', '$val'));
  return v;
}

/// The home Wi-Fi the hub (and every new strip) uses.
class WifiScreen extends StatefulWidget {
  final AppState state;
  const WifiScreen({super.key, required this.state});

  @override
  State<WifiScreen> createState() => _WifiScreenState();
}

class _WifiScreenState extends State<WifiScreen> {
  AppState get s => widget.state;
  final _ssid = TextEditingController();
  final _pass = TextEditingController();
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _ssid.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final ssid = _ssid.text.trim();
    final pass = _pass.text;
    if (ssid.isEmpty) return;
    if (ssid.contains(':') || pass.contains(':')) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_tr('اسم الشبكة أو الباسورد مينفعش يكون فيهم علامة :', 'The name or password cannot contain ":"'))));
      return;
    }
    if (!await confirmDialog(context, _tr('تغيير شبكة الـ Hub؟', 'Change the hub network?'), _trx('الـ Hub هيفصل حوالي 20 ثانية ويجرّب "{x}". لو نجح هيكمل عليها ويحفظها، ولو فشل هيرجع للشبكة الحالية لوحده.', 'The hub goes offline for about 20 seconds and tries "{x}". If it works it stays and saves it; if not, it goes back to the current network.', {'x': ssid}), ok: _tr('جرّب واحفظ', 'Test & save'))) return;
    setState(() => _busy = true);
    final r = await s.setHubWifi(ssid, pass);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.error ?? t('err_failed'))));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(backgroundColor: C.bg, surfaceTintColor: Colors.transparent, title: Text(_tr('شبكة الواي فاي', 'Wi-Fi network'), style: const TextStyle(fontWeight: FontWeight.w700))),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: s,
          builder: (context, _) => ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 24), children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: cardBox(),
              child: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: C.accent2.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
                  child: Icon(Icons.wifi, color: C.accent2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_tr('الـ Hub متصل بـ', 'The hub is on'), style: TextStyle(color: C.muted, fontSize: 12)),
                    Text(s.hubSsid.isEmpty ? '—' : s.hubSsid, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ]),
            ),
            if (s.wifiTest != 'idle') ...[const SizedBox(height: 12), _testCard()],
            if (s.hubV2 && (s.hubFw == '2.0' || s.hubFw == '2.1' || s.hubFw == '2.2' || s.hubFw == '2.3'))
              emptyCard(_tr('تغيير الشبكة من التطبيق محتاج فيرموير الـ Hub 2.4 أو أحدث.', 'Changing the network from the app needs hub firmware 2.4 or newer.'), icon: Icons.system_update_alt)
            else
              section(_tr('تغيير الشبكة والربط', 'Connect & change network'), [
                TextField(controller: _ssid, textDirection: TextDirection.ltr, autocorrect: false, decoration: InputDecoration(labelText: _tr('اسم الشبكة (2.4GHz)', 'Network name (2.4 GHz)'))),
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
                primaryButton(_tr('جرّب واحفظ', 'Test & save'), _busy || s.mode == ConnMode.offline ? null : _apply, icon: Icons.check),
              ]),
            const SizedBox(height: 14),
            emptyCard(_tr('المشتركات بتحفظ الشبكة جواها. لو غيّرت اسم أو باسورد الراوتر نفسه، كل مشترك محتاج تضيفه تاني من "إضافة مشترك"، وأساميه وإعداداته هترجع زي ما هي.', 'Strips keep the network inside them. If you change the router name or password, add each strip again with "Add strip"; its names and settings come back as they were.'), icon: Icons.info_outline),
            const SizedBox(height: 10),
            emptyCard(_tr('لو غيّرت الراوتر قبل ما تغيّر هنا، الـ Hub هيفتح شبكة مفتوحة (من غير باسورد) اسمها Fisha-Hub-XXXX. ادخل عليها من الموبايل، وافتح 192.168.4.1 واختار الشبكة الجديدة.', 'If you change the router first, the hub opens an open network (no password) called Fisha-Hub-XXXX. Join it from your phone, open 192.168.4.1 and pick the new network.'), icon: Icons.router_outlined),
          ]),
        ),
      ),
    );
  }

  Widget _testCard() {
    final (icon, color, text) = switch (s.wifiTest) {
      'ok' => (Icons.check_circle_outline, C.green, _trx('الـ Hub اتنقل لـ "{x}" واتحفظت.', 'The hub moved to "{x}" and saved it.', {'x': s.wifiTestSsid})),
      'failed' => (Icons.error_outline, C.danger, _trx('"{x}" ما اشتغلتش (اسم أو باسورد غلط؟)، والـ Hub رجع للشبكة القديمة.', '"{x}" did not work (wrong name or password?); the hub went back to the old network.', {'x': s.wifiTestSsid})),
      _ => (Icons.sync, C.accent, _trx('الـ Hub بيجرّب "{x}"…', 'The hub is trying "{x}"…', {'x': s.wifiTestSsid})),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: cardBox(border: color.withValues(alpha: 0.5)),
      child: Row(children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: C.textSoft, height: 1.5))),
      ]),
    );
  }
}
