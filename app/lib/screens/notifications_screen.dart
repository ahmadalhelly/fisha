import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../theme.dart';
import '../services/notify_service.dart';
import '../widgets/common.dart';

String _tr(String ar, String en) => Tr.isAr ? ar : en;

/// Phone notifications: the hub pushes them through ntfy, so they arrive even when Fisha is closed.
class NotificationsScreen extends StatefulWidget {
  final AppState state;
  const NotificationsScreen({super.key, required this.state});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  AppState get s => widget.state;
  bool _busy = false;
  bool _native = false;

  @override
  void initState() {
    super.initState();
    NotifyService.isEnabled().then((v) => mounted ? setState(() => _native = v) : null);
  }

  Future<void> _toggleNative(bool v) async {
    if (v) {
      final ok = await NotifyService.enable();
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_tr('لازم تسمح للتطبيق بالإشعارات من إعدادات الموبايل', 'Allow notifications for Fisha in the phone settings'))));
      }
      setState(() => _native = ok);
    } else {
      await NotifyService.disable();
      if (mounted) setState(() => _native = false);
    }
  }

  String _newTopic() {
    const abc = 'abcdefghijkmnpqrstuvwxyz23456789';
    final r = Random.secure();
    return 'fisha-${List.generate(12, (_) => abc[r.nextInt(abc.length)]).join()}';
  }

  Future<void> _enable() async {
    setState(() => _busy = true);
    final topic = s.ntfyTopic.isNotEmpty ? s.ntfyTopic : _newTopic();
    await s.setNotifyConfig(topic: topic);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _disable() async {
    if (!await confirmDialog(context, t('notif_off_t'), t('notif_off_b'), ok: t('notif_off'), danger: true)) return;
    await s.setNotifyConfig(topic: '');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final on = s.ntfyTopic.isNotEmpty;
        return Scaffold(
          backgroundColor: C.bg,
          appBar: AppBar(
            backgroundColor: C.bg,
            surfaceTintColor: Colors.transparent,
            title: Text(t('notif_title'), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          body: SafeArea(
            child: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 24), children: [
              if (!s.hubV2) emptyCard(t('err_old_fw')) else ...[
                section(_tr('إشعارات Fisha', 'Fisha notifications'), [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeTrackColor: C.accent,
                    value: _native,
                    onChanged: _toggleNative,
                    title: Text(_tr('إشعارات مباشرة على الموبايل', 'Notifications on this phone'), style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        _tr('من غير أي تطبيق تاني. Fisha بيفضل شغال في الخلفية بإشعار صغير ثابت، وبيوصلك التنبيه حتى لو قفلت التطبيق أو كنت برا البيت.',
                            'No extra app. Fisha keeps a small service running in the background and alerts you even when it is closed or you are away.'),
                        style: TextStyle(color: C.muted, fontSize: 12, height: 1.5)),
                  ),
                  if (_native)
                    OutlinedButton.icon(
                      onPressed: () async {
                        final ok = await s.testNotify();
                        if (ok && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('notif_test_sent'))));
                      },
                      icon: const Icon(Icons.send_outlined),
                      label: Text(t('notif_test')),
                      style: OutlinedButton.styleFrom(foregroundColor: C.accent, side: BorderSide(color: C.tileOnBorder), minimumSize: const Size(0, 46)),
                    ),
                  if (_native && !s.settings.hasCloud)
                    Text(_tr('محتاج بيانات السيرفر في الإعدادات ← الاتصال عشان التنبيهات توصل.', 'Server details are needed in Settings → Connection.'),
                        style: TextStyle(color: C.danger, fontSize: 12)),
                ]),
                const SizedBox(height: 14),
                section(_tr('بديل: تطبيق ntfy', 'Alternative: the ntfy app'), [
                  Text(t('notif_how'), style: TextStyle(color: C.textSoft, height: 1.6)),
                  if (!on) primaryButton(t('notif_enable'), _busy ? null : _enable, icon: Icons.notifications_active_outlined),
                  if (on) ...[
                    _step('1', t('notif_step1')),
                    _step('2', t('notif_step2')),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(14)),
                      child: Row(children: [
                        Expanded(child: SelectableText(s.ntfyTopic, textDirection: TextDirection.ltr, style: mono(15, color: C.accent))),
                        IconButton(
                          tooltip: t('copy'),
                          icon: Icon(Icons.copy, color: C.muted),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: s.ntfyTopic));
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('copied'))));
                          },
                        ),
                      ]),
                    ),
                    _step('3', t('notif_step3')),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final ok = await s.testNotify();
                            if (ok && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('notif_test_sent'))));
                          },
                          icon: const Icon(Icons.send_outlined),
                          label: Text(t('notif_test')),
                          style: OutlinedButton.styleFrom(foregroundColor: C.accent, side: BorderSide(color: C.tileOnBorder), minimumSize: const Size(0, 46)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      TextButton(onPressed: _disable, child: Text(t('notif_off'), style: TextStyle(color: C.danger))),
                    ]),
                    Text(t('notif_privacy'), style: TextStyle(color: C.muted, fontSize: 12, height: 1.5)),
                  ],
                ]),
                if (on || _native) ...[
                  const SizedBox(height: 14),
                  section(t('notif_types'), [
                    for (var i = 0; i < AppState.notifyTypeKeys.length; i++)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        activeTrackColor: C.accent,
                        value: s.notifyTypes & (1 << i) != 0,
                        title: Text(t('nt_${AppState.notifyTypeKeys[i]}')),
                        onChanged: (v) => s.setNotifyConfig(types: v ? s.notifyTypes | (1 << i) : s.notifyTypes & ~(1 << i)),
                      ),
                  ]),
                  const SizedBox(height: 14),
                  section(t('notif_where'), [
                    Text(t('notif_where_sub'), style: TextStyle(color: C.muted, fontSize: 12, height: 1.5)),
                    for (final st in s.allStrips) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(s.stripName(st), style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        FilterChip(
                          label: Text(t('whole_strip')),
                          selected: st.notifyMask & 0x10 != 0,
                          selectedColor: C.accentBg,
                          onSelected: (v) => s.setNotifyMask(st, v ? st.notifyMask | 0x10 : st.notifyMask & ~0x10),
                        ),
                        for (final o in st.outlets)
                          FilterChip(
                            label: Text(s.outletName(st, o.n)),
                            selected: st.notifyMask & (1 << (o.n - 1)) != 0,
                            selectedColor: C.accentBg,
                            onSelected: (v) => s.setNotifyMask(st, v ? st.notifyMask | (1 << (o.n - 1)) : st.notifyMask & ~(1 << (o.n - 1))),
                          ),
                      ]),
                    ],
                  ]),
                ],
              ],
            ]),
          ),
        );
      },
    );
  }

  Widget _step(String n, String text) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: C.accentBg, shape: BoxShape.circle),
          child: Text(n, style: TextStyle(color: C.accent, fontWeight: FontWeight.w700, fontSize: 12)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: C.textSoft, height: 1.5))),
      ]);
}
