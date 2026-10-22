import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The backup password, kept in the phone's secure storage (Android Keystore) so the owner does not type it each time.
/// The screen asks for the fingerprint before it reads it when the owner turned that on.
class BackupSecret {
  static const _key = 'backup_password';
  static const _store = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

  static Future<String?> read() async {
    try {
      final v = await _store.read(key: _key);
      return v == null || v.isEmpty ? null : v;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> exists() async => (await read()) != null;

  static Future<void> write(String password) => _store.write(key: _key, value: password);

  static Future<void> clear() async {
    try {
      await _store.delete(key: _key);
    } catch (_) {}
  }
}
