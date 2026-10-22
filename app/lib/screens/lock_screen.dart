import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'account_screen.dart' show joinWithInviteDialog;
import 'connection_screen.dart';

String _tr(String ar, String en) => Tr.isAr ? ar : en;

void _snack(BuildContext context, String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

/// Signs in with Google (and offers the Drive backup, which brings this account's hub key back). Null when done.
Future<String?> _googleIn(BuildContext context, AppState s) async {
  final err = await s.googleSignIn();
  if (err != null) return err;
  final has = await s.googleHasData();
  if (has == true && context.mounted && await confirmDialog(context, t('g_found_t'), t('g_found_b'), ok: t('g_restore'))) {
    return await s.restoreFromGoogle();
  }
  return null;
}

/// shown instead of the app when the hub refuses this phone. The phone asks for access with the
/// signed-in Google account, shows a number, and the owner picks the same number on their phone.
class AccessScreen extends StatefulWidget {
  final AppState state;
  const AccessScreen({super.key, required this.state});

  @override
  State<AccessScreen> createState() => _AccessScreenState();
}

class _AccessScreenState extends State<AccessScreen> {
  AppState get s => widget.state;
  String _phase = 'idle'; // idle · waiting · refused · expired · claim
  int _id = 0, _code = 0;
  Timer? _poll;
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() f) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await f();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() => _run(() async {
        final e = await _googleIn(context, s);
        if (e != null && mounted) setState(() => _err = e);
      });

  Future<void> _ask() => _run(() async {
        final r = await s.requestAccess();
        if (!mounted) return;
        if (r.error != null) {
          setState(() => _err = r.error);
          return;
        }
        setState(() {
          _id = r.id;
          _code = r.code;
          _phase = 'waiting';
        });
        _poll?.cancel();
        _poll = Timer.periodic(const Duration(seconds: 2), (_) async {
          final st = await s.pollAccess(_id, _code);
          if (!mounted || _phase != 'waiting') return;
          if (st == 'refused' || st == 'expired') {
            _poll?.cancel();
            setState(() => _phase = st);
          }
          // ok: the app opens by itself (the hub stops refusing this phone)
        });
      });

  void _cancel() {
    _poll?.cancel();
    setState(() => _phase = 'idle');
  }

  @override
  Widget build(BuildContext context) {
    final signed = s.accountType == 'google' && s.googleEmail.isNotEmpty;
    return Scaffold(
      backgroundColor: C.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 36, 22, 24),
          children: [
            const Center(child: BrandMark(size: 64)),
            const SizedBox(height: 14),
            Text(_phase == 'claim' ? _tr('إنت صاحب الهاب؟', 'Is this your hub?') : _tr('الـ Hub مقفول', 'The hub is locked'),
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
                _phase == 'claim'
                    ? _tr('أول تليفون بيقفل الهاب بيبقى تليفون المالك. من غير باسورد.', 'The first phone to lock the hub becomes the owner phone. No password needed.')
                    : _tr('عشان تشوف مشتركات البيت، صاحب الهاب لازم يوافق على التليفون ده.', 'To see the strips at home, the hub owner has to approve this phone.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: C.muted, fontSize: 13, height: 1.6)),
            const SizedBox(height: 22),
            if (signed) _account() else primaryButton(_tr('الدخول بجوجل', 'Sign in with Google'), _busy ? null : _google, icon: Icons.login),
            const SizedBox(height: 18),
            if (signed) ...[
              if (_phase == 'idle') primaryButton(_tr('اطلب دخول', 'Ask for access'), _busy ? null : _ask, icon: Icons.phonelink_lock_outlined),
              if (_phase == 'waiting') _waiting(),
              if (_phase == 'refused' || _phase == 'expired') _ended(),
              if (_phase == 'claim') ClaimForm(state: s, onDone: () {}),
            ],
            if (_err != null) ...[
              const SizedBox(height: 12),
              Text(_err!, textAlign: TextAlign.center, style: TextStyle(color: C.danger, fontSize: 13)),
            ],
            const SizedBox(height: 26),
            Wrap(alignment: WrapAlignment.center, spacing: 4, runSpacing: 2, children: [
              if (signed && _phase != 'claim')
                TextButton(onPressed: () => setState(() => _phase = 'claim'), child: Text(_tr('أنا صاحب الهاب', 'I own this hub'))),
              if (_phase == 'claim') TextButton(onPressed: () => setState(() => _phase = 'idle'), child: Text(_tr('رجوع', 'Back'))),
              TextButton(onPressed: () => joinWithInviteDialog(context, s), child: Text(_tr('عندي كود دعوة', 'I have an invite code'))),
              TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ConnectionScreen(state: s))),
                  child: Text(_tr('إعدادات الاتصال', 'Connection settings'))),
              if (signed) TextButton(onPressed: () => s.logout(), child: Text(t('acc_logout'), style: TextStyle(color: C.muted))),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _account() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: cardBox(radius: 16),
        child: Row(children: [
          Icon(Icons.account_circle_outlined, color: C.accent),
          const SizedBox(width: 10),
          Expanded(
              child: Text(s.googleEmail, textDirection: TextDirection.ltr, style: mono(13, color: C.textSoft), overflow: TextOverflow.ellipsis)),
        ]),
      );

  Widget _waiting() => Container(
        padding: const EdgeInsets.all(18),
        decoration: cardBox(radius: 20),
        child: Column(children: [
          Text(_tr('قول الرقم ده لصاحب الهاب', 'Tell the hub owner this number'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 4),
          Text(_tr('هيختار نفس الرقم على تليفونه عشان يوافق', 'They pick the same number on their phone to approve'),
              textAlign: TextAlign.center, style: TextStyle(color: C.muted, fontSize: 12.5)),
          const SizedBox(height: 14),
          Text('$_code',
              style: mono(52, color: C.accent).copyWith(fontWeight: FontWeight.w600, shadows: [Shadow(color: C.accent.withValues(alpha: .35), blurRadius: 22)])),
          const SizedBox(height: 6),
          Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: C.muted)),
            const SizedBox(width: 8),
            Text(_tr('مستنيين الموافقة · الطلب صالح 5 دقايق', 'Waiting for approval · valid for 5 minutes'), style: TextStyle(color: C.muted, fontSize: 12)),
          ]),
          const SizedBox(height: 14),
          OutlinedButton(onPressed: _cancel, child: Text(_tr('إلغاء الطلب', 'Cancel request'))),
        ]),
      );

  Widget _ended() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
            _phase == 'refused'
                ? _tr('صاحب الهاب رفض الطلب، أو اختار رقم غلط.', 'The owner refused the request, or picked a wrong number.')
                : _tr('الطلب انتهى قبل ما يتوافق عليه.', 'The request expired before it was approved.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: _phase == 'refused' ? C.danger : C.warn, fontSize: 13)),
        const SizedBox(height: 12),
        primaryButton(_tr('اطلب تاني', 'Ask again'), _busy ? null : _ask, icon: Icons.refresh),
      ]);
}

