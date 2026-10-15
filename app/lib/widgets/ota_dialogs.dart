import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../theme.dart';

String _o(String ar, String en) => Tr.isAr ? ar : en;

/// Asks once for the hub update password when the saved one and the default were both refused.
Future<String?> askUpdatePassword(BuildContext context, AppState s) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: C.surface,
      title: Text(_o('باسورد تحديث الهاب', 'Hub update password'), style: const TextStyle(fontSize: 18)),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_o('الباسورد المحفوظ اترفض. اكتب الباسورد اللي إنت حاططه، أو الافتراضي:', 'The saved password was refused. Type your own, or the default:'),
            style: TextStyle(color: C.muted, fontSize: 12.5, height: 1.5)),
        const SizedBox(height: 6),
        SelectableText(s.defaultOtaPass, textDirection: TextDirection.ltr, style: mono(13, color: C.accent)),
        const SizedBox(height: 10),
        TextField(controller: ctrl, autofocus: true, obscureText: true, textDirection: TextDirection.ltr),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'), style: TextStyle(color: C.muted))),
        TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(t('save'))),
      ],
    ),
  );
}

/// Owner: reset / change the update password. Needs the default (or current) password, then the new one twice.
/// Leaving the new password empty puts the default fisha-<MAC> back.
Future<void> changeUpdatePasswordDialog(BuildContext context, AppState s) async {
  final cur = TextEditingController(), n1 = TextEditingController(), n2 = TextEditingController();
  String? err;
  bool busy = false;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        backgroundColor: C.surface,
        title: Text(_o('تغيير باسورد التحديث', 'Change update password'), style: const TextStyle(fontSize: 18)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_o('الباسورد الافتراضي الثابت لكل هاب:', 'The fixed default for every hub:'), style: TextStyle(color: C.muted, fontSize: 12.5)),
            const SizedBox(height: 4),
            SelectableText(s.defaultOtaPass, textDirection: TextDirection.ltr, style: mono(13, color: C.accent)),
            const SizedBox(height: 12),
            TextField(
                controller: cur,
                obscureText: true,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: _o('الباسورد الافتراضي أو الحالي', 'Default or current password'))),
            const SizedBox(height: 8),
            TextField(
                controller: n1,
                obscureText: true,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: _o('الباسورد الجديد (8 حروف على الأقل)', 'New password (8+ characters)'))),
            const SizedBox(height: 8),
            TextField(
                controller: n2,
                obscureText: true,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: _o('اكتب الجديد تاني', 'Repeat the new password'))),
            const SizedBox(height: 6),
            Text(_o('سيبه فاضي لو عاوز ترجّع الافتراضي.', 'Leave empty to go back to the default.'), style: TextStyle(color: C.muted, fontSize: 11.5)),
            if (err != null) ...[const SizedBox(height: 8), Text(err!, style: TextStyle(color: C.danger, fontSize: 12.5))],
          ]),
        ),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: Text(t('cancel'), style: TextStyle(color: C.muted))),
          TextButton(
            onPressed: busy
                ? null
                : () async {
                    if (n1.text != n2.text) {
                      set(() => err = _o('الباسوردين مش زي بعض.', 'The two passwords differ.'));
                      return;
                    }
                    if (n1.text.isNotEmpty && n1.text.length < 8) {
                      set(() => err = _o('8 حروف على الأقل.', 'At least 8 characters.'));
                      return;
                    }
                    set(() {
                      busy = true;
                      err = null;
                    });
                    final e = await s.changeOtaPass(cur.text.trim(), n1.text);
                    if (!ctx.mounted) return;
                    if (e == null) {
                      Navigator.pop(ctx);
                      return;
                    }
                    set(() {
                      busy = false;
                      err = e.contains('wrong') ? _o('الباسورد الحالي غلط.', 'Wrong current password.') : e;
                    });
                  },
            child: Text(t('save')),
          ),
        ],
      ),
    ),
  );
}
