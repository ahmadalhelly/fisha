part of '../strip_card.dart';

/// Switch an outlet, asking first if it needs biometric or is protected and being turned off.
Future<void> guardedSwitch(BuildContext context, AppState state, Strip s, Outlet o, bool on) async {
  // view members only look; control members leave overload-protected outlets alone
  if (!state.canControl || (o.protected && !state.can(Perm.prot))) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(!state.canControl
            ? (Tr.isAr ? 'صلاحيتك مشاهدة بس' : 'You can view only')
            : (Tr.isAr ? 'المخرج ده محمي، المالك بس اللي يغيّره' : 'This outlet is protected; only the owner can switch it'))));
    return;
  }
  if (!s.online) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('strip_offline_cmd'))));
    return;
  }
  if (!on && o.keepOn) {
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        icon: Icon(Icons.push_pin_outlined, color: C.accent),
        title: Text(Tr.isAr ? 'المخرج محمي (مفتوح دائمًا)' : 'Outlet kept always on', style: const TextStyle(fontSize: 18)),
        content: Text(Tr.isAr ? 'هذا المخرج تم ضبطه ليعمل دائمًا ولا يمكن إيقافه إلا إذا قمت بإلغاء إعداد «التشغيل دائماً» أولاً.' : 'This outlet is set to keep always on. To turn it off, disable the Keep Always On setting first.', style: TextStyle(color: C.textSoft)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'), style: TextStyle(color: C.muted))),
        ],
      ),
    );
    return;
  }
  if (state.requiresBio(s.mac, o.n)) {
    final reason = Tr.isAr
        ? 'تأكيد البصمة للتحكم في «${state.outletName(s, o.n)}»'
        : 'Authenticate to switch "${state.outletName(s, o.n)}"';
    final ok = await authenticateBio(reason);
    if (!ok || !context.mounted) return;
  }
  if (!on && o.protected) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        icon: Icon(Icons.shield_outlined, color: C.accent),
        title: Text(t('confirm_off_t', {'x': state.outletName(s, o.n)}), style: const TextStyle(fontSize: 18)),
        content: Text(t('confirm_off_b'), style: TextStyle(color: C.textSoft)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'), style: TextStyle(color: C.muted))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t('turn_off'), style: TextStyle(color: C.danger, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (ok != true) return;
  }
  await state.setOutlet(s.mac, o.n, on);
}

/// "All" with fingerprint-protected outlets: fingerprint first, then ask whether they are included too.
/// true = include them, false = only the rest, null = cancel (nothing is switched).
Future<bool?> _bioAllChoice(BuildContext context, AppState state, Strip s, List<Outlet> outs, bool on) async {
  final passed = await authenticateBio(on
      ? (Tr.isAr ? 'تأكيد البصمة لتشغيل الكل' : 'Authenticate for All On')
      : (Tr.isAr ? 'تأكيد البصمة لإيقاف الكل' : 'Authenticate for All Off'));
  if (!context.mounted) return null;
  final names = outs.map((o) => state.outletName(s, o.n)).join('، ');
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: C.surface,
      icon: Icon(Icons.fingerprint, color: C.accent),
      title: Text(t('bio_all_t'), style: const TextStyle(fontSize: 18)),
      content: Text(t(passed ? 'bio_all_b' : 'bio_all_failed', {'x': names}), style: TextStyle(color: C.textSoft, height: 1.5)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'), style: TextStyle(color: C.muted))),
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('bio_all_rest'), style: TextStyle(color: C.accent))),
        if (passed)
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t(on ? 'bio_all_on' : 'bio_all_off'), style: TextStyle(color: on ? C.accent : C.danger, fontWeight: FontWeight.w700))),
      ],
    ),
  );
}

/// "the whole strip" in one command only when no outlet is child-locked: the strip applies a whole-strip command to its
/// free outlets only, so a locked outlet stayed as it was. With a lock each outlet gets its own command.
bool _wholeStripOk(Strip s) => !s.masterLock && s.outlets.every((o) => !o.locked);

Future<void> guardedAllOn(BuildContext context, AppState state, Strip s) async {
  if (!s.online) return;
  if (state.requiresBio(s.mac, 0)) {
    if (!await authenticateBio(Tr.isAr ? 'تأكيد البصمة لتشغيل الكل' : 'Authenticate for All On')) return;
  }
  final bioOuts = s.outlets.where((o) => !o.on && state.requiresBio(s.mac, o.n)).toList();
  bool bioOk = true;
  if (bioOuts.isNotEmpty) {
    if (!context.mounted) return;
    final c = await _bioAllChoice(context, state, s, bioOuts, true);
    if (c == null) return;
    bioOk = c;
  }
  if (bioOk && _wholeStripOk(s)) {
    await state.setOutlet(s.mac, 0, true);
  } else {
    for (final o in s.outlets) {
      if (!o.on && (bioOk || !state.requiresBio(s.mac, o.n))) {
        await state.setOutlet(s.mac, o.n, true);
      }
    }
  }
}

Future<void> guardedAllOff(BuildContext context, AppState state, Strip s) async {
  if (!s.online) return;
  if (state.requiresBio(s.mac, 0)) {
    if (!await authenticateBio(Tr.isAr ? 'تأكيد البصمة لإيقاف الكل' : 'Authenticate for All Off')) return;
  }
  final bioOutlets = s.outlets.where((o) => o.on && state.requiresBio(s.mac, o.n)).toList();
  bool bioOk = true;
  if (bioOutlets.isNotEmpty) {
    if (!context.mounted) return;
    final c = await _bioAllChoice(context, state, s, bioOutlets, false);
    if (c == null) return;
    bioOk = c;
  }
  final targets = s.outlets.where((o) => o.on && !o.keepOn && (bioOk || !state.requiresBio(s.mac, o.n))).toList();
  if (targets.isEmpty) return;

  final protectedOn = targets.where((o) => o.protected).toList();
  if (protectedOn.isEmpty) {
    if (bioOk && _wholeStripOk(s) && targets.length == s.onCount && s.outlets.every((o) => !o.keepOn)) {
      return state.setOutlet(s.mac, 0, false);
    } else {
      for (final o in targets) {
        await state.setOutlet(s.mac, o.n, false);
      }
      return;
    }
  }

  if (!context.mounted) return;
  final names = protectedOn.map((o) => state.outletName(s, o.n)).join('، ');
  final choice = await showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: C.surface,
      icon: Icon(Icons.shield_outlined, color: C.accent),
      title: Text(t('all_off_prot_t'), style: const TextStyle(fontSize: 18)),
      content: Text(t('all_off_prot_b', {'x': names}), style: TextStyle(color: C.textSoft, height: 1.5)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, 0), child: Text(t('cancel'), style: TextStyle(color: C.muted))),
        TextButton(onPressed: () => Navigator.pop(ctx, 2), child: Text(t('all_off_all'), style: TextStyle(color: C.danger))),
        TextButton(
            onPressed: () => Navigator.pop(ctx, 1),
            child: Text(t('all_off_keep'), style: TextStyle(color: C.accent, fontWeight: FontWeight.w700))),
      ],
    ),
  );
  if (choice == 1) {
    for (final o in targets) {
      if (!o.protected) await state.setOutlet(s.mac, o.n, false);
    }
  } else if (choice == 2) {
    if (bioOk && _wholeStripOk(s) && targets.length == s.onCount && s.outlets.every((o) => !o.keepOn)) {
      await state.setOutlet(s.mac, 0, false);
    } else {
      for (final o in targets) {
        await state.setOutlet(s.mac, o.n, false);
      }
    }
  }
}
