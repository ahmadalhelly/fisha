import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ota_dialogs.dart';

/// Updates the hub firmware from the phone: pick the .bin, upload it to the hub's /update page.
class FirmwareScreen extends StatefulWidget {
  final AppState state;
  const FirmwareScreen({super.key, required this.state});

  @override
  State<FirmwareScreen> createState() => _FirmwareScreenState();
}

class _FirmwareScreenState extends State<FirmwareScreen> {
  AppState get s => widget.state;
  late final TextEditingController _pass = TextEditingController(text: s.otaPass);
  String? _fileName;
  List<int>? _bytes;
  double? _progress;
  String? _error;
  bool _done = false;
  bool _obscure = true;

  @override
  void dispose() {
    _pass.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    final f = r?.files.single;
    if (f == null || f.bytes == null) return;
    setState(() {
      _fileName = f.name;
      _bytes = f.bytes;
      _error = (f.bytes!.isEmpty || f.bytes!.first != 0xE9 || !f.name.toLowerCase().endsWith('.bin')) ? t('fw_bad_file') : null;
      _done = false;
    });
  }

  Future<void> _upload() async {
    final bytes = _bytes;
    if (bytes == null) return;
    if (!await confirmDialog(context, t('fw_confirm_t'), t('fw_confirm_b'), ok: t('fw_upload'))) return;
    if (_pass.text.isNotEmpty) await s.setOtaPass(_pass.text);
    setState(() {
      _progress = 0;
      _error = null;
      _done = false;
    });
    final err = await s.uploadFirmwareAuto(bytes, (p) {
      if (mounted) setState(() => _progress = p);
    }, ask: () => askUpdatePassword(context, s));
    if (!mounted) return;
    setState(() {
      _progress = null;
      _done = err == null;
      _error = switch (err) {
        null => null,
        'auth' || 'cancel' => t('fw_err_auth'),
        'net' => t('fw_err_net'),
        'bad_file' => t('fw_bad_file'),
        _ => err,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final busy = _progress != null;
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: C.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(t('fw_title'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 24), children: [
          section(t('fw_current'), [
            Row(children: [
              Icon(Icons.memory, color: C.accent),
              const SizedBox(width: 10),
              Expanded(child: Text(t('hub_fw'))),
              Text(s.hubFw ?? '—', textDirection: TextDirection.ltr, style: mono(16, color: C.accent)),
            ]),
          ]),
          const SizedBox(height: 14),
          if (s.mode != ConnMode.local) ...[emptyCard(t('fw_local_only'), icon: Icons.wifi), const SizedBox(height: 14)],
          section(t('fw_new'), [
            Text(t('fw_how'), style: TextStyle(color: C.muted, fontSize: 12, height: 1.6)),
            OutlinedButton.icon(
              onPressed: busy ? null : _pick,
              icon: const Icon(Icons.folder_open),
              label: Text(_fileName ?? t('fw_pick')),
              style: OutlinedButton.styleFrom(foregroundColor: C.accent, side: BorderSide(color: C.tileOnBorder), minimumSize: const Size(0, 48)),
            ),
            if (_bytes != null) Text('${(_bytes!.length / 1024).toStringAsFixed(0)} KB', textDirection: TextDirection.ltr, style: mono(12, color: C.muted)),
            if (!s.isShared)
            TextField(
              controller: _pass,
              obscureText: _obscure,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: t('fw_pass'),
                helperText: t('fw_pass_hint'),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: C.muted),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            if (s.isOwner)
              OutlinedButton.icon(
                onPressed: busy ? null : () => changeUpdatePasswordDialog(context, s),
                icon: const Icon(Icons.key_outlined),
                label: Text(Tr.isAr ? 'تغيير / إعادة تعيين الباسورد' : 'Change / reset the password'),
                style: OutlinedButton.styleFrom(foregroundColor: C.accent, side: BorderSide(color: C.tileOnBorder), minimumSize: const Size(0, 44)),
              ),
          ]),
          const SizedBox(height: 16),
          if (busy) ...[
            LinearProgressIndicator(value: _progress, minHeight: 8, color: C.accent, backgroundColor: C.surface2, borderRadius: BorderRadius.circular(4)),
            const SizedBox(height: 8),
            Center(child: Text('${((_progress ?? 0) * 100).toStringAsFixed(0)}%  ·  ${t('fw_dont_close')}', style: TextStyle(color: C.muted))),
          ] else
            primaryButton(t('fw_upload'), _bytes == null || _error == t('fw_bad_file') || s.mode != ConnMode.local ? null : _upload,
                icon: Icons.system_update_alt),
          if (_error != null) ...[const SizedBox(height: 12), emptyCard(_error!, icon: Icons.error_outline)],
          if (_done) ...[const SizedBox(height: 12), emptyCard(t('fw_done'), icon: Icons.check_circle_outline)],
        ]),
      ),
    );
  }
}
