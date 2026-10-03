import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Owner page: people the hub is shared with (hub 2.9+). Adding and removing people works on the home Wi-Fi.
class UsersScreen extends StatefulWidget {
  final AppState state;
  const UsersScreen({super.key, required this.state});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  AppState get s => widget.state;
  List<HubUser>? _users;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final u = await s.loadUsers();
    if (!mounted) return;
    setState(() {
      _users = u;
      _busy = false;
      if (u == null) _error = s.lastError ?? t('err_failed');
    });
  }

  Future<void> _emqx() async {
    final url = TextEditingController(), key = TextEditingController(), sec = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        title: Text(t('emqx_title'), style: const TextStyle(fontSize: 18)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t('emqx_sub'), style: TextStyle(color: C.textSoft, fontSize: 12, height: 1.5)),
            const SizedBox(height: 10),
            for (final (c, l, h) in [
              (url, t('emqx_url'), 'https://xxxx.ala.eu-central-1.emqxsl.com:8443/api/v5'),
              (key, t('emqx_key'), ''),
              (sec, t('emqx_secret'), ''),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: c,
                  textDirection: TextDirection.ltr,
                  autocorrect: false,
                  obscureText: c == sec,
                  decoration: InputDecoration(labelText: l, hintText: h.isEmpty ? null : h),
                ),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'), style: TextStyle(color: C.muted))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('save'))),
        ],
      ),
    );
    final u = url.text.trim(), k = key.text.trim(), sc = sec.text.trim();
    url.dispose();
    key.dispose();
    sec.dispose();
    if (ok != true) return;
    setState(() => _busy = true);
    final r = await s.setEmqx(u, k, sc);
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(r.ok ? t('emqx_ok') : (r.error ?? t('err_failed')));
    if (r.ok) _load();
  }

  /// Name, role and strips. Returns null when cancelled.
  Future<HubUser?> _editor({HubUser? initial}) async {
    final name = TextEditingController(text: initial?.name ?? '');
    var role = initial?.role ?? 1;
    var all = initial?.all ?? true;
    final picked = <String>{...?initial?.strips};
    final res = await showDialog<HubUser>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: C.surface,
          title: Text(initial == null ? t('user_new') : t('user_edit'), style: const TextStyle(fontSize: 18)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(controller: name, maxLength: 23, decoration: InputDecoration(labelText: t('user_name'))),
              const SizedBox(height: 6),
              Text(t('role'), style: TextStyle(color: C.muted, fontSize: 13)),
              const SizedBox(height: 6),
              Segmented<int>(value: role, items: {0: t('role_0'), 1: t('role_1'), 2: t('role_2')}, onChanged: (v) => setLocal(() => role = v)),
              const SizedBox(height: 6),
              Text(t('role_${role}_sub'), style: TextStyle(color: C.muted, fontSize: 12, height: 1.5)),
              const SizedBox(height: 12),
              Text(t('user_scope'), style: TextStyle(color: C.muted, fontSize: 13)),
              const SizedBox(height: 6),
              Segmented<bool>(value: all, items: {true: t('scope_all'), false: t('scope_some')}, onChanged: (v) => setLocal(() => all = v)),
              if (!all)
                for (final st in s.allStrips)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    activeColor: C.accent,
                    checkColor: C.onAccent,
                    value: picked.contains(st.mac.toUpperCase()),
                    title: Text(s.stripName(st)),
                    onChanged: (v) => setLocal(() => v == true ? picked.add(st.mac.toUpperCase()) : picked.remove(st.mac.toUpperCase())),
                  ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'), style: TextStyle(color: C.muted))),
            TextButton(
              onPressed: () => Navigator.pop(ctx, HubUser(id: initial?.id ?? '', name: name.text.trim(), role: role, all: all, strips: picked.toList())),
              child: Text(t('save')),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    if (res == null) return null;
    if (res.name.isEmpty || (!res.all && res.strips.isEmpty)) {
      _snack(t('user_incomplete'));
      return null;
    }
    return res;
  }

  Future<void> _invite() async {
    final u = await _editor();
    if (u == null) return;
    setState(() => _busy = true);
    final r = await s.inviteUser(u.name, u.role, u.all, u.strips);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      _snack(r.error ?? t('err_failed'));
      return;
    }
    final code = (r.data?['code'] ?? '').toString();
    await _load();
    if (!mounted || code.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        title: Text(t('invite_ready'), style: const TextStyle(fontSize: 18)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t('invite_how', {'x': u.name}), style: TextStyle(color: C.textSoft, fontSize: 13, height: 1.5)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(12)),
            child: SelectableText(code, textDirection: TextDirection.ltr, style: mono(11, color: C.accent, weight: FontWeight.w500)),
          ),
          const SizedBox(height: 8),
          Text(t('invite_private'), style: TextStyle(color: C.warn, fontSize: 12, height: 1.5)),
        ]),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (ctx.mounted) Navigator.pop(ctx);
              _snack(t('copied'));
            },
            child: Text(t('copy')),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(HubUser u) async {
    final e = await _editor(initial: u);
    if (e == null) return;
    setState(() => _busy = true);
    final r = await s.updateUser(e);
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(r.ok ? t('saved') : (r.error ?? t('err_failed')));
    _load();
  }

  Future<void> _revoke(HubUser u) async {
    if (!await confirmDialog(context, t('user_revoke'), t('user_revoke_b', {'x': u.name}), ok: t('user_revoke'), danger: true)) return;
    setState(() => _busy = true);
    final r = await s.revokeUser(u.id);
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(r.ok ? t('user_revoked') : (r.error ?? t('err_failed')));
    _load();
  }

  String _scopeText(HubUser u) {
    if (u.all) return t('scope_all');
    final names = [
      for (final m in u.strips)
        for (final st in s.allStrips)
          if (st.mac.toUpperCase() == m) s.stripName(st)
    ];
    return names.isEmpty ? '${u.strips.length}' : names.join('، ');
  }

  @override
  Widget build(BuildContext context) {
    final users = _users;
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(backgroundColor: C.bg, surfaceTintColor: Colors.transparent, title: Text(t('users_title'), style: const TextStyle(fontWeight: FontWeight.w700))),
      floatingActionButton: s.emqxSet && !_busy
          ? FloatingActionButton.extended(
              onPressed: _invite,
              backgroundColor: C.accent,
              foregroundColor: C.onAccent,
              icon: const Icon(Icons.person_add_alt),
              label: Text(t('user_new')),
            )
          : null,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 96), children: [
            if (s.mode != ConnMode.local) ...[emptyCard(t('users_local_note'), icon: Icons.wifi), const SizedBox(height: 14)],
            if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
            if (_error != null) ...[emptyCard(_error!, icon: Icons.error_outline), const SizedBox(height: 14)],
            section(t('emqx_title'), [
              Text(s.emqxSet ? t('emqx_set') : t('users_need_emqx'), style: TextStyle(color: C.textSoft, fontSize: 13, height: 1.5)),
              OutlinedButton.icon(
                onPressed: _busy ? null : _emqx,
                icon: const Icon(Icons.key_outlined),
                label: Text(s.emqxSet ? t('emqx_change') : t('emqx_title')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: C.accent,
                  side: BorderSide(color: C.tileOnBorder),
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            if (users != null && users.isEmpty) emptyCard(t('users_empty'), icon: Icons.group_outlined),
            if (users != null)
              for (final u in users) ...[
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                  decoration: cardBox(radius: 18),
                  child: Row(children: [
                    Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: C.accentBg, shape: BoxShape.circle),
                      child: Text(u.name.isEmpty ? '?' : u.name.characters.first, style: TextStyle(color: C.accent, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(u.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text('${t('role_${u.role}')} · ${_scopeText(u)}', style: TextStyle(color: C.textSoft, fontSize: 12)),
                      ]),
                    ),
                    IconButton(icon: Icon(Icons.edit_outlined, color: C.muted), onPressed: _busy ? null : () => _edit(u)),
                    IconButton(icon: Icon(Icons.person_remove_outlined, color: C.danger), onPressed: _busy ? null : () => _revoke(u)),
                  ]),
                ),
                const SizedBox(height: 10),
              ],
          ]),
        ),
      ),
    );
  }
}