/// The update password proves the hub is yours; this phone then holds the owner key.
class ClaimForm extends StatefulWidget {
  final AppState state;
  final VoidCallback onDone;
  const ClaimForm({super.key, required this.state, required this.onDone});

  @override
  State<ClaimForm> createState() => _ClaimFormState();
}

class _ClaimFormState extends State<ClaimForm> {
  bool _busy = false;
  String? _err;
  bool _needPass = false;                       // the hub already has an owner: the update password wins ownership back
  final _pass = TextEditingController();

  @override
  void dispose() {
    _pass.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    final e = await widget.state.claimHub(_pass.text.trim());
    if (!mounted) return;
    setState(() {
      _busy = false;
      _err = e;
      if (e == t('lock_claimed')) _needPass = true;
    });
    if (e == null) {
      _snack(context, _tr('الـ Hub اتقفل. أي تليفون تاني محتاج موافقتك.', 'Hub locked. Any other phone now needs your approval.'));
      widget.onDone();
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_err != null) ...[
          Text(_err!, style: TextStyle(color: C.danger, fontSize: 12.5)),
          const SizedBox(height: 8),
        ],
        if (_needPass) ...[
          TextField(
              controller: _pass,
              textDirection: TextDirection.ltr,
              autocorrect: false,
              decoration: InputDecoration(labelText: _tr('باسورد تحديث الهاب', 'Hub update password'))),
          const SizedBox(height: 10),
        ],
        primaryButton(_tr('اقفل الهاب على التليفون ده', 'Lock the hub to this phone'), _busy ? null : _go, icon: Icons.lock_outline),
      ]);
}

