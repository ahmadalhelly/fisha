import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

/// Optional Google account: sign-in plus one private sync file in the app's hidden Google Drive folder (appDataFolder).
/// Nothing goes through an extra server; only this app can read the file.
/// A Google sign-in / Drive failure with a short reason the app can translate:
/// not_configured (OAuth client / SHA-1), network, drive_disabled, auth, drive.
class GoogleSyncError implements Exception {
  final String code;
  final String detail;
  const GoogleSyncError(this.code, [this.detail = '']);
  @override
  String toString() => detail.isEmpty ? code : '$code: $detail';
}

/// One saved copy on Drive: its file id, when it was written, and its size.
class SyncVersion {
  final String id;
  final DateTime modified;
  final int bytes;
  const SyncVersion(this.id, this.modified, this.bytes);
}

class GoogleSync {
  GoogleSync._();
  static final GoogleSync I = GoogleSync._();

  static const _scope = 'https://www.googleapis.com/auth/drive.appdata';
  // 2.0.20: every sync writes its own timestamped file, so old copies stay choosable at restore time
  // instead of being overwritten. The single 'fisha-sync.json' from older builds is still read as a fallback.
  static const _legacyName = 'fisha-sync.json';
  static const _prefix = 'fisha-sync-';
  static String _versionName(DateTime t) => '$_prefix${t.toUtc().millisecondsSinceEpoch}.json';

  final GoogleSignIn _g = GoogleSignIn(scopes: const ['email', _scope]);
  GoogleSignInAccount? _acc;

  String? get email => _acc?.email;
  String? get displayName => _acc?.displayName;
  bool get signedIn => _acc != null;

  /// Interactive sign-in. Returns the e-mail, or null if the user cancelled; throws [GoogleSyncError] on a real failure.
  Future<String?> signIn() async {
    try {
      _acc = await _g.signIn();
      return _acc?.email;
    } on PlatformException catch (e) {
      final m = '${e.code} ${e.message}';
      if (e.code == GoogleSignIn.kSignInCanceledError || m.contains('12501')) return null;
      if (m.contains('ApiException: 10') || m.contains('DEVELOPER_ERROR')) throw GoogleSyncError('not_configured', m);
      if (e.code == GoogleSignIn.kNetworkError || m.contains('ApiException: 7')) throw GoogleSyncError('network', m);
      throw GoogleSyncError('auth', m);
    }
  }

  /// Quiet sign-in at start-up (no UI).
  Future<bool> restore() async {
    try {
      _acc = await _g.signInSilently();
    } catch (_) {
      _acc = null;
    }
    return _acc != null;
  }

  Future<void> signOut() async {
    try {
      await _g.disconnect();
    } catch (_) {
      try {
        await _g.signOut();
      } catch (_) {}
    }
    _acc = null;
  }

  Future<Map<String, String>> _headers() async {
    var a = _acc;
    if (a == null) {
      try {
        a = await _g.signInSilently();
      } catch (_) {}
    }
    if (a == null) throw const GoogleSyncError('auth', 'not signed in');
    _acc = a;
    return await a.authHeaders;
  }

  /// Runs a Drive request; on 401 the cached token is dropped and the request is sent once more with a fresh one.
  Future<http.Response> _send(Future<http.Response> Function(Map<String, String> h) call) async {
    http.Response r;
    try {
      r = await call(await _headers()).timeout(const Duration(seconds: 25));
      if (r.statusCode == 401) {
        await _acc?.clearAuthCache();
        r = await call(await _headers()).timeout(const Duration(seconds: 25));
      }
    } on GoogleSyncError {
      rethrow;
    } catch (e) {
      throw GoogleSyncError('network', e.toString());
    }
    if (r.statusCode == 403 && (r.body.contains('accessNotConfigured') || r.body.contains('SERVICE_DISABLED'))) {
      throw GoogleSyncError('drive_disabled', r.body);
    }
    if (r.statusCode == 401 || r.statusCode == 403) throw GoogleSyncError('auth', 'HTTP ${r.statusCode}');
    return r;
  }

