import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../app_state.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ota_dialogs.dart';
import '../services/apk_install.dart';
import '../services/keep_alive.dart';
import '../services/update_service.dart';
import 'settings_screen.dart' show appVersion;
import 'strip_firmware_screen.dart';

String _tr(String ar, String en) => Tr.isAr ? ar : en;

/// Update center (2.0.20): one ring for the overall state, then the app, the hub, and the strips, each
/// expandable in place. The changelog shown per item is the version installed now and the new one available —
/// a short, generic line each, never the full release history or the raw commit log.
class UpdateCenterScreen extends StatefulWidget {
  final AppState state;
  const UpdateCenterScreen({super.key, required this.state});
  @override
  State<UpdateCenterScreen> createState() => _UpdateCenterScreenState();
}

class _UpdateCenterScreenState extends State<UpdateCenterScreen> {
  AppState get s => widget.state;
  UpdateService get u => UpdateService.instance;
  final _open = <String, bool>{};
  final Map<String, double?> _progress = {}; // kind -> 0..1 while downloading / uploading
  final Map<String, String> _status = {}; // kind -> line under the button

  @override
  void initState() {
    super.initState();
    u.check();
  }

  String? _current(String kind) => kind == 'app' ? appVersion : s.hubFw;

  String _when(DateTime t) => '${t.day}/${t.month} · ${fmtTime12(t.hour, t.minute)}';

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
    setState(() {
      _progress['hub'] = null;
      _status['hub'] = _tr('بينزّل الملف…', 'Downloading…');
    });
    // 2.0.25: keeps going if you switch to another app
    await UpdateKeepAlive.start(_tr('تحديث الـ Hub', 'Updating the hub'), _tr('بينزّل الملف…', 'Downloading…'));
    try {
      await _updateHubRun(r);
    } finally {
      await UpdateKeepAlive.stop();
    }
  }

  Future<void> _updateHubRun(Release r) async {
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
    final err = await s.uploadFirmwareAuto(bytes, (p) {
      UpdateKeepAlive.progress(_tr('تحديث الـ Hub', 'Updating the hub'), _tr('بيرفع على الـ Hub…', 'Uploading to the hub…'), p);
      if (mounted) setState(() => _progress['hub'] = p);
    }, ask: () => askUpdatePassword(context, s));
    if (!mounted) return;
    setState(() {
      _progress.remove('hub');
      _status['hub'] = switch (err) {
        null => _tr('اتحدّث. الـ Hub بيعيد التشغيل وهيرجع خلال دقيقة.', 'Done. The hub is restarting and will be back within a minute.'),
        'auth' || 'cancel' => t('fw_err_auth'),
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
    await UpdateKeepAlive.start(_tr('تحديث فيشة', 'Updating Fisha'), _tr('بينزّل التطبيق…', 'Downloading the app…'));
    final err = await downloadAndInstallApk(r.url, r.size, (p) {
      UpdateKeepAlive.progress(_tr('تحديث فيشة', 'Updating Fisha'), _tr('بينزّل التطبيق…', 'Downloading the app…'), p);
      if (mounted) setState(() => _progress['app'] = p);
    });
    await UpdateKeepAlive.stop();
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

  /// The release whose version matches the one actually installed, if it is still published.
  Release? _releaseFor(String kind, String? version) {
    if (version == null || version.isEmpty) return null;
    for (final r in u.releases) {
      if (r.kind == kind && compareVersions(r.version, version) == 0) return r;
    }
    return null;
  }

  /// A short, generic line — the version installed now, and the new one available, never the full history.
  String _genericNote(String version, Release? r, String tag) {
    final first = r != null && r.lines.isNotEmpty ? r.lines.first : _tr('تحسينات عامة وإصلاحات', 'General improvements and fixes');
    return '$version ($tag) — $first';
  }

  Widget _kindIcon(String kind, {double size = 20}) => Icon(
        switch (kind) { 'hub' => Icons.router_outlined, 'strip' => Icons.power_outlined, _ => Icons.phone_android },
        size: size,
        color: C.accent,
      );

  bool _pending(String kind) {
    if (kind == 'strip') return s.strips.any((x) => x.online && u.newer('strip', x.fw) != null);
    final cur = _current(kind);
    return u.newer(kind, cur) != null;
  }

  Widget _row(String kind, String name) {
    final isOpen = _open[kind] ?? false;
    final pend = _pending(kind);
    final busy = _progress.containsKey(kind);
    final latest = u.latest(kind);
    final cur = _current(kind);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: cardBox(radius: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _open[kind] = !isOpen),
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: C.accentBg, borderRadius: BorderRadius.circular(11)),
                child: Center(child: _kindIcon(kind)),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                  Text(
                    kind == 'strip'
                        ? (pend
                            ? _tr('في مشتركات محتاجة تحديث', 'Some strips need an update')
                            : _tr('كل المشتركات محدّثة', 'All strips are up to date'))
                        : ((_current(kind)?.isEmpty ?? true) ? '—' : _current(kind)!),
                    textDirection: kind == 'strip' ? null : TextDirection.ltr,
                    style: TextStyle(color: C.muted, fontSize: 11.5),
                  ),
                ]),
              ),
              _statusChip(busy, pend),
              const SizedBox(width: 4),
              Icon(isOpen ? Icons.expand_less : Icons.expand_more, color: C.muted),
            ]),
          ),
        ),
        if (isOpen)
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 0, 13, 13),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Divider(height: 18),
              if (kind == 'strip')
                _stripBody()
              else ...[
                if (busy)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(value: _progress[kind], minHeight: 5, color: C.accent, backgroundColor: C.surface2),
                  )
                else
                  SizedBox(
                    height: 42,
                    child: FilledButton(
                      onPressed: latest == null || !pend ? null : () => kind == 'hub' ? _updateHub(latest) : _updateApp(latest),
                      style: FilledButton.styleFrom(
                        backgroundColor: C.accent,
                        foregroundColor: C.onAccent,
                        disabledBackgroundColor: C.surface2,
                        disabledForegroundColor: C.faint,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(pend ? _tr('حدّث لـ ${latest!.version}', 'Update to ${latest.version}') : _tr('آخر نسخة', 'Up to date'),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                if (_status[kind] != null) ...[
                  const SizedBox(height: 8),
                  Text(_status[kind]!, style: TextStyle(color: C.muted, fontSize: 11.5, height: 1.5)),
                ],
                const SizedBox(height: 10),
                if (pend && latest != null) ...[
                  Text(_genericNote(latest.version, latest, _tr('جديد', 'New')), style: TextStyle(color: C.textSoft, fontSize: 12.5, height: 1.6)),
                  if (cur != null && cur.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(_genericNote(cur, _releaseFor(kind, cur), _tr('الحالي', 'Current')), style: TextStyle(color: C.muted, fontSize: 12, height: 1.6)),
                  ],
                ] else if (cur != null && cur.isNotEmpty)
                  Text(_genericNote(cur, _releaseFor(kind, cur) ?? latest, _tr('آخر نسخة عندك', 'Your current version')),
                      style: TextStyle(color: C.textSoft, fontSize: 12.5, height: 1.6)),
              ],
            ]),
          ),
      ]),
    );
  }

  Widget _statusChip(bool busy, bool pend) {
    final (bg, fg, label) = busy
        ? (C.accent2.withValues(alpha: .14), C.accent2, _tr('جاري', 'Busy'))
        : pend
            ? (C.warn.withValues(alpha: .14), C.warn, _tr('تحديث متاح', 'Update available'))
            : (C.green.withValues(alpha: .14), C.green, _tr('محدّث', 'Up to date'));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 10.5, fontWeight: FontWeight.w700)),
    );
  }

  bool _stripFetching = false;
  Future<void> _fetchLatestStrip() async {
    final release = u.latest('strip');
    if (release == null) {
      setState(() => _status['strip'] = _tr('مفيش ملف فيرموير صالح منشور.', 'No valid strip firmware release is published.'));
      return;
    }
    setState(() {
      _stripFetching = true;
      _status['strip'] = _tr('التطبيق بيحمّل F${release.version} ويرفعه للـ Hub (0%)…', 'Downloading F${release.version} and uploading to hub (0%)…');
    });
    final err = await s.downloadAndUploadStripFw(release.url, (p) {
      if (!mounted) return;
      final pct = (p * 100).clamp(0, 100).toStringAsFixed(0);
      setState(() {
        _status['strip'] = _tr('جاري تحميل ورفع F${release.version} للـ Hub ($pct%)…', 'Uploading F${release.version} to hub ($pct%)…');
      });
    });
    if (!mounted) return;
    setState(() {
      _stripFetching = false;
      if (err == null) {
        _status.remove('strip');
      } else {
        _status['strip'] = err == 'net'
            ? _tr('مقدرتش أوصل للـ Hub. اتأكد إنك على نفس الواي فاي.', 'Could not reach the hub.')
            : _tr('تعذر تجهيز الملف: $err', 'Could not prepare the file: $err');
      }
    });
    if (err == null) Navigator.of(context).push(MaterialPageRoute(builder: (_) => StripFirmwareScreen(state: s)));
  }

  Widget _stripBody() {
    final online = [for (final x in s.strips) if (x.online) x];
    if (online.isEmpty) return Text(_tr('مفيش مشتركات متصلة', 'No strips connected'), style: TextStyle(color: C.muted, fontSize: 12.5));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final x in online)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text(x.label.isNotEmpty ? x.label : x.mac, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
            Text(x.fw.isEmpty ? '—' : x.fw, textDirection: TextDirection.ltr,
                style: mono(12, color: u.newer('strip', x.fw) != null ? C.warn : C.muted)),
          ]),
        ),
      const SizedBox(height: 8),
      // the hub downloads our latest strip build itself; the file never passes through the phone
      FilledButton.icon(
        onPressed: s.mode == ConnMode.local && !_stripFetching && u.latest('strip') != null ? _fetchLatestStrip : null,
        icon: _stripFetching
            ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.onAccent))
            : const Icon(Icons.cloud_download_outlined, size: 18),
        label: Text(_tr('حمّل F${u.latest('strip')?.version ?? '—'} وحدّث', 'Get F${u.latest('strip')?.version ?? '—'} and update')),
        style: FilledButton.styleFrom(
            backgroundColor: C.accent, foregroundColor: C.onAccent, minimumSize: const Size(0, 44),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      ),
      if (_status['strip'] != null) ...[
        const SizedBox(height: 6),
        Text(_status['strip']!, style: TextStyle(color: C.muted, fontSize: 11.5, height: 1.5)),
      ],
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: s.mode == ConnMode.local ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StripFirmwareScreen(state: s))) : null,
        icon: const Icon(Icons.system_update_alt, size: 18),
        label: Text(_tr('تحديث المشتركات', 'Update strips')),
        style: OutlinedButton.styleFrom(foregroundColor: C.accent, side: BorderSide(color: C.tileOnBorder), minimumSize: const Size(0, 44)),
      ),
      const SizedBox(height: 6),
      Text(
        _tr('الزرار الأول بيخلي الـ Hub يجيب آخر نسخة بنفسه، وبعدها تختار المشتركات. التاني لو معاك ملف.',
            'The first button has the hub fetch the latest build itself, then you pick strips. The second is for a file you have.'),
        style: TextStyle(color: C.muted, fontSize: 11, height: 1.5),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([u, s]),
      builder: (context, _) {
        final kinds = ['app', if (s.can(Perm.hubFw)) 'hub', if (s.can(Perm.stripFw)) 'strip'];
        final okCount = kinds.where((k) => !_pending(k)).length;
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
              child: ListView(padding: const EdgeInsets.fromLTRB(18, 10, 18, 28), children: [
                _hero(okCount, kinds.length),
                const SizedBox(height: 16),
                _row('app', _tr('التطبيق', 'App')),
                if (s.can(Perm.hubFw)) _row('hub', 'Hub'),
                if (s.can(Perm.stripFw)) _row('strip', _tr('المشتركات', 'Strips')),
                const SizedBox(height: 4),
                Text(
                  u.error == 'rate'
                      ? _tr('سيرفر التحديثات طلب نستنى شوية قبل التشييك تاني.', 'The update server asked us to wait before checking again.')
                      : u.error == 'net'
                          ? _tr('ماقدرتش أوصل لسيرفر التحديثات. اتأكد من النت.', 'Could not reach the update server. Check the internet.')
                          : u.checkedAt == null
                              ? _tr('بيشيّك…', 'Checking…')
                              : '${_tr('آخر تشييك', 'Last check')}: ${_when(u.checkedAt!)}',
                  style: TextStyle(color: u.error != null ? C.warn : C.muted, fontSize: 12),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _hero(int okCount, int total) {
    final allOk = okCount == total;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: cardBox(radius: 18),
      child: Row(children: [
        SizedBox(
          width: 60,
          height: 60,
          child: CustomPaint(painter: _RingPainter(okCount / total, allOk ? C.green : C.accent)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(allOk ? _tr('كل حاجة محدّثة', 'Everything is up to date') : _tr('${total - okCount} تحديثات متاحة', '${total - okCount} updates available'),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            Text(_tr('التطبيق والهاب والمشتركات', 'App, hub and strips'), style: TextStyle(color: C.muted, fontSize: 12)),
          ]),
        ),
      ]),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double frac;
  final Color color;
  const _RingPainter(this.frac, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 5;
    final bg = Paint()
      ..color = Colors.white.withValues(alpha: .08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    final fg = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 6;
    canvas.drawCircle(c, r, bg);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, 2 * math.pi * frac, false, fg);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.frac != frac || old.color != color;
}
