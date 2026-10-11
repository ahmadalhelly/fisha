import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../app_state.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../services/apk_install.dart';
import '../services/update_service.dart';
import 'settings_screen.dart' show appVersion;

String _tr(String ar, String en) => Tr.isAr ? ar : en;

/// Update center: the hub and the app, each with its update button, then every release with its notes.
/// Builds come from the public repo ahmadalhelly/fisha-app (CI copies each build there).
class UpdateCenterScreen extends StatefulWidget {
  final AppState state;
  const UpdateCenterScreen({super.key, required this.state});
  @override
  State<UpdateCenterScreen> createState() => _UpdateCenterScreenState();
}

class _UpdateCenterScreenState extends State<UpdateCenterScreen> {
  AppState get s => widget.state;
  UpdateService get u => UpdateService.instance;
  String _filter = 'all';
  final Map<String, double?> _progress = {}; // kind -> 0..1 while downloading / uploading
  final Map<String, String> _status = {}; // kind -> line under the button

  @override
  void initState() {
    super.initState();
    u.check();
  }

  String? _current(String kind) => kind == 'app' ? appVersion : s.hubFw;

  String _ago(DateTime t) {
    final m = DateTime.now().difference(t).inMinutes;
    if (m < 1) return _tr('دلوقتي', 'just now');
    if (m < 60) return _tr('من $m دقيقة', '$m min ago');
    final h = m ~/ 60;
    if (h < 24) return _tr('من $h ساعة', '$h h ago');
    return _tr('من ${h ~/ 24} يوم', '${h ~/ 24} d ago');
  }

  String _when(DateTime t) => '${t.day}/${t.month} · ${fmtTime12(t.hour, t.minute)}';

