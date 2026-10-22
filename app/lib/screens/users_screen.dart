import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Owner page: people the hub is shared with. Adding and removing people works on the home Wi-Fi.
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
    var perms = initial?.perms ?? 0;
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
              // what this person may do on top of the role (admins already have all of it)
              if (role < 2) ...[
                const SizedBox(height: 12),
                Text(t('perm_title'), style: TextStyle(color: C.muted, fontSize: 13)),
                for (final p in [Perm.auto, Perm.prot, Perm.stripFw, Perm.wifi, Perm.hubFw, Perm.export])
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    activeColor: C.accent,
                    checkColor: C.onAccent,
                    value: perms & p != 0,
                    title: Text(t('perm_$p')),
                    onChanged: (v) => setLocal(() => perms = v == true ? perms | p : perms & ~p),
                  ),
              ],
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
              onPressed: () => Navigator.pop(ctx, HubUser(id: initial?.id ?? '', name: name.text.trim(), role: role, perms: role < 2 ? perms : 0, email: initial?.email ?? '', photo: initial?.photo ?? '', all: all, strips: picked.toList())),
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
    final r = await s.inviteUser(u.name, u.role, u.all, u.strips, perms: u.perms);
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

  // the owner (this phone's Google account) heads the list with the same photo/name/email card as members
  Widget _ownerCard() {
    final mine = s.isOwner;
    final others = [for (final o in s.ownerPhones) if (!mine || o.email.toLowerCase() != s.googleEmail.toLowerCase()) o];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (mine)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: cardBox(radius: 20),
          child: Row(children: [
            Avatar(photo: s.googlePhoto, name: s.userName.isEmpty ? s.googleEmail : s.userName, size: 48, ring: roleColor(3)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.userName.isEmpty ? s.googleEmail.split('@').first : s.userName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                if (s.googleEmail.isNotEmpty) SelectableText(s.googleEmail, textDirection: TextDirection.ltr, style: TextStyle(color: C.muted, fontSize: 12)),
              ]),
            ),
            roleChip(3),
          ]),
        ),
      for (final o in others) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: cardBox(radius: 20),
          child: Row(children: [
            Avatar(photo: '', name: o.email, size: 48, ring: roleColor(3)),
            const SizedBox(width: 12),
            Expanded(child: SelectableText(o.email, textDirection: TextDirection.ltr, style: TextStyle(color: C.muted, fontSize: 12.5))),
            roleChip(3),
          ]),
        ),
      ],
    ]);
  }

  // family page "ب": one expanded card per member: Google photo, name, email, role, strips and extra permissions
  Widget _memberCard(HubUser u) {
    final extras = [for (final p in [Perm.auto, Perm.prot, Perm.stripFw, Perm.wifi, Perm.hubFw, Perm.export]) if (u.perms & p != 0) t('perm_$p')];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: cardBox(radius: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Avatar(photo: u.photo, name: u.name, size: 48, ring: roleColor(u.role)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(u.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              u.email.isEmpty
                  ? Text(t('member_no_email'), style: TextStyle(color: C.faint, fontSize: 12))
                  : SelectableText(u.email, textDirection: TextDirection.ltr, style: TextStyle(color: C.muted, fontSize: 12)),
            ]),
          ),
          roleChip(u.role),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: C.surface2.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.power_outlined, size: 15, color: C.muted),
              const SizedBox(width: 6),
              Expanded(child: Text(_scopeText(u), style: TextStyle(color: C.textSoft, fontSize: 12.5))),
            ]),
            const SizedBox(height: 6),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.verified_user_outlined, size: 15, color: C.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(u.role >= 2 ? t('perm_all') : extras.isEmpty ? t('perm_none') : extras.join(' · '),
                    style: TextStyle(color: C.textSoft, fontSize: 12.5, height: 1.4)),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton.icon(
              onPressed: _busy ? null : () => _edit(u), icon: const Icon(Icons.edit_outlined, size: 18), label: Text(t('user_edit'))),
          TextButton.icon(
              onPressed: _busy ? null : () => _revoke(u),
              style: TextButton.styleFrom(foregroundColor: C.danger),
              icon: const Icon(Icons.person_remove_outlined, size: 18),
              label: Text(t('user_revoke'))),
        ]),
      ]),
    );
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
            _ownerCard(),
            const SizedBox(height: 10),
            if (users != null && users.isEmpty) emptyCard(t('users_empty'), icon: Icons.group_outlined),
            if (users != null)
              for (final u in users) ...[
                _memberCard(u),
                const SizedBox(height: 10),
              ],
          ]),
        ),
      ),
    );
  }
}
