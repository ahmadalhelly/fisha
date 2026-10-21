import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// One published build on the public repo ahmadalhelly/fisha-app (CI copies every app and hub build there).
class Release {
  final String kind; // 'app', 'hub' or 'strip'
  final String version; // app/Hub release version or strip firmware version without the F prefix
  final int build; // CI run number; strip firmware releases have no CI build number
  final String notes; // Arabic bullets from the commit messages (markdown)
  final DateTime published;
  final String url; // download of the .apk / .bin / .fwr
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
  static final _stripTag = RegExp(r'^strip-F(\d+(?:\.\d+)+)$', caseSensitive: false);
  static final _stripVersion = RegExp(r'F(\d+(?:\.\d+)+)', caseSensitive: false);

  static String? stripVersion(String firmware) => _stripVersion.firstMatch(firmware)?.group(1);

  /// 2.0.29: the newest build, by CI build number (always rising), not by version name: the public launch restarts
  /// the versions at 1.0.0, which must still count as newer than the internal 2.x builds.
  Release? latest(String kind) {
    Release? best;
    for (final r in releases) {
      if (r.kind != kind) continue;
      if (best == null ||
          (kind == 'strip'
              ? compareVersions(r.version, best.version) > 0 ||
                  (compareVersions(r.version, best.version) == 0 && r.published.isAfter(best.published))
              : r.build > best.build)) {
        best = r;
      }
    }
    return best;
  }

  /// the CI build number of the installed [version], from its release (the highest one if it was built twice)
  int? buildOf(String kind, String version) {
    int? b;
    for (final r in releases) {
      if (r.kind == kind && compareVersions(r.version, version) == 0 && (b == null || r.build > b)) b = r.build;
    }
    return b;
  }

  /// the internal numbering used before the public launch (app 2.0.x, hub 2.13-2.15). Any launch version counts as
  /// newer than these. Only matters when that old release is no longer listed (see [newer]).
  static bool isPreLaunch(String v) => (int.tryParse(v.split('.').first) ?? 0) == 2;

  /// the newer release for [kind] than [current], or null when up to date or unknown
  Release? newer(String kind, String? current) {
    final l = latest(kind);
    if (l == null || current == null || current.isEmpty || current == 'dev') return null;
    if (kind == 'strip') {
      final cur = stripVersion(current);
      return cur != null && compareVersions(l.version, cur) > 0 ? l : null;
    }
    if (compareVersions(l.version, current) == 0) return null;
    final cur = buildOf(kind, current);
    if (cur != null) return l.build > cur ? l : null;
    // the installed version isn't listed (an old release that was removed, or a hand-flashed build)
    if (isPreLaunch(current) && !isPreLaunch(l.version)) return l;
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

  /// Fallback parser using GitHub's Atom feed (`https://github.com/<repo>/releases.atom`)
  /// which is never subject to api.github.com's 60 req/hr unauthenticated rate limit.
  Future<bool> _checkAtomFallback() async {
    try {
      final res = await http
          .get(
            Uri.parse('https://github.com/$repo/releases.atom'),
            headers: const {'User-Agent': 'Fisha-App', 'Accept': 'application/atom+xml,text/xml,*/*'},
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return false;
      final entries = RegExp(r'<entry>([\s\S]*?)</entry>').allMatches(res.body);
      final out = <Release>[];
      for (final e in entries) {
        final block = e.group(1) ?? '';
        final tagMatch = RegExp(r'/releases/tag/([^"<>\s]+)').firstMatch(block);
        if (tagMatch == null) continue;
        final tag = Uri.decodeComponent(tagMatch.group(1)!);
        final updatedMatch = RegExp(r'<updated>([^<]+)</updated>').firstMatch(block);
        final pub = DateTime.tryParse(updatedMatch?.group(1) ?? '')?.toLocal() ?? DateTime.now();

        final m = _tag.firstMatch(tag);
        final sm = _stripTag.firstMatch(tag);
        if (m == null && sm == null) continue;
        final kind = m == null ? 'strip' : m.group(1)!;
        final version = m == null ? sm!.group(1)! : m.group(2)!;
        final build = m == null ? 0 : int.parse(m.group(3)!);
        final String assetUrl = switch (kind) {
          'strip' => 'https://github.com/$repo/releases/download/$tag/comMTTL-W01_F$version.fwr',
          'hub' => 'https://github.com/$repo/releases/download/$tag/fisha-hub-$version.bin',
          _ => 'https://github.com/$repo/releases/download/$tag/fisha-$version.apk',
        };
        // Preserve existing URL/notes from cache if we already have this release
        final existing = releases.where((r) => r.kind == kind && r.version == version && r.build == build).toList();
        if (existing.isNotEmpty) {
          out.add(existing.first);
        } else {
          out.add(Release(kind, version, build, '', pub, assetUrl, 327944));
        }
      }
      if (out.isNotEmpty) {
        out.sort((a, b) => b.published.compareTo(a.published));
        releases = out;
        checkedAt = DateTime.now();
        return true;
      }
    } catch (_) {}
    return false;
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
          .get(
            Uri.parse('https://api.github.com/repos/$repo/releases?per_page=40'),
            headers: const {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'Fisha-App',
              'X-GitHub-Api-Version': '2022-11-28',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        _parse(res.body);
        checkedAt = DateTime.now();
        error = null;
        final p = await SharedPreferences.getInstance();
        await p.setString('upd_cache', res.body);
        await p.setInt('upd_at', checkedAt!.millisecondsSinceEpoch);
      } else {
        final okAtom = await _checkAtomFallback();
        if (!okAtom && releases.isEmpty) {
          error = res.statusCode == 403 || res.statusCode == 429 ? 'rate' : 'net';
        }
      }
    } catch (_) {
      final okAtom = await _checkAtomFallback();
      if (!okAtom && releases.isEmpty) {
        error = 'net';
      }
    }
    loading = false;
    notifyListeners();
  }

  void _parse(String body) {
    try {
      final out = <Release>[];
      for (final j in (jsonDecode(body) as List)) {
        if (j['draft'] == true) continue;
        final tag = (j['tag_name'] ?? '').toString();
        final m = _tag.firstMatch(tag);
        final sm = _stripTag.firstMatch(tag);
        if (m == null && sm == null) continue;
        final kind = m == null ? 'strip' : m.group(1)!;
        final version = m == null ? sm!.group(1)! : m.group(2)!;
        final build = m == null ? 0 : int.parse(m.group(3)!);
        final extension = switch (kind) { 'app' => '.apk', 'hub' => '.bin', _ => '.fwr' };
        final assets = (j['assets'] as List? ?? []).cast<Map>();
        final a = assets.cast<Map?>().firstWhere(
            (x) =>
                (x!['name'] ?? '').toString().toLowerCase().endsWith(extension) &&
                ((x['size'] as num?)?.toInt() ?? 0) > 0 &&
                (kind != 'strip' ||
                    (x['name'] ?? '').toString() == 'comMTTL-W01_F$version.fwr' ||
                    (x['name'] ?? '').toString().toUpperCase().contains('F$version')),
            orElse: () => null);
        if (a == null) continue;
        out.add(Release(kind, version, build, (j['body'] ?? '').toString(),
            DateTime.tryParse((j['published_at'] ?? '').toString())?.toLocal() ?? DateTime.now(), a['browser_download_url'].toString(), (a['size'] as num?)?.toInt() ?? 0));
      }
      out.sort((a, b) => b.published.compareTo(a.published));
      releases = out;
    } catch (_) {}
  }
}
