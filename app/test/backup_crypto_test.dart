import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mttl_hub/services/backup_crypto.dart';

void main() {
  const timeout = Timeout(Duration(minutes: 3));
  final backup = <String, dynamic>{
    'fisha_backup': 1,
    'app': {
      'names': {'t': 's', 'v': 'مطبخ'},
    },
  };

  test('a sealed backup opens with the right password and is not readable without it', () async {
    final bytes = await BackupCrypto.encrypt(backup, 'secret-pass');
    final env = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    expect(BackupCrypto.isEncrypted(env), isTrue);
    expect(utf8.decode(bytes).contains('names'), isFalse);
    expect(utf8.decode(bytes).contains('مطبخ'), isFalse);
    final back = await BackupCrypto.decrypt(env, 'secret-pass');
    expect(back, backup);
  }, timeout: timeout);

  test('a wrong password gives null, not an error', () async {
    final env = jsonDecode(utf8.decode(await BackupCrypto.encrypt(backup, 'secret-pass'))) as Map<String, dynamic>;
    expect(await BackupCrypto.decrypt(env, 'other-pass'), isNull);
  }, timeout: timeout);

  test('the same password gives a different file each time', () async {
    final a = utf8.decode(await BackupCrypto.encrypt(backup, 'secret-pass'));
    final b = utf8.decode(await BackupCrypto.encrypt(backup, 'secret-pass'));
    expect(a == b, isFalse);
  }, timeout: timeout);

  test('a changed ciphertext is reported as a damaged file', () async {
    final env = jsonDecode(utf8.decode(await BackupCrypto.encrypt(backup, 'secret-pass'))) as Map<String, dynamic>;
    final ct = base64Decode(env['ct'] as String);
    ct[0] = ct[0] ^ 0xFF;
    env['ct'] = base64Encode(ct);
    expect(() => BackupCrypto.decrypt(env, 'secret-pass'), throwsFormatException);
  }, timeout: timeout);

  test('a plain backup and a broken envelope are told apart', () async {
    expect(BackupCrypto.isEncrypted(backup), isFalse);
    expect(() => BackupCrypto.decrypt({BackupCrypto.marker: 1}, 'x'), throwsFormatException);
  });
}