  /// Every saved copy (versioned ones, plus the legacy single file if it is still there), newest first.
  /// Throws on any Drive error, so a failed lookup is never mistaken for "no copies".
  Future<List<SyncVersion>> listVersions() async {
    final q = Uri.encodeQueryComponent("(name contains '$_prefix' or name='$_legacyName') and trashed=false");
    final r = await _send((h) => http.get(
          Uri.parse('https://www.googleapis.com/drive/v3/files?spaces=appDataFolder&q=$q'
              '&orderBy=modifiedTime%20desc&fields=files(id,name,modifiedTime,size)&pageSize=50'),
          headers: h,
        ));
    if (r.statusCode != 200) throw GoogleSyncError('drive', 'list ${r.statusCode}');
    final j = jsonDecode(r.body);
    final files = j is Map ? j['files'] : null;
    if (files is! List) return const [];
    final out = <SyncVersion>[];
    for (final f in files) {
      if (f is! Map) continue;
      final id = f['id']?.toString();
      final mod = DateTime.tryParse((f['modifiedTime'] ?? '').toString());
      if (id == null || mod == null) continue;
      out.add(SyncVersion(id, mod.toLocal(), int.tryParse((f['size'] ?? '0').toString()) ?? 0));
    }
    out.sort((a, b) => b.modified.compareTo(a.modified));
    return out;
  }

  /// Id of the newest saved copy, or null when there is none.
  Future<String?> _latestId() async {
    final v = await listVersions();
    return v.isEmpty ? null : v.first.id;
  }

  /// Writes a new, separate copy, then deletes the oldest ones beyond [keep] (minimum 1).
  Future<void> upload(Map<String, dynamic> data, {int keep = 5}) async {
    final body = utf8.encode(jsonEncode(data));
    final createRes = await _send((h) => http.post(
          Uri.parse('https://www.googleapis.com/drive/v3/files?fields=id'),
          headers: {...h, 'Content-Type': 'application/json; charset=UTF-8'},
          body: jsonEncode({'name': _versionName(DateTime.now()), 'parents': ['appDataFolder']}),
        ));
    if (createRes.statusCode != 200 && createRes.statusCode != 201) {
      throw GoogleSyncError('drive', 'create ${createRes.statusCode}');
    }
    final created = jsonDecode(createRes.body);
    if (created is! Map || created['id'] == null) throw const GoogleSyncError('drive', 'missing file id');
    final id = created['id'].toString();

    final r = await _send((h) => http.patch(
          Uri.parse('https://www.googleapis.com/upload/drive/v3/files/$id?uploadType=media'),
          headers: {...h, 'Content-Type': 'application/json; charset=UTF-8'},
          body: body,
        ));
    if (r.statusCode != 200) throw GoogleSyncError('drive', 'upload ${r.statusCode}');

    try {
      final all = await listVersions();
      for (final old in all.skip(keep < 1 ? 1 : keep)) {
        await _send((h) => http.delete(Uri.parse('https://www.googleapis.com/drive/v3/files/${old.id}'), headers: h));
      }
    } catch (_) {
      // pruning is best-effort: a failure here must not fail the upload that just succeeded
    }
  }

  /// The data of [id], or of the newest saved copy when [id] is null; null when there is none yet.
  /// Throws [GoogleSyncError] on failure.
  Future<Map<String, dynamic>?> download([String? id]) async {
    final fileId = id ?? await _latestId();
    if (fileId == null) return null;
    final r = await _send((h) => http.get(Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId?alt=media'), headers: h));
    if (r.statusCode != 200) throw GoogleSyncError('drive', 'download ${r.statusCode}');
    try {
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      throw const GoogleSyncError('drive', 'bad sync file');
    }
  }
}
