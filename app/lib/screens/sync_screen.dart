import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../services/backup_crypto.dart';
import '../services/backup_secret.dart';
import '../services/file_io.dart';
import '../services/google_sync.dart';
import '../services/sync_parts.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// one page for both kinds of backup — manual export/import, and Google Drive sync (on/off, schedule,
/// and a choice of past copies to restore from). Replaces the old split between BackupScreen and the Google
/// section of AccountScreen.
class SyncScreen extends StatefulWidget {
  final AppState state;
  const SyncScreen({super.key, required this.state});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  AppState get s => widget.state;
  bool _app = true;
  bool _hub = true;
  bool _busy = false;
  // backup file encryption (this phone only): on/off, fingerprint before the saved password is used, password saved
  bool _encOn = false, _bioOn = false, _hasPw = false;

  List<SyncVersion>? _versions; // null = not loaded yet
  bool _versionsLoading = false;
  String? _versionsErr;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && s.accountType == 'google') _loadVersions();
    _loadEnc();
  }

  Set<String> get _selectedParts => {
        if (_app) 'app',
        if (_hub) 'hub',
      };

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _run(Future<void> Function() f) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await f();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- manual ----------

  Future<void> _loadEnc() async {
    final p = await SharedPreferences.getInstance();
    final has = await BackupSecret.exists();
    if (mounted) {
      setState(() {
        _encOn = p.getBool('backupEnc') ?? false;
        _bioOn = p.getBool('backupBio') ?? false;
        _hasPw = has;
      });
    }
  }

  Future<void> _setEnc(bool v) async {
    if (v && !_hasPw) {
      final pw = await _askPassword(Tr.isAr ? 'باسورد النسخة الاحتياطية' : 'Backup password', confirm: true);
      if (pw == null) return;
      try {
        await BackupSecret.write(pw);
      } catch (_) {
        _snack(Tr.isAr ? 'مقدرتش أحفظ الباسورد في تخزين الموبايل الآمن.' : 'Could not save the password in the secure storage.');
        return;
      }
      _hasPw = true;
    }
    final p = await SharedPreferences.getInstance();
    await p.setBool('backupEnc', v);
    if (mounted) setState(() => _encOn = v);
  }

  Future<void> _setBio(bool v) async {
    if (v && !await authenticateBio(Tr.isAr ? 'تأكيد البصمة' : 'Confirm your fingerprint')) return;
    final p = await SharedPreferences.getInstance();
    await p.setBool('backupBio', v);
    if (mounted) setState(() => _bioOn = v);
  }

  Future<void> _changePw() async {
    if (_bioOn && !await authenticateBio(Tr.isAr ? 'تأكيد البصمة لتغيير الباسورد' : 'Confirm your fingerprint to change the password')) return;
    final pw = await _askPassword(Tr.isAr ? 'باسورد جديد للنسخة' : 'New backup password', confirm: true);
    if (pw == null) return;
    try {
      await BackupSecret.write(pw);
    } catch (_) {
      _snack(Tr.isAr ? 'مقدرتش أحفظ الباسورد.' : 'Could not save the password.');
      return;
    }
    if (mounted) setState(() => _hasPw = true);
    _snack(Tr.isAr ? 'الباسورد اتغيّر. الملفات القديمة لسه بتفتح بالباسورد اللي اتشفّرت بيه.' : 'Password changed. Older files still open with the password they were sealed with.');
  }

  /// the saved password (after the fingerprint when that is on), or null when there is none or the fingerprint failed
  Future<String?> _storedPassword() async {
    if (!await BackupSecret.exists()) return null;
    if (_bioOn && !await authenticateBio(Tr.isAr ? 'تأكيد البصمة لفتح باسورد النسخة' : 'Confirm your fingerprint to use the backup password')) return null;
    return BackupSecret.read();
  }

  /// asks for a password (twice when [confirm]); at least 6 characters; null when cancelled
  Future<String?> _askPassword(String title, {bool confirm = false}) async {
    final a = TextEditingController(), b = TextEditingController();
    String? err;
    var show = false;
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: C.surface,
          title: Text(title, style: const TextStyle(fontSize: 18)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: a,
              obscureText: !show,
              autofocus: true,
              decoration: InputDecoration(
                labelText: Tr.isAr ? 'الباسورد' : 'Password',
                suffixIcon: IconButton(
                  tooltip: show ? (Tr.isAr ? 'إخفاء' : 'Hide') : (Tr.isAr ? 'إظهار' : 'Show'),
                  icon: Icon(show ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: C.muted, size: 20),
                  onPressed: () => setD(() => show = !show),
                ),
              ),
            ),
            if (confirm)
              TextField(
                controller: b,
                obscureText: !show,
                decoration: InputDecoration(labelText: Tr.isAr ? 'أكّد الباسورد' : 'Confirm the password'),
              ),
            if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: TextStyle(color: C.danger, fontSize: 12.5))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'), style: TextStyle(color: C.muted))),
            TextButton(
              onPressed: () {
                if (a.text.length < 6) {
                  setD(() => err = Tr.isAr ? 'الباسورد 6 حروف على الأقل.' : 'At least 6 characters.');
                } else if (confirm && a.text != b.text) {
                  setD(() => err = Tr.isAr ? 'الباسوردين مش زي بعض.' : 'The two passwords differ.');
                } else {
                  Navigator.pop(ctx, a.text);
                }
              },
              child: Text(Tr.isAr ? 'تمام' : 'OK', style: TextStyle(color: C.accent, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
    a.dispose();
    b.dispose();
    return r;
  }

  String _backupFileName() {
    final now = DateTime.now();
    String p2(int n) => n.toString().padLeft(2, '0');
    return 'fisha-backup-${now.year}${p2(now.month)}${p2(now.day)}-${p2(now.hour)}${p2(now.minute)}.json';
  }

  Future<void> _export() async {
    final parts = _selectedParts;
    if (parts.isEmpty) {
      _snack(t('backup_select_part'));
      return;
    }
    await _run(() async {
      try {
        final data = await s.exportBackup(parts: parts);
        var name = _backupFileName();
        Uint8List bytes;
        if (_encOn) {
          var pw = await _storedPassword();
          if (pw == null && !_hasPw) {
            pw = await _askPassword(Tr.isAr ? 'باسورد النسخة الاحتياطية' : 'Backup password', confirm: true);
            if (pw != null) {
              await BackupSecret.write(pw);
              _hasPw = true;
            }
          }
          if (pw == null) return;
          bytes = Uint8List.fromList(await BackupCrypto.encrypt(data, pw));
          name = name.replaceFirst('.json', '.enc.json');
        } else {
          bytes = Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(data)));
        }
        final res = await FilePicker.platform.saveFile(fileName: name, bytes: bytes);
        if (res != null || kIsWeb) {
          if (res != null && !kIsWeb) {
            try {
              await writeFileIfEmpty(res, bytes);
            } catch (_) {}
          }
          _snack(t('backup_saved'));
        }
      } catch (_) {
        _snack(t('err_failed'));
      }
    });
  }

  Future<void> _import() async {
    final parts = _selectedParts;
    if (parts.isEmpty) {
      _snack(t('backup_select_part'));
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
      _snack(t('backup_err_invalid'));
      return;
    }

    Map<String, dynamic> j;
    try {
      Object? decoded = jsonDecode(utf8.decode(bytes));
      if (BackupCrypto.isEncrypted(decoded)) {
        // a sealed file: the saved password first (after the fingerprint), then the one typed here
        Map<String, dynamic>? plain;
        final env = Map<String, dynamic>.from(decoded as Map);
        final saved = await _storedPassword();
        if (saved != null) plain = await BackupCrypto.decrypt(env, saved);
        if (plain == null) {
          if (!mounted) return;
          final pw = await _askPassword(Tr.isAr ? 'باسورد الملف' : 'File password');
          if (pw == null) return;
          plain = await BackupCrypto.decrypt(env, pw);
        }
        if (plain == null) {
          _snack(Tr.isAr ? 'الباسورد غلط.' : 'Wrong password.');
          return;
        }
        decoded = plain;
      }
      if (decoded is! Map<String, dynamic> || decoded['fisha_backup'] != 1) throw const FormatException();
      j = decoded;
    } on FormatException catch (e) {
      _snack(e.message.contains('damaged') ? (Tr.isAr ? 'الملف اتعدّل أو اتلف.' : 'The file was changed or damaged.') : t('backup_err_invalid'));
      return;
    } catch (_) {
      _snack(t('backup_err_invalid'));
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

    await _run(() async {
      try {
        final res = await s.importBackup(j, parts: parts, replace: replace);
        _snack(res ?? t('backup_restored'));
      } catch (_) {
        _snack(t('err_failed'));
      }
    });
  }

  // ---------- Google ----------

  Future<void> _loadVersions() async {
    setState(() {
      _versionsLoading = true;
      _versionsErr = null;
    });
    try {
      final v = await s.listGoogleVersions();
      if (mounted) setState(() => _versions = v);
    } catch (e) {
      if (mounted) setState(() => _versionsErr = e is GoogleSyncError ? e.code : 'err');
    } finally {
      if (mounted) setState(() => _versionsLoading = false);
    }
  }

  Future<void> _signInGoogle() => _run(() async {
        final err = await s.googleSignIn();
        if (err != null) {
          _snack(err);
          return;
        }
        final has = await s.googleHasData();
        if (has == null) {
          _snack(t('g_check_failed'));
          return;
        }
        if (has && mounted) {
          final yes = await confirmDialog(context, t('g_found_t'), t('g_found_b'), ok: t('g_restore'));
          if (yes) {
            final r = await s.restoreFromGoogle();
            _snack(r ?? t('g_restored'));
            await _loadVersions();
            return;
          }
        }
        final r = await s.syncNow();
        _snack(r ?? t('g_synced'));
        await _loadVersions();
      });

  Future<void> _toggleGoogle(bool on) async {
    if (!on) {
      if (!await confirmDialog(context, t('sync_pause_off'), t('acc_logout_b'))) return;
      await _run(() async {
        await s.useLocalAccount();
        setState(() => _versions = null);
      });
      return;
    }
    await _signInGoogle();
  }

  Future<void> _restoreVersion(SyncVersion v) async {
    if (!await confirmDialog(context, t('g_restore'), t('sync_restore_confirm_b', {'x': _when(v.modified)}), ok: t('g_restore'))) return;
    await _run(() async {
      final r = await s.restoreFromGoogle(v.id);
      _snack(r ?? t('g_restored'));
    });
  }

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return t('sync_today');
    if (diff == 1) return t('sync_yesterday');
    return '${d.day}/${d.month}';
  }

  String _when(DateTime d) => '${_dayLabel(d)} · ${fmtTime12(d.hour, d.minute)}';

  String _syncLabel(int m) => switch (m) {
        60 => Tr.isAr ? 'كل ساعة' : 'Hourly',
        1440 => Tr.isAr ? 'يوميًا' : 'Daily',
        10080 => Tr.isAr ? 'أسبوعيًا' : 'Weekly',
        _ => Tr.isAr ? 'مع كل تغيير' : 'On every change',
      };

  // ---------- UI ----------

  Widget _googleCard() {
    final on = s.accountType == 'google' && !s.syncPaused;
    final signedIn = s.accountType == 'google';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: cardBox(radius: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: C.accent2.withValues(alpha: .14), borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.cloud_outlined, color: C.accent2, size: 20),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('sync_google_section'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              Text(signedIn ? (on ? t('sync_google_on') : t('sync_pause_off')) : t('sync_google_off'),
                  style: TextStyle(color: C.muted, fontSize: 12)),
            ]),
          ),
          Switch(
            value: signedIn,
            onChanged: _busy ? null : (v) => _toggleGoogle(v),
            activeTrackColor: C.accent,
          ),
        ]),
        if (signedIn) ...[
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.circle, size: 7, color: on ? C.accent : C.muted),
            const SizedBox(width: 6),
            Expanded(
                child: Text(
                    s.googleEmail.isEmpty
                        ? (s.lastSync == null ? t('g_never') : t('g_last', {'x': _when(s.lastSync!)}))
                        : '${s.googleEmail} · ${s.lastSync == null ? t('g_never') : _when(s.lastSync!)}',
                    style: TextStyle(color: C.textSoft, fontSize: 12.5),
                    overflow: TextOverflow.ellipsis)),
          ]),
          if (on) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : () => _run(() async => _snack(await s.syncNow() ?? t('g_synced'))),
              style: TextButton.styleFrom(foregroundColor: C.accent, padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
              child: Text(t('g_sync_now'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ] else ...[
            const SizedBox(height: 6),
            OutlinedButton(
              onPressed: _busy ? null : () => _run(() async => s.setSyncPaused(false)),
              style: OutlinedButton.styleFrom(foregroundColor: C.accent, side: BorderSide(color: C.tileOnBorder), minimumSize: const Size(0, 42)),
              child: Text(t('sync_pause_on')),
            ),
          ],
        ],
      ]),
    );
  }

  /// what the Google copy carries: one switch per kind of data
  Widget _partsCard() {
    final all = s.syncCats.length == SyncParts.cats.length;
    return section(Tr.isAr ? 'إيه اللي يتزامن' : 'What to sync', [
      InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => s.setSyncCats(all ? <String>{} : SyncParts.allIds),
        child: Row(children: [
          Expanded(child: Text(Tr.isAr ? 'الكل' : 'Everything', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
          Switch(
            value: all,
            activeTrackColor: C.accent,
            onChanged: (v) => s.setSyncCats(v ? SyncParts.allIds : <String>{}),
          ),
        ]),
      ),
      for (final c in SyncParts.cats)
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => s.setSyncCats(s.syncCats.contains(c.id) ? ({...s.syncCats}..remove(c.id)) : {...s.syncCats, c.id}),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(Tr.isAr ? c.ar : c.en, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                Text(Tr.isAr ? c.subAr : c.subEn, style: TextStyle(color: C.muted, fontSize: 11.5, height: 1.4)),
              ]),
            ),
            Switch(
              value: s.syncCats.contains(c.id),
              activeTrackColor: C.accent,
              onChanged: (v) => s.setSyncCats(v ? {...s.syncCats, c.id} : ({...s.syncCats}..remove(c.id))),
            ),
          ]),
        ),
    ]);
  }

  Widget _scheduleCard() {
    return section(t('sync_schedule'), [
      for (final m in AppState.syncChoices)
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => s.setSyncEvery(m),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              Icon(s.syncEveryMin == m ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  size: 19, color: s.syncEveryMin == m ? C.accent : C.border),
              const SizedBox(width: 11),
              Text(_syncLabel(m), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            ]),
          ),
        ),
    ]);
  }

  Widget _keepCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: cardBox(radius: 18),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('sync_keep_title'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            Text(t('sync_keep_sub'), style: TextStyle(color: C.muted, fontSize: 11.5)),
          ]),
        ),
        _stepButton(Icons.remove, s.syncKeepVersions > 1 ? () => s.setSyncKeepVersions(s.syncKeepVersions - 1) : null),
        SizedBox(
          width: 30,
          child: Text('${s.syncKeepVersions}', textAlign: TextAlign.center, style: mono(16, weight: FontWeight.w700)),
        ),
        _stepButton(Icons.add, s.syncKeepVersions < 10 ? () => s.setSyncKeepVersions(s.syncKeepVersions + 1) : null),
      ]),
    );
  }

  Widget _stepButton(IconData icon, VoidCallback? onTap) => SizedBox(
        width: 32,
        height: 32,
        child: IconButton(
          padding: EdgeInsets.zero,
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          style: IconButton.styleFrom(backgroundColor: C.surface2, foregroundColor: C.text, shape: const CircleBorder()),
        ),
      );

  Widget _versionsCard() {
    final list = _versions;
    return section(t('sync_versions'), [
      if (_versionsLoading && list == null)
        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
      else if (_versionsErr != null)
        Text(t('g_sync_failed'), style: TextStyle(color: C.warn, fontSize: 12.5))
      else if (list == null || list.isEmpty)
        Text(t('sync_versions_empty'), style: TextStyle(color: C.muted, fontSize: 12.5))
      else
        for (var i = 0; i < list.length; i++) _versionRow(list[i], i == 0),
    ]);
  }

  Widget _versionRow(SyncVersion v, bool isLatest) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _busy ? null : () => _restoreVersion(v),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(children: [
            Icon(Icons.radio_button_unchecked, size: 18, color: isLatest ? C.accent : C.border),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_when(v.modified), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                Text('${(v.bytes / 1024).toStringAsFixed(v.bytes < 10240 ? 1 : 0)} KB', textDirection: TextDirection.ltr, style: TextStyle(color: C.muted, fontSize: 11)),
              ]),
            ),
            if (isLatest)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: C.accentBg, borderRadius: BorderRadius.circular(999)),
                child: Text(Tr.isAr ? 'الأحدث' : 'Latest', style: TextStyle(color: C.accent, fontSize: 10.5, fontWeight: FontWeight.w700)),
              )
            else
              Icon(Icons.chevron_left, size: 18, color: C.muted),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final signedIn = !kIsWeb && s.accountType == 'google';
        return Scaffold(
          backgroundColor: C.bg,
          appBar: AppBar(
            backgroundColor: C.bg,
            surfaceTintColor: Colors.transparent,
            title: Text(t('sync_title'), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          body: SafeArea(
            child: RefreshIndicator(
              color: C.accent,
              onRefresh: signedIn ? _loadVersions : () async {},
              child: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 28), children: [
                if (!kIsWeb) ...[_googleCard(), const SizedBox(height: 14)],
                if (signedIn) ...[
                  _partsCard(),
                  const SizedBox(height: 14),
                  _scheduleCard(),
                  const SizedBox(height: 14),
                  _keepCard(),
                  const SizedBox(height: 14),
                  _versionsCard(),
                  const SizedBox(height: 14),
                  const SizedBox(height: 14),
                ],
                section(Tr.isAr ? 'تشفير ملف النسخة الاحتياطية' : 'Backup file encryption', [
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(Tr.isAr ? 'تشفير الملف بباسورد' : 'Encrypt the file with a password', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        Text(Tr.isAr ? 'AES-256. الباسورد بيتحفظ في تخزين الموبايل الآمن وبتكتبه مرة واحدة.' : 'AES-256. The password is kept in the secure storage of the phone; you type it once.',
                            style: TextStyle(color: C.muted, fontSize: 11.5, height: 1.4)),
                      ]),
                    ),
                    Switch(value: _encOn, activeTrackColor: C.accent, onChanged: _busy ? null : _setEnc),
                  ]),
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(Tr.isAr ? 'بصمة الصباع للنسخ والاسترجاع' : 'Fingerprint for backup and restore', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        Text(
                            _encOn
                                ? (Tr.isAr ? 'البصمة مربوطة بالموبايل ده. على موبايل جديد هتكتب الباسورد.' : 'The fingerprint belongs to this phone. On a new phone you type the password.')
                                : (Tr.isAr ? 'فعّل تشفير الملف الأول وبعدين تقدر تقفل الباسورد بالبصمة.' : 'Turn the file encryption on first, then lock the password with your fingerprint.'),
                            style: TextStyle(color: C.muted, fontSize: 11.5, height: 1.4)),
                      ]),
                    ),
                    Switch(value: _bioOn && _encOn, activeTrackColor: C.accent, onChanged: (_busy || !_encOn) ? null : _setBio),
                  ]),
                  if (_encOn && _hasPw)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        onPressed: _busy ? null : _changePw,
                        style: TextButton.styleFrom(foregroundColor: C.accent, padding: EdgeInsets.zero),
                        child: Text(Tr.isAr ? 'تغيير الباسورد' : 'Change the password', style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                ]),
                const SizedBox(height: 14),
                section(t('sync_manual_section'), [
                  CheckboxListTile(
                    value: _app,
                    onChanged: _busy ? null : (v) => setState(() => _app = v ?? false),
                    activeColor: C.accent,
                    checkColor: C.onAccent,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(t('backup_part_app'), style: TextStyle(color: C.text, fontWeight: FontWeight.w600, fontSize: 13.5)),
                  ),
                  CheckboxListTile(
                    value: _hub,
                    onChanged: _busy ? null : (v) => setState(() => _hub = v ?? false),
                    activeColor: C.accent,
                    checkColor: C.onAccent,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(t('backup_part_hub'), style: TextStyle(color: C.text, fontWeight: FontWeight.w600, fontSize: 13.5)),
                  ),
                  const SizedBox(height: 4),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy || _selectedParts.isEmpty ? null : _export,
                        icon: const Icon(Icons.save_alt_outlined, size: 18),
                        label: Text(t('backup_btn_export'), style: const TextStyle(fontSize: 12.5)),
                        style: OutlinedButton.styleFrom(foregroundColor: C.text, side: BorderSide(color: C.border), minimumSize: const Size(0, 52)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy || _selectedParts.isEmpty ? null : _import,
                        icon: const Icon(Icons.upload_file_outlined, size: 18),
                        label: Text(t('backup_btn_import'), style: const TextStyle(fontSize: 12.5)),
                        style: OutlinedButton.styleFrom(foregroundColor: C.text, side: BorderSide(color: C.border), minimumSize: const Size(0, 52)),
                      ),
                    ),
                  ]),
                ]),
                const SizedBox(height: 14),
                emptyCard(t('backup_note'), icon: Icons.lock_outline),
                if (_busy) ...[const SizedBox(height: 16), const Center(child: CircularProgressIndicator())],
              ]),
            ),
          ),
        );
      },
    );
  }
}