/// Settings → hub lock: whether the hub is locked, the owner phones, and locking it the first time.
class HubLockScreen extends StatelessWidget {
  final AppState state;
  const HubLockScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final s = state;
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
          backgroundColor: C.bg,
          surfaceTintColor: Colors.transparent,
          title: Text(_tr('قفل الهاب', 'Hub lock'), style: const TextStyle(fontWeight: FontWeight.w700))),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: s,
          builder: (context, _) {
            final signed = s.accountType == 'google' && s.googleEmail.isNotEmpty;
            final claimed = s.hubClaimed;
            return ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 30), children: [
              _status(claimed),
              const SizedBox(height: 14),
              if (claimed == false)
                section(_tr('اقفله دلوقتي', 'Lock it now'), [
                  if (!signed) ...[
                    Text(_tr('القفل مربوط بحساب جوجل بتاعك.', 'The lock is tied to your Google account.'), style: TextStyle(color: C.textSoft, fontSize: 13)),
                    primaryButton(_tr('الدخول بجوجل', 'Sign in with Google'), () async {
                      final e = await _googleIn(context, s);
                      if (e != null && context.mounted) _snack(context, e);
                    }, icon: Icons.login),
                  ] else
                    ClaimForm(state: s, onDone: () {}),
                ]),
              if (claimed == true) ...[
                section(_tr('تليفونات المالك', 'Owner phones'), [
                  for (final o in s.ownerPhones) _owner(context, o),
                  if (s.ownerPhones.isEmpty) Text('—', style: TextStyle(color: C.muted)),
                ]),
                const SizedBox(height: 14),
                Text(
                    _tr('تليفونات أهل البيت اللي وافقت عليها بتظهر في صفحة العائلة، ومن هناك تغيّر صلاحيتها أو تشيلها.',
                        'Family phones you approved are listed on the Family page, where you can change or remove them.'),
                    style: TextStyle(color: C.muted, fontSize: 12.5, height: 1.6)),
              ],
            ]);
          },
        ),
      ),
    );
  }

  Widget _status(bool? claimed) {
    final (icon, color, title, sub) = switch (claimed) {
      true => (Icons.lock_outline, C.accent, _tr('مقفول', 'Locked'),
          _tr('أي تليفون جديد لازم توافق عليه، حتى لو على واي فاي البيت.', 'Every new phone needs your approval, even on the home Wi-Fi.')),
      false => (Icons.lock_open_outlined, C.warn, _tr('مفتوح', 'Open'),
          _tr('أي حد على واي فاي البيت يقدر يشوف ويتحكم في مشتركاتك.', 'Anyone on the home Wi-Fi can see and control your strips.')),
      null => (Icons.system_update_alt, C.muted, _tr('محتاج تحديث للهاب', 'Hub update needed'),
          _tr('القفل محتاج آخر فيرموير للهاب، ومحتاج تكون على واي فاي البيت.', 'The lock needs the latest hub firmware, on the home Wi-Fi.')),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardBox(border: color.withValues(alpha: .45)),
      child: Row(children: [
        Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: color)),
        const SizedBox(width: 12),
        Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: color)),
          const SizedBox(height: 2),
          Text(sub, style: TextStyle(color: C.textSoft, fontSize: 12.5, height: 1.5)),
        ])),
      ]),
    );
  }

  Widget _owner(BuildContext context, OwnerPhone o) {
    final me = o.email == state.googleEmail.toLowerCase();
    return Row(children: [
      Icon(Icons.smartphone, color: C.accent, size: 22),
      const SizedBox(width: 10),
      Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(o.email, textDirection: TextDirection.ltr, style: mono(12.5, color: C.text), overflow: TextOverflow.ellipsis),
        Text([o.model, if (me) _tr('حسابك', 'your account')].join(' · '), style: TextStyle(color: C.muted, fontSize: 11.5)),
      ])),
      IconButton(
        tooltip: _tr('شيل', 'Remove'),
        icon: Icon(Icons.close, color: C.muted, size: 20),
        onPressed: () async {
          final last = state.ownerPhones.length == 1;
          final ok = await confirmDialog(
              context,
              _tr('تشيل التليفون ده؟', 'Remove this phone?'),
              last
                  ? _tr('ده آخر تليفون مالك، والهاب هيرجع مفتوح لأي حد على الواي فاي.', 'This is the last owner phone; the hub will be open to anyone on the Wi-Fi again.')
                  : _tr('التليفون ده مش هيقدر يدخل تاني من غير موافقة.', 'That phone will need approval to get back in.'),
              ok: _tr('شيل', 'Remove'),
              danger: true);
          if (!ok) return;
          final r = await state.removeOwnerPhone(o.email);
          if (context.mounted && !r.ok) _snack(context, r.error ?? t('err_failed'));
        },
      ),
    ]);
  }
}

