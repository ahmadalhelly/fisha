/// The web build cannot install APKs.
Future<String?> downloadAndInstallApk(String url, int size, void Function(double) progress) async => 'web';
