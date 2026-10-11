import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// Streams the APK to the app cache with [progress] 0..1, then opens Android's installer.
/// Returns null when the installer opened, else an error code: net, install.
Future<String?> downloadAndInstallApk(String url, int size, void Function(double) progress) async {
  final client = http.Client();
  try {
    final res = await client.send(http.Request('GET', Uri.parse(url)));
    if (res.statusCode != 200) return 'net';
    final total = res.contentLength ?? size;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/fisha-update.apk');
    final sink = file.openWrite();
    var got = 0;
    await for (final chunk in res.stream) {
      sink.add(chunk);
      got += chunk.length;
      if (total > 0) progress((got / total).clamp(0.0, 1.0));
    }
    await sink.close();
    if (total > 0 && got < total) return 'net';
    final r = await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
    return r.type == ResultType.done ? null : 'install';
  } catch (_) {
    return 'net';
  } finally {
    client.close();
  }
}