/// The owner's answer to a phone asking in: pick the number that phone shows (one of 3), or refuse.
Future<void> showPairSheet(BuildContext context, AppState s, PairRequest p) async {
  var role = 1;
  final res = await showModalBottomSheet<int>(
    context: context,
    backgroundColor: C.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: C.border, borderRadius: BorderRadius.circular(4)))),
            const SizedBox(height: 14),
            Text(_tr('تليفون جديد طالب يدخل', 'A new phone wants access'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.email, textDirection: TextDirection.ltr, style: mono(13, color: C.text)),
                if (p.model.isNotEmpty) Text(p.model, style: TextStyle(color: C.muted, fontSize: 12)),
              ]),
            ),
            const SizedBox(height: 12),
            if (p.owner)
              Text(_tr('ده نفس إيميلك، فالتليفون ده هيبقى تليفون مالك.', 'This is your own email, so it becomes an owner phone.'),
                  style: TextStyle(color: C.accent, fontSize: 12.5))
            else
              Segmented<int>(value: role, items: {1: _tr('تحكم', 'Control'), 0: _tr('مشاهدة', 'View only')}, onChanged: (v) => setSt(() => role = v)),
            const SizedBox(height: 14),
            Text(_tr('اختار الرقم اللي ظاهر على التليفون ده. لو مش قدامك، ارفض.', 'Pick the number shown on that phone. If it isn\'t in front of you, refuse.'),
                style: TextStyle(color: C.textSoft, fontSize: 12.5)),
            const SizedBox(height: 10),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Row(children: [
                for (final n in p.choices)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 60),
                            side: BorderSide(color: C.border),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                        onPressed: () => Navigator.pop(ctx, n),
                        child: Text('$n', style: mono(24, color: C.text)),
                      ),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(ctx, -1),
              child: Text(_tr('مش أنا · رفض', 'Not me · refuse'), style: TextStyle(color: C.danger, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ),
    ),
  );
  if (res == null) return; // closed: the request stays until it expires
  final r = await s.answerPair(p.id, res < 0 ? 0 : res, res < 0 ? -1 : role);
  if (!context.mounted) return;
  _snack(
      context,
      !r.ok
          ? (r.error ?? t('err_failed'))
          : res < 0
              ? _tr('اترفض الطلب', 'Request refused')
              : _tr('اتوافق. التليفون هيدخل خلال ثواني.', 'Approved. The phone gets in within seconds.'));
}