  Future<String?> _askPass() async {
    final ctrl = TextEditingController(text: s.otaPass);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        title: Text(_tr('باسورد التحديث', 'Update password'), style: const TextStyle(fontSize: 18)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: true,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(hintText: 'OTA_PASS'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'), style: TextStyle(color: C.muted))),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(t('save'))),
        ],
      ),
    );
  }

  Future<void> _updateHub(Release r) async {
    if (s.mode != ConnMode.local) {
      setState(() => _status['hub'] = t('fw_local_only'));
      return;
    }
    if (!await confirmDialog(context, _tr('تحديث الـ Hub لـ ${r.version}', 'Update the hub to ${r.version}'),
        _tr('الـ Hub هيعيد التشغيل بعد التحديث، والمشتركات بتفضل شغالة.', 'The hub restarts after the update; the strips keep running.'),
        ok: _tr('حدّث', 'Update'))) {
      return;
    }
    var pass = s.otaPass;
    if (pass.isEmpty) {
      final p = await _askPass();
      if (p == null) return;
      pass = p;
    }
    setState(() {
      _progress['hub'] = null;
      _status['hub'] = _tr('بينزّل الملف…', 'Downloading…');
    });
    List<int> bytes;
    try {
      final res = await http.get(Uri.parse(r.url)).timeout(const Duration(seconds: 90));
      if (res.statusCode != 200) throw Exception();
      bytes = res.bodyBytes;
    } catch (_) {
      if (mounted) setState(() => _status['hub'] = _tr('النت فصل وقت التنزيل. جرّب تاني.', 'The download failed. Try again.'));
      return;
    }
    if (!mounted) return;
    setState(() {
      _progress['hub'] = 0;
      _status['hub'] = _tr('بيرفع على الـ Hub…', 'Uploading to the hub…');
    });
    final err = await s.uploadFirmware(bytes, pass, (p) {
      if (mounted) setState(() => _progress['hub'] = p);
    });
    if (err == null) await s.setOtaPass(pass);
    if (!mounted) return;
    setState(() {
      _progress.remove('hub');
      _status['hub'] = switch (err) {
        null => _tr('اتحدّث. الـ Hub بيعيد التشغيل وهيرجع خلال دقيقة.', 'Done. The hub is restarting and will be back within a minute.'),
        'auth' => t('fw_err_auth'),
        'net' => t('fw_err_net'),
        _ => err,
      };
    });
  }

  Future<void> _updateApp(Release r) async {
    setState(() {
      _progress['app'] = 0;
      _status['app'] = _tr('بينزّل التطبيق…', 'Downloading the app…');
    });
    final err = await downloadAndInstallApk(r.url, r.size, (p) {
      if (mounted) setState(() => _progress['app'] = p);
    });
    if (!mounted) return;
    setState(() {
      _progress.remove('app');
      _status['app'] = switch (err) {
        null => _tr('دوس «تثبيت» في الشاشة اللي فتحت. لو أندرويد طلب إذن، اسمح للتطبيق يثبّت تطبيقات.',
            'Tap "Install" on the screen that opened. If Android asks, allow the app to install apps.'),
        'install' => _tr('ماقدرتش أفتح شاشة التثبيت. اسمح للتطبيق يثبّت تطبيقات من الإعدادات وجرّب تاني.',
            'Could not open the installer. Allow this app to install apps in Android settings and retry.'),
        _ => _tr('النت فصل وقت التنزيل. جرّب تاني.', 'The download failed. Try again.'),
      };
    });
  }

  Widget _mini(String kind) {
    final cur = _current(kind);
    final up = u.newer(kind, cur);
    final busy = _progress.containsKey(kind);
    final isHub = kind == 'hub';
    final blocked = isHub && s.isShared;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: cardBox(radius: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: C.accentBg, borderRadius: BorderRadius.circular(9)),
              child: Icon(isHub ? Icons.router_outlined : Icons.phone_android, size: 17, color: C.accent),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(isHub ? 'Hub' : _tr('التطبيق', 'App'), style: const TextStyle(fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 8),
          Text(cur == null || cur.isEmpty ? '—' : cur, textDirection: TextDirection.ltr, textAlign: TextAlign.end, style: mono(15, weight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (busy) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: _progress[kind], minHeight: 5, color: C.accent, backgroundColor: C.surface2),
            ),
          ] else
            SizedBox(
              height: 36,
              child: FilledButton(
                onPressed: up == null || blocked ? null : () => isHub ? _updateHub(up) : _updateApp(up),
                style: FilledButton.styleFrom(
                  backgroundColor: C.accent,
                  foregroundColor: C.onAccent,
                  disabledBackgroundColor: C.surface2,
                  disabledForegroundColor: C.faint,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: FittedBox(
                  child: Text(up == null ? _tr('آخر نسخة', 'Up to date') : _tr('حدّث لـ ${up.version}', 'Update to ${up.version}'),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                ),
              ),
            ),
          if (_status[kind] != null) ...[
            const SizedBox(height: 6),
            Text(_status[kind]!, style: TextStyle(color: C.muted, fontSize: 11.5, height: 1.5)),
          ],
        ]),
      ),
    );
  }

  Widget _chip(String key, String label) {
    final sel = _filter == key;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: sel,
        showCheckmark: false,
        selectedColor: C.accentBg,
        backgroundColor: C.surface2,
        labelStyle: TextStyle(color: sel ? C.text : C.textSoft, fontWeight: FontWeight.w600, fontSize: 12.5),
        side: BorderSide(color: sel ? C.tileOnBorder : C.border),
        onSelected: (_) => setState(() => _filter = key),
      ),
    );
  }

  Widget _release(Release r, bool last) {
    final cur = _current(r.kind);
    final isCur = cur != null && compareVersions(r.version, cur) == 0;
    final isNew = cur != null && cur != 'dev' && compareVersions(r.version, cur) > 0 && identical(u.latest(r.kind), r);
    final dot = isNew ? C.accent : C.surface2;
    final tagColor = r.kind == 'hub' ? C.accent : C.blue;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 18,
          child: Column(children: [
            const SizedBox(height: 3),
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: dot,
                shape: BoxShape.circle,
                border: Border.all(color: isNew || isCur ? C.accent : C.border, width: 2),
              ),
            ),
            if (!last) Expanded(child: Container(width: 2, color: C.border)),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(color: tagColor.withValues(alpha: .14), borderRadius: BorderRadius.circular(6)),
                  child: Text(r.kind == 'hub' ? 'Hub' : 'App', style: TextStyle(color: tagColor, fontSize: 10.5, fontWeight: FontWeight.w700)),
                ),
                Text(r.version, textDirection: TextDirection.ltr, style: mono(13.5, weight: FontWeight.w600)),
                if (isNew) _pill(_tr('جديد', 'New'), C.accent),
                if (isCur) _pill(_tr('اللي عندك', 'Installed'), C.muted),
              ]),
              const SizedBox(height: 2),
              Text(_when(r.published), style: TextStyle(color: C.muted, fontSize: 11)),
              const SizedBox(height: 4),
              for (final l in r.lines.take(8))
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(padding: const EdgeInsets.only(top: 7), child: Container(width: 4, height: 4, decoration: BoxDecoration(color: C.faint, shape: BoxShape.circle))),
                    const SizedBox(width: 8),
                    Expanded(child: Text(l, style: TextStyle(color: C.textSoft, fontSize: 12.5, height: 1.6))),
                  ]),
                ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _pill(String text, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: c.withValues(alpha: .14), borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(color: c, fontSize: 10.5, fontWeight: FontWeight.w700)),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([u, s]),
      builder: (context, _) {
        final items = u.releases.where((r) => _filter == 'all' || r.kind == _filter).take(30).toList();
        return Scaffold(
          backgroundColor: C.bg,
          appBar: AppBar(
            backgroundColor: C.bg,
            surfaceTintColor: Colors.transparent,
            title: Text(_tr('مركز التحديثات', 'Update center'), style: const TextStyle(fontWeight: FontWeight.w700)),
            actions: [
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 10),
                child: u.loading
                    ? Padding(padding: const EdgeInsets.all(14), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: C.accent)))
                    : TextButton(onPressed: () => u.check(force: true), child: Text(_tr('شيّك دلوقتي', 'Check now'))),
              ),
            ],
          ),
          body: SafeArea(
            child: RefreshIndicator(
              color: C.accent,
              onRefresh: () => u.check(force: true),
              child: ListView(padding: const EdgeInsets.fromLTRB(18, 4, 18, 28), children: [
                Text(
                  u.error == 'rate'
                      ? _tr('GitHub طلب نستنى شوية قبل التشييك تاني.', 'GitHub asked us to wait before checking again.')
                      : u.error == 'net'
                          ? _tr('ماقدرتش أوصل لـ GitHub. اتأكد من النت.', 'Could not reach GitHub. Check the internet.')
                          : u.checkedAt == null
                              ? _tr('بيشيّك…', 'Checking…')
                              : '${_tr('آخر تشييك', 'Last check')}: ${_ago(u.checkedAt!)} · GitHub',
                  style: TextStyle(color: u.error != null ? C.warn : C.muted, fontSize: 12),
                ),
                const SizedBox(height: 12),
                IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_mini('hub'), const SizedBox(width: 8), _mini('app')])),
                const SizedBox(height: 18),
                Row(children: [_chip('all', _tr('الكل', 'All')), _chip('hub', 'Hub'), _chip('app', _tr('التطبيق', 'App'))]),
                const SizedBox(height: 14),
                if (items.isEmpty && !u.loading)
                  emptyCard(_tr('لسه مفيش إصدارات منشورة.', 'No releases published yet.'), icon: Icons.inventory_2_outlined),
                for (var i = 0; i < items.length; i++) _release(items[i], i == items.length - 1),
              ]),
            ),
          ),
        );
      },
    );
  }
}
