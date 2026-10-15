import 'dart:convert';
import 'dart:io';

/// What went wrong the last time an upload failed with 'net' (shown next to the message so a failure can be diagnosed).
String lastUploadNetDetail = '';

/// Uploads a firmware .bin to the hub's /update page at [uri]; [progress] gets 0..1. Returns null on success or an error text.
Future<String?> uploadFirmwareBytes(Uri uri, List<int> bytes, String password, void Function(double) progress,
    {Map<String, String>? headers, String fileName = 'firmware.bin'}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
  try {
    final req = await client.postUrl(uri);
    if (headers != null) {
      headers.forEach(req.headers.set);
    } else {
      req.headers.set(HttpHeaders.authorizationHeader, 'Basic ${base64Encode(utf8.encode('admin:$password'))}');
    }
    final boundary = '----fisha${DateTime.now().millisecondsSinceEpoch}';
    req.headers.contentType = ContentType('multipart', 'form-data', parameters: {'boundary': boundary});
    final head = utf8.encode('--$boundary\r\nContent-Disposition: form-data; name="f"; filename="$fileName"\r\n'
        'Content-Type: application/octet-stream\r\n\r\n');
    final tail = utf8.encode('\r\n--$boundary--\r\n');
    req.contentLength = head.length + bytes.length + tail.length;
    req.add(head);
    const chunk = 8192;
    for (var i = 0; i < bytes.length; i += chunk) {
      req.add(bytes.sublist(i, i + chunk > bytes.length ? bytes.length : i + chunk));
      await req.flush();
      progress((i + chunk).clamp(0, bytes.length) / bytes.length);
    }
    req.add(tail);
    final resp = await req.close().timeout(const Duration(seconds: 60));
    final body = await resp.transform(utf8.decoder).join();
    if (resp.statusCode == 401) return 'auth';
    if (resp.statusCode != 200) return body.trim().isEmpty ? 'HTTP ${resp.statusCode}' : body.trim();
    return null;
  } catch (e) {
    lastUploadNetDetail = e.toString().split('\n').first;
    return 'net';
  } finally {
    client.close(force: true);
  }
}
