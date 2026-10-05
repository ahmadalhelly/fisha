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
    _acc = await _g.signIn();
    return _acc?.email;
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
      await _g.signOut();
    }
    _acc = null;
  }

  Future<Map<String, String>> _headers() async {
    final a = _acc ?? await _g.signInSilently();
    if (a == null) throw StateError('not signed in');
    _acc = a;
    return a.authHeaders;
  }

  Future<String?> _fileId(Map<String, String> h) async {
    final q = Uri.encodeQueryComponent("name='$_fileName'");
    final r = await http.get(Uri.parse('https://www.googleapis.com/drive/v3/files?spaces=appDataFolder&q=$q&fields=files(id,modifiedTime)'), headers: h);
    if (r.statusCode != 200) throw StateError('drive ${r.statusCode}');
    final files = (jsonDecode(r.body) as Map<String, dynamic>)['files'];
    if (files is List && files.isNotEmpty) return (files.first as Map)['id']?.toString();
    return null;
  }

  /// Uploads (creates or replaces) the sync file.
  Future<void> upload(Map<String, dynamic> data) async {
    final h = await _headers();
    final id = await _fileId(h);
    final body = utf8.encode(jsonEncode(data));
    if (id != null) {
      final r = await http.patch(Uri.parse('https://www.googleapis.com/upload/drive/v3/files/$id?uploadType=media'),
          headers: {...h, 'Content-Type': 'application/json'}, body: body);
      if (r.statusCode != 200) throw StateError('drive ${r.statusCode}');
      return;
    }
    const boundary = 'fisha_sync_boundary';
    final meta = jsonEncode({'name': _fileName, 'parents': ['appDataFolder']});
    final multipart = <int>[
      ...utf8.encode('--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$meta\r\n'),
      ...utf8.encode('--$boundary\r\nContent-Type: application/json\r\n\r\n'),
      ...body,
      ...utf8.encode('\r\n--$boundary--\r\n'),
    ];
    final r = await http.post(Uri.parse('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart'),
        headers: {...h, 'Content-Type': 'multipart/related; boundary=$boundary'}, body: multipart);
    if (r.statusCode != 200) throw StateError('drive ${r.statusCode}');
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
