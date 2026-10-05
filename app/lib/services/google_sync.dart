import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

/// Optional Google account: sign-in plus one private sync file in the app's hidden Google Drive folder (appDataFolder).
/// Nothing goes through an extra server; only this app can read the file.
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

  /// Interactive sign-in. Returns the e-mail, or null if the user cancelled.
  Future<String?> signIn() async {
    try {
      _acc = await _g.signIn();
      return _acc?.email;
    } catch (_) {
      return null;
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
    if (a == null) throw StateError('not signed in');
    _acc = a;
    return await a.authHeaders;
  }

  Future<String?> _fileId(Map<String, String> h) async {
    try {
      final q = Uri.encodeQueryComponent("name='$_fileName' and trashed=false");
      final r = await http.get(
        Uri.parse('https://www.googleapis.com/drive/v3/files?spaces=appDataFolder&q=$q&fields=files(id,name,trashed)'),
        headers: h,
      );
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body);
        if (j is Map && j['files'] is List && (j['files'] as List).isNotEmpty) {
          for (final f in j['files'] as List) {
            if (f is Map && f['trashed'] != true) return f['id']?.toString();
          }
        }
      }
      // Fallback: list without query
      final r2 = await http.get(
        Uri.parse('https://www.googleapis.com/drive/v3/files?spaces=appDataFolder&fields=files(id,name,trashed)'),
        headers: h,
      );
      if (r2.statusCode == 200) {
        final j2 = jsonDecode(r2.body);
        if (j2 is Map && j2['files'] is List) {
          for (final f in j2['files'] as List) {
            if (f is Map && f['name'] == _fileName && f['trashed'] != true) {
              return f['id']?.toString();
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Uploads (creates or replaces) the sync file.
  Future<void> upload(Map<String, dynamic> data) async {
    final h = await _headers();
    var id = await _fileId(h);
    final body = utf8.encode(jsonEncode(data));

    if (id == null) {
      // Step 1: Create file in appDataFolder
      final createRes = await http.post(
        Uri.parse('https://www.googleapis.com/drive/v3/files'),
        headers: {...h, 'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({'name': _fileName, 'parents': ['appDataFolder']}),
      );
      if (createRes.statusCode != 200 && createRes.statusCode != 201) {
        throw StateError('drive create ${createRes.statusCode}: ${createRes.body}');
      }
      final created = jsonDecode(createRes.body);
      if (created is Map && created['id'] != null) {
        id = created['id'].toString();
      } else {
        throw StateError('drive: missing file id');
      }
    }

    // Step 2: Patch content to media upload endpoint
    final r = await http.patch(
      Uri.parse('https://www.googleapis.com/upload/drive/v3/files/$id?uploadType=media'),
      headers: {...h, 'Content-Type': 'application/json'},
      body: body,
    );
    if (r.statusCode != 200) throw StateError('drive patch ${r.statusCode}: ${r.body}');
  }

  /// The last synced data, or null when this Google account has none yet.
  Future<Map<String, dynamic>?> download() async {
    final h = await _headers();
    final id = await _fileId(h);
    if (id == null) return null;
    final r = await http.get(Uri.parse('https://www.googleapis.com/drive/v3/files/$id?alt=media'), headers: h);
    if (r.statusCode != 200) throw StateError('drive ${r.statusCode}');
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    return j is Map<String, dynamic> ? j : null;
  }
}
