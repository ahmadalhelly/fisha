import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'users_screen.dart';

/// First-run choice (local account or Google) and, later, the account page in Settings.
class AccountScreen extends StatefulWidget {
  final AppState state;
  final bool firstRun;
  const AccountScreen({super.key, required this.state, this.firstRun = false});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  AppState get s => widget.state;
  bool _busy = false;

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _run(Future<void> Function() f) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await f();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _local() => _run(() async {
        await s.useLocalAccount();
        if (!widget.firstRun && mounted) _snack(t('acc_local_on'));
      });

  Future<void> _google() => _run(() async {
        final err = await s.googleSignIn();
        if (err != null) {
          _snack(err);
          return;
        }
        if (await s.googleHasData() && mounted) {
          final yes = await confirmDialog(context, t('g_found_t'), t('g_found_b'), ok: t('g_restore'));
          if (yes) {
            final r = await s.restoreFromGoogle();
            _snack(r ?? t('g_restored'));
            return;
          }
        }
        final r = await s.syncNow();
        _snack(r ?? t('g_synced'));
      });

  Future<void> _join() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        title: Text(t('join_title'), style: const TextStyle(fontSize: 18)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t('join_sub'), style: TextStyle(color: C.textSoft, height: 1.5, fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            minLines: 2,
            maxLines: 4,
            textDirection: TextDirection.ltr,
            autocorrect: false,
            decoration: InputDecoration(
              hintText: t('join_hint'),
              suffixIcon: IconButton(
                icon: Icon(Icons.content_paste, color: C.muted),
                onPressed: () async {
                  final d = await Clipboard.getData(Clipboard.kTextPlain);
                  if (d?.text != null) ctrl.text = d!.text!;
                },
              ),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'), style: TextStyle(color: C.muted))),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(t('join_btn'))),
        ],
      ),
    );
    ctrl.dispose();
    if (code == null || code.trim().isEmpty) return;
    final inv = AppState.decodeInvite(code);
    if (inv == null) {
      _snack(t('join_bad'));
      return;
    }
    if (!mounted) return;
    final ok = await confirmDialog(context, t('join_title'), t('join_confirm', {'x': (inv['n'] ?? inv['u']).toString()}));
    if (!ok) return;
    await _run(() async {
      await s.joinWithCode(code);
      if (s.accountType.isEmpty) await s.setAccount('local');
      _snack(t('join_ok'));
    });
  }

  Future<void> _leave() async {
    if (!await confirmDialog(context, t('leave_title'), t('leave_body'), ok: t('leave_btn'), danger: true)) return;
    await _run(() async {
      await s.leaveShared();
      _snack(t('saved'));
    });
  }

  Widget _choice(IconData icon, String title, String sub, VoidCallback? onTap, {bool selected = false}) => InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: cardBox(radius: 18, color: selected ? C.tileOn : C.surface, border: selected ? C.tileOnBorder : C.border),
          child: Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: C.accentBg, borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: C.accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 3),
                Text(sub, style: TextStyle(color: C.textSoft, fontSize: 12, height: 1.4)),
              ]),
            ),
            if (selected) Icon(Icons.check_circle, color: C.accent),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      appBar: widget.firstRun
          ? null
          : AppBar(backgroundColor: C.bg, surfaceTintColor: Colors.transparent, title: Text(t('acc_title'), style: const TextStyle(fontWeight: FontWeight.w700))),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: s,
          builder: (context, _) => ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 24), children: [
            if (widget.firstRun) ...[
              const SizedBox(height: 28),
              Text(t('app_name'), textAlign: TextAlign.center, style: TextStyle(color: C.accent, fontSize: 30, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(t('acc_pick'), textAlign: TextAlign.center, style: TextStyle(color: C.textSoft, fontSize: 14, height: 1.5)),
              const SizedBox(height: 24),
            ],
            _choice(Icons.phone_android, t('acc_local'), t('acc_local_sub'), _busy ? null : _local, selected: s.accountType == 'local'),
            const SizedBox(height: 12),
            _choice(Icons.account_circle_outlined, t('acc_google'),
                s.accountType == 'google' && s.googleEmail.isNotEmpty ? s.googleEmail : t('acc_google_sub'), _busy ? null : _google,
                selected: s.accountType == 'google'),
            if (_busy) ...[const SizedBox(height: 16), const Center(child: CircularProgressIndicator())],
            if (s.accountType == 'google' && !widget.firstRun) ...[
              const SizedBox(height: 14),
              section(t('g_sync'), [
                Text(s.lastSync == null ? t('g_never') : t('g_last', {'x': _fmt(s.lastSync!)}), style: TextStyle(color: C.textSoft, fontSize: 13)),
                primaryButton(t('g_sync_now'), _busy ? null : () => _run(() async => _snack(await s.syncNow() ?? t('g_synced'))), icon: Icons.cloud_upload_outlined),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          if (!await confirmDialog(context, t('g_restore'), t('g_restore_b'))) return;
                          await _run(() async => _snack(await s.restoreFromGoogle() ?? t('g_restored')));
                        },
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: Text(t('g_restore')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: C.accent,
                    side: BorderSide(color: C.tileOnBorder),
                    minimumSize: const Size(0, 52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
                Text(t('g_note'), style: TextStyle(color: C.muted, fontSize: 12, height: 1.5)),
              ]),
            ],
            const SizedBox(height: 14),
            section(t('share_title'), [
              if (s.isShared) ...[
                Text(t('shared_banner', {'x': s.settings.sharedName.isEmpty ? s.settings.sharedUser : s.settings.sharedName}),
                    style: TextStyle(color: C.textSoft, fontSize: 13, height: 1.5)),
                Text('${t('role')}: ${t('role_${s.settings.sharedRole}')}', style: TextStyle(color: C.muted, fontSize: 12)),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _leave,
                  icon: const Icon(Icons.logout),
                  label: Text(t('leave_btn')),
                  style: OutlinedButton.styleFrom(foregroundColor: C.danger, side: BorderSide(color: C.border), minimumSize: const Size(0, 48)),
                ),
              ] else ...[
                if (!widget.firstRun)
                  primaryButton(t('users_title'), () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => UsersScreen(state: s))),
                      icon: Icons.group_add_outlined),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _join,
                  icon: const Icon(Icons.qr_code_2),
                  label: Text(t('join_title')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: C.accent,
                    side: BorderSide(color: C.tileOnBorder),
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ],
            ]),
          ]),
        ),
      ),
    );
  }

  String _fmt(DateTime d) {
    String p(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)} ${p(d.hour)}:${p(d.minute)}';
  }
}
