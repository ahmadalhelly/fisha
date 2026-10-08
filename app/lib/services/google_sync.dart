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

class GoogleSync {
  GoogleSync._();
  static final GoogleSync I = GoogleSync._();

  static const _scope = 'https://www.googleapis.com/auth/drive.appdata';
  static const _fileName = 'fisha-sync.json';

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

  /// Id of the newest sync file, or null when there is none. Throws on any Drive error, so a failed lookup is
  /// never mistaken for "no file" (that used to create duplicate files and restore an old one).
  Future<String?> _fileId() async {
    final q = Uri.encodeQueryComponent("name='$_fileName' and trashed=false");
    final r = await _send((h) => http.get(
          Uri.parse('https://www.googleapis.com/drive/v3/files?spaces=appDataFolder&q=$q'
              '&orderBy=modifiedTime%20desc&fields=files(id,modifiedTime)'),
          headers: h,
        ));
    if (r.statusCode != 200) throw GoogleSyncError('drive', 'list ${r.statusCode}');
    final j = jsonDecode(r.body);
    final files = j is Map ? j['files'] : null;
    if (files is List && files.isNotEmpty && files.first is Map) return (files.first as Map)['id']?.toString();
    return null;
  }

  /// Uploads (creates or replaces) the sync file.
  Future<void> upload(Map<String, dynamic> data) async {
    var id = await _fileId();
    final body = utf8.encode(jsonEncode(data));

    if (id == null) {
      final createRes = await _send((h) => http.post(
            Uri.parse('https://www.googleapis.com/drive/v3/files?fields=id'),
            headers: {...h, 'Content-Type': 'application/json; charset=UTF-8'},
            body: jsonEncode({'name': _fileName, 'parents': ['appDataFolder']}),
          ));
      if (createRes.statusCode != 200 && createRes.statusCode != 201) {
        throw GoogleSyncError('drive', 'create ${createRes.statusCode}');
      }
      final created = jsonDecode(createRes.body);
      if (created is! Map || created['id'] == null) throw const GoogleSyncError('drive', 'missing file id');
      id = created['id'].toString();
    }

    final r = await _send((h) => http.patch(
          Uri.parse('https://www.googleapis.com/upload/drive/v3/files/$id?uploadType=media'),
          headers: {...h, 'Content-Type': 'application/json; charset=UTF-8'},
          body: body,
        ));
    if (r.statusCode != 200) throw GoogleSyncError('drive', 'upload ${r.statusCode}');
  }

  /// The last synced data, or null when this Google account has none yet. Throws [GoogleSyncError] on failure.
  Future<Map<String, dynamic>?> download() async {
    final id = await _fileId();
    if (id == null) return null;
    final r = await _send((h) => http.get(Uri.parse('https://www.googleapis.com/drive/v3/files/$id?alt=media'), headers: h));
    if (r.statusCode != 200) throw GoogleSyncError('drive', 'download ${r.statusCode}');
    try {
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      throw const GoogleSyncError('drive', 'bad sync file');
    }
  }
}
