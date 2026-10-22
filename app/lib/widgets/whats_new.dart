import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../screens/about_screen.dart';
import '../screens/settings_screen.dart' show appVersion, appBuild;
import '../services/update_service.dart';
import '../theme.dart';

String _tr(String ar, String en) => Tr.isAr ? ar : en;

/// "What's new" once after an update: the app after its own update, the hub after its firmware changed.
/// A first install (nothing seen yet) only remembers the version, so a new user is not greeted with it.
class WhatsNew {
  static bool _busy = false, _again = false;

  /// one check at a time (two at once could each show the same box); a call that comes meanwhile runs after it
  static Future<void> check(BuildContext context, AppState s) async {
    if (!context.mounted) return;
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      do {
        _again = false;
        await _check(context, s);
      } while (_again && context.mounted);
    } finally {
      _busy = false;
    }
  }

  static Future<void> _check(BuildContext context, AppState s) async {
    final p = await SharedPreferences.getInstance();
    if (appBuild > 0) {
      final cur = '$appVersion+$appBuild';
      final seen = p.getString('wn_app');
      if (seen == null) {
        await p.setString('wn_app', cur);
      } else if (seen != cur) {
        if (!context.mounted) return;
        await _show(context, _tr('التطبيق اتحدّث لـ $appVersion', 'The app is now $appVersion'), _points('app', appBuild));
        await p.setString('wn_app', cur);
      }
    }
    final fw = s.hubFw, id = s.settings.hubId.toUpperCase();
    if (fw != null && id.isNotEmpty && s.hubBuild > 0) {
      final key = 'wn_hub_$id', cur = '$fw+${s.hubBuild}';
      final seen = p.getString(key);
      if (seen == null) {
        await p.setString(key, cur);
      } else if (seen != cur) {
        if (!context.mounted) return;
        await _show(context, _tr('الهاب اتحدّث لـ $fw', 'The hub is now $fw'), _points('hub', s.hubBuild));
        await p.setString(key, cur);
      }
    }
  }

  /// the release notes of that exact build (the update center already has them), else the About list
  static List<String> _points(String kind, int build) {
    for (final r in UpdateService.instance.releases) {
      if (r.kind == kind && r.build == build) {
        final l = r.lines;
        if (l.isNotEmpty) return l.take(4).toList();
      }
    }
    return kind == 'app' ? AboutScreen.latestTitles.take(4).toList() : const [];
  }

  static Future<void> _show(BuildContext context, String title, List<String> points) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        title: Row(children: [
          Icon(Icons.auto_awesome, color: C.accent),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (points.isEmpty) Text(_tr('فيه تحسينات وإصلاحات جديدة.', 'New improvements and fixes.'), style: TextStyle(color: C.textSoft)),
          for (final x in points)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.only(top: 6), child: Icon(Icons.circle, size: 6, color: C.accent)),
                const SizedBox(width: 10),
                Expanded(child: Text(x, style: TextStyle(color: C.textSoft, height: 1.45))),
              ]),
            ),
          const SizedBox(height: 8),
          Text(_tr('التفاصيل في الإعدادات ← عن التطبيق.', 'Details in Settings → About.'), style: TextStyle(color: C.muted, fontSize: 12)),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_tr('تمام', 'OK'), style: TextStyle(color: C.accent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
