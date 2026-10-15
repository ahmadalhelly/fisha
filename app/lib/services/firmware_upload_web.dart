/// Web build: an https page cannot reach the hub's plain-http /update page (mixed content), so there is no upload.
String lastUploadNetDetail = '';
Future<String?> uploadFirmwareBytes(Uri uri, List<int> bytes, String password, void Function(double) progress,
        {Map<String, String>? headers, String fileName = 'firmware.bin'}) async =>
    'net';
