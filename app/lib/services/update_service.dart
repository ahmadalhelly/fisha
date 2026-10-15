import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// One published build on the public repo ahmadalhelly/fisha-app (CI copies every app and hub build there).
class Release {
  final String kind; // 'app' or 'hub'
  final String version; // 2.0.16 / 2.15.12
  final int build; // CI run number
  final String notes; // Arabic bullets from the commit messages (markdown)
  final DateTime published;
  final String url; // download of the .apk / .bin
  final int size;
  const Release(this.kind, this.version, this.build, this.notes, this.published, this.url, this.size);

  /// notes as plain lines: headings and bullets without their markdown marks, empty lines dropped
  List<String> get lines => [
        for (final l in const LineSplitter().convert(notes))
          if (l.trim().isNotEmpty && !l.startsWith('#') && !l.startsWith('Branch:')) l.trim().replaceFirst(RegExp(r'^[-*]\s+'), ''),
      ];
}

/// Compares dotted versions numerically ("2.0.16" > "2.0.9"); non-numeric parts count as 0.
int compareVersions(String a, String b) {
  final pa = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final pb = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  for (var i = 0; i < 4; i++) {
    final x = i < pa.length ? pa[i] : 0, y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

/// Update center data: reads the releases of the public repo, at most every 6 hours unless asked.
class UpdateService extends ChangeNotifier {
  UpdateService._();
  static final instance = UpdateService._();

  static const repo = 'ahmadalhelly/fisha-app';
  static const _every = Duration(hours: 6);

  List<Release> releases = [];
  DateTime? checkedAt;
  bool loading = false;
  String? error; // 'net' or 'rate'
  String dismissed = ''; // the "app|hub" versions whose home banner the user closed

  static final _tag = RegExp(r'^(app|hub)-(\d+(?:\.\d+)+)-(?:build|run)-(\d+)$');

  Release? latest(String kind) {
    Release? best;
    for (final r in releases) {
      if (r.kind != kind) continue;
      if (best == null || compareVersions(r.version, best.version) > 0 || (compareVersions(r.version, best.version) == 0 && r.build > best.build)) best = r;
    }
    return best;
  }

  /// The release right before [latest] for the same kind — used to show "current + previous" only, never
  /// the full history.
  Release? previous(String kind) {
    final l = latest(kind);
    if (l == null) return null;
    Release? best;
    for (final r in releases) {
      if (r.kind != kind || identical(r, l)) continue;
      if (compareVersions(r.version, l.version) == 0 && r.build == l.build) continue;
      if (best == null || compareVersions(r.version, best.version) > 0 || (compareVersions(r.version, best.version) == 0 && r.build > best.build)) best = r;
    }
    return best;
  }

  /// 2.0.20: the latest strip firmware we publish. Strip builds aren't on CI yet, so this is kept in sync by hand
  /// with the newest .fwr we've shipped (see the strip-firmware notes).
  static const latestStripFw = '1.0.82';

  /// the newer release for [kind] than [current], or null when up to date or unknown
  Release? newer(String kind, String? current) {
    final l = latest(kind);
    if (l == null || current == null || current.isEmpty || current == 'dev') return null;
    return compareVersions(l.version, current) > 0 ? l : null;
  }

  Future<void> _loadPrefs() async {
    if (checkedAt != null || releases.isNotEmpty) return;
    final p = await SharedPreferences.getInstance();
    final at = p.getInt('upd_at') ?? 0;
    if (at > 0) checkedAt = DateTime.fromMillisecondsSinceEpoch(at);
    dismissed = p.getString('upd_dismissed') ?? '';
    final cached = p.getString('upd_cache');
    if (cached != null) _parse(cached);
  }

  Future<void> dismiss(String key) async {
    dismissed = key;
    notifyListeners();
    (await SharedPreferences.getInstance()).setString('upd_dismissed', key);
  }

  /// checks GitHub when the last check is older than 6 hours (or [force])
  Future<void> check({bool force = false}) async {
    if (kIsWeb || loading) return;
    await _loadPrefs();
    if (!force && checkedAt != null && DateTime.now().difference(checkedAt!) < _every) {
      notifyListeners();
      return;
    }
    loading = true;
    error = null;
    notifyListeners();
    try {
      final res = await http
          .get(Uri.parse('https://api.github.com/repos/$repo/releases?per_page=40'), headers: {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        _parse(res.body);
        checkedAt = DateTime.now();
        final p = await SharedPreferences.getInstance();
        await p.setString('upd_cache', res.body);
        await p.setInt('upd_at', checkedAt!.millisecondsSinceEpoch);
      } else {
        error = res.statusCode == 403 || res.statusCode == 429 ? 'rate' : 'net';
      }
    } catch (_) {
      error = 'net';
    }
    loading = false;
    notifyListeners();
  }

  void _parse(String body) {
    try {
      final out = <Release>[];
      for (final j in (jsonDecode(body) as List)) {
        final m = _tag.firstMatch((j['tag_name'] ?? '').toString());
        if (m == null || j['draft'] == true) continue;
        final kind = m.group(1)!;
        final assets = (j['assets'] as List? ?? []).cast<Map>();
        final a = assets.cast<Map?>().firstWhere(
            (x) => (x!['name'] ?? '').toString().toLowerCase().endsWith(kind == 'app' ? '.apk' : '.bin'),
            orElse: () => null);
        if (a == null) continue;
        out.add(Release(kind, m.group(2)!, int.parse(m.group(3)!), (j['body'] ?? '').toString(),
            DateTime.tryParse((j['published_at'] ?? '').toString())?.toLocal() ?? DateTime.now(), a['browser_download_url'].toString(), (a['size'] as num?)?.toInt() ?? 0));
      }
      out.sort((a, b) => b.published.compareTo(a.published));
      releases = out;
    } catch (_) {}
  }
}
