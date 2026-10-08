import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../services/file_io.dart';
import '../theme.dart';
import '../widgets/common.dart';

class BackupScreen extends StatefulWidget {
  final AppState state;
  const BackupScreen({super.key, required this.state});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  AppState get s => widget.state;
  bool _app = true;
  bool _hub = true;
  bool _busy = false;

  Set<String> get _selectedParts => {
        if (_app) 'app',
        if (_hub) 'hub',
      };

  String _backupFileName() {
    final now = DateTime.now();
    String p2(int n) => n.toString().padLeft(2, '0');
    final y = now.year.toString().padLeft(4, '0');
    final m = p2(now.month);
    final d = p2(now.day);
    final h = p2(now.hour);
    final min = p2(now.minute);
    return 'fisha-backup-$y$m$d-$h$min.json';
  }

  Future<void> _export() async {
    final parts = _selectedParts;
    if (parts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('backup_select_part'))));
      return;
    }
    setState(() => _busy = true);
    try {
      final data = await s.exportBackup(parts: parts);
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
      final bytes = Uint8List.fromList(utf8.encode(jsonStr));
      final res = await FilePicker.platform.saveFile(
        fileName: _backupFileName(),
        bytes: bytes,
      );
      // on the web the browser downloads the file itself and saveFile returns null
      if (res != null || kIsWeb) {
        if (res != null && !kIsWeb) {
          try {
            await writeFileIfEmpty(res, bytes);
          } catch (_) {}
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('backup_saved'))));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('err_failed'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final parts = _selectedParts;
    if (parts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('backup_select_part'))));
      return;
    }
    final r = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    final f = r?.files.single;
    if (f == null) return;

    Uint8List? bytes = f.bytes;
    if (bytes == null && !kIsWeb && f.path != null) {
      try {
        bytes = await readFileBytes(f.path!);
      } catch (_) {}
    }
    if (bytes == null || bytes.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('backup_err_invalid'))));
      return;
    }

    Map<String, dynamic> j;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      j = decoded;
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('backup_err_invalid'))));
      return;
    }

    if (j['fisha_backup'] != 1) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('backup_err_invalid'))));
      return;
    }

    if (!mounted) return;
    bool replace = false;
    if (parts.contains('hub') && j.containsKey('hub')) {
      final choice = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: C.surface,
          title: Text(t('backup_restore_title'), style: const TextStyle(fontSize: 18)),
          content: Text(t('backup_restore_sched_q'), style: TextStyle(color: C.textSoft, height: 1.5)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: Text(t('cancel'), style: TextStyle(color: C.muted))),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('backup_add'), style: TextStyle(color: C.accent))),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t('backup_replace'), style: TextStyle(color: C.danger, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      replace = choice;
    } else {
      if (!await confirmDialog(context, t('backup_restore_title'), t('backup_restore_confirm'))) return;
    }

    setState(() => _busy = true);
    try {
      final res = await s.importBackup(j, parts: parts, replace: replace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res ?? t('backup_restored'))));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('err_failed'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: C.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(t('backup_title'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          children: [
            section(t('backup_section_parts'), [
              CheckboxListTile(
                value: _app,
                onChanged: _busy ? null : (v) => setState(() => _app = v ?? false),
                activeColor: C.accent,
                checkColor: C.onAccent,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  t('backup_part_app'),
                  style: TextStyle(color: C.text, fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
              CheckboxListTile(
                value: _hub,
                onChanged: _busy ? null : (v) => setState(() => _hub = v ?? false),
                activeColor: C.accent,
                checkColor: C.onAccent,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  t('backup_part_hub'),
                  style: TextStyle(color: C.text, fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            section(t('backup_title'), [
              primaryButton(
                t('backup_btn_export'),
                _busy || _selectedParts.isEmpty ? null : _export,
                icon: Icons.download_outlined,
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy || _selectedParts.isEmpty ? null : _import,
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(t('backup_btn_import')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: C.accent,
                  side: BorderSide(color: C.tileOnBorder),
                  minimumSize: const Size(0, 52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            emptyCard(
              t('backup_note'),
              icon: Icons.lock_outline,
            ),
          ],
        ),
      ),
    );
  }
}
