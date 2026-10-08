/// Web build: no local_auth, so a biometric-protected outlet is not re-confirmed (treated as passed).
Future<bool> authenticateBio(String reason) async => true;
