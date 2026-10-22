import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show compute;

/// Encrypted backup file: the backup JSON sealed with AES-256-GCM. The key comes from the owner's password through
/// PBKDF2-HMAC-SHA256 with a random salt, so the same password gives a different file every time. The envelope also
/// carries the SHA-256 of the ciphertext, which tells a damaged or edited file apart from a wrong password.
class BackupCrypto {
  static const marker = 'fisha_backup_enc';
  static const iterations = 100000;

  static bool isEncrypted(Object? j) => j is Map && j[marker] == 1;

  /// the sealed file contents (JSON text as bytes)
  static Future<List<int>> encrypt(Map<String, dynamic> backup, String password) async {
    final env = await compute(_seal, _SealJob(jsonEncode(backup), password));
    return utf8.encode(jsonEncode(env));
  }

  /// the backup, or null when the password is wrong or the file was changed; throws [FormatException] when the
  /// envelope is not one of ours or its hash does not match the ciphertext (damaged file)
  static Future<Map<String, dynamic>?> decrypt(Map<String, dynamic> env, String password) async {
    final ct = _b64(env['ct']);
    final nonce = _b64(env['nonce']);
    final mac = _b64(env['mac']);
    final salt = _b64(env['salt']);
    final iter = env['iter'];
    if (ct == null || nonce == null || mac == null || salt == null || iter is! int || iter < 1000 || iter > 5000000) {
      throw const FormatException('not a Fisha encrypted backup');
    }
    final want = (env['sha256'] ?? '').toString();
    final got = _hex((await Sha256().hash(ct)).bytes);
    if (want.isNotEmpty && want != got) throw const FormatException('the file was changed or damaged');
    final text = await compute(_open, _OpenJob(ct, nonce, mac, salt, iter, password));
    if (text == null) return null;
    final j = jsonDecode(text);
    return j is Map<String, dynamic> ? j : null;
  }

  static List<int>? _b64(Object? v) {
    if (v is! String) return null;
    try {
      return base64Decode(v);
    } catch (_) {
      return null;
    }
  }

  static String _hex(List<int> b) => [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
}

class _SealJob {
  final String json, password;
  const _SealJob(this.json, this.password);
}

class _OpenJob {
  final List<int> ct, nonce, mac, salt;
  final int iter;
  final String password;
  const _OpenJob(this.ct, this.nonce, this.mac, this.salt, this.iter, this.password);
}

Future<SecretKey> _key(String password, List<int> salt, int iter) =>
    Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iter, bits: 256).deriveKeyFromPassword(password: password, nonce: salt);

// run in an isolate (compute): 100,000 rounds of HMAC would freeze the screen for a moment on a phone
Future<Map<String, dynamic>> _seal(_SealJob job) async {
  final salt = SecretKeyData.random(length: 16).bytes;
  final key = await _key(job.password, salt, BackupCrypto.iterations);
  final box = await AesGcm.with256bits().encrypt(utf8.encode(job.json), secretKey: key);
  return {
    BackupCrypto.marker: 1,
    'kdf': 'pbkdf2-sha256',
    'iter': BackupCrypto.iterations,
    'cipher': 'aes-256-gcm',
    'salt': base64Encode(salt),
    'nonce': base64Encode(box.nonce),
    'ct': base64Encode(box.cipherText),
    'mac': base64Encode(box.mac.bytes),
    'sha256': [for (final x in (await Sha256().hash(box.cipherText)).bytes) x.toRadixString(16).padLeft(2, '0')].join(),
  };
}

Future<String?> _open(_OpenJob job) async {
  try {
    final key = await _key(job.password, job.salt, job.iter);
    final clear = await AesGcm.with256bits().decrypt(SecretBox(job.ct, nonce: job.nonce, mac: Mac(job.mac)), secretKey: key);
    return utf8.decode(clear);
  } catch (_) {
    return null; // a wrong password fails the GCM check
  }
}
