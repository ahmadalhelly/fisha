import 'package:local_auth/local_auth.dart';

Future<bool> authenticateBio(String reason) async {
  try {
    final auth = LocalAuthentication();
    return await auth.authenticate(
      localizedReason: reason,
      options: const AuthenticationOptions(stickyAuth: true, biometricOnly: false),
    );
  } catch (_) {
    return false;
  }
}
