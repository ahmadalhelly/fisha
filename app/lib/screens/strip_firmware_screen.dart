import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'manual_screen.dart' show stripFwDisclaimer;

/// Updates strip firmware through the hub (hub 2.15.8+): upload the .fwr once, pick strips (or all), and the hub
/// updates them one at a time over their normal connection, checking each one's version when it comes back.
class StripFirmwareScreen extends StatefulWidget {
  final AppState state;
  const StripFirmwareScreen({super.key, required this.state});

  @override
  State<StripFirmwareScreen> createState() => _StripFirmwareScreenState();
}

class _StripFirmwareScreenState extends State<StripFirmwareScreen> {
  AppState get s => widget.state;
  Map<String, dynamic>? _hub;
  bool _loaded = false;
  final _picked = <String>{};
  double? _progress;
  String? _error;
  String? _fileName;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_running) _refresh();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  bool get _running => _hub?['running'] == true;
  bool get _hasFile => (_hub?['size'] as num? ?? 0) > 0 && _hub?['valid'] == true;
  List<Map<String, dynamic>> get _items => [for (final x in (_hub?['items'] as List? ?? const [])) if (x is Map<String, dynamic>) x];

  Future<void> _refresh() async {
    final j = await s.stripFwState();
    if (!mounted) return;
    setState(() {
      _hub = j;
      _loaded = true;
    });
  }

  String _name(Strip x) => x.label.isNotEmpty ? x.label : t('default_strip', {'id': x.mac.length > 4 ? x.mac.substring(x.mac.length - 4) : x.mac});

  Future<void> _pickAndUpload() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    final f = r?.files.single;
    if (f == null || f.bytes == null) return;
    if (!AppState.looksLikeStripFw(f.bytes!)) {
      setState(() => _error = t('sfw_bad_file'));
      return;
    }
    setState(() {
      _fileName = f.name;
      _progress = 0;
      _error = null;
    });
    final err = await s.uploadStripFw(f.bytes!, (p) {
      if (mounted) setState(() => _progress = p);
    });
    if (!mounted) return;
    setState(() {
      _progress = null;
      _error = switch (err) {
        null => null,
        'bad_file' => t('sfw_bad_file'),
        'net' => t('fw_err_net'),
        'auth' => t('sfw_owner_only'),
        _ => err,
      };
    });
    _refresh();
  }

  Future<void> _start() async {
    final macs = [for (final x in s.strips) if (x.online && _picked.contains(x.mac)) x.mac];
    if (macs.isEmpty) return;
    if (!await confirmDialog(context, t('sfw_confirm_t'), t('sfw_confirm_b', {'n': macs.length}), ok: t('sfw_start'))) return;
    final err = await s.stripFwStart(macs);
    if (!mounted) return;
    setState(() => _error = err == null ? null : (err == 'net' ? t('fw_err_net') : err));
    _refresh();
  }

  Widget _stateChip(Map<String, dynamic> it) {
    final st = (it['state'] ?? '').toString();
    final color = switch (st) { 'ok' => C.green, 'failed' => C.danger, 'skipped' => C.faint, _ => C.accent };
    final pct = (it['pct'] as num?)?.toInt() ?? 0;
    final label = t('sfw_st_$st') + (st == 'transfer' ? ' $pct%' : '');
    return Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600));
  }

  @override
  Widget build(BuildContext context) {
    final online = [for (final x in s.strips) if (x.online) x];
    _picked.removeWhere((m) => !online.any((x) => x.mac == m));
    final allPicked = online.isNotEmpty && _picked.length == online.length;
    final busy = _progress != null || _running;
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: C.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(t('sfw_title'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 24), children: [
            if (s.mode != ConnMode.local) ...[emptyCard(t('fw_local_only'), icon: Icons.wifi), const SizedBox(height: 14)],
            if (_loaded && _hub == null) ...[emptyCard(t('sfw_hub_old'), icon: Icons.info_outline), const SizedBox(height: 14)],
            stripFwDisclaimer(),
            const SizedBox(height: 14),
            section(t('sfw_file'), [
              Text(t('sfw_how'), style: TextStyle(color: C.muted, fontSize: 12, height: 1.6)),
              Row(children: [
                Icon(_hasFile ? Icons.check_circle_outline : Icons.insert_drive_file_outlined, color: _hasFile ? C.green : C.muted),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(_hasFile
                        ? t('sfw_stored', {'kb': ((_hub!['size'] as num) / 1024).toStringAsFixed(0)})
                        : ((_hub?['why'] ?? '').toString().isNotEmpty ? t('sfw_refused', {'x': _hub!['why']}) : t('sfw_none')))),
              ]),
              OutlinedButton.icon(
                onPressed: busy || _hub == null ? null : _pickAndUpload,
                icon: const Icon(Icons.folder_open),
                label: Text(_fileName ?? t('sfw_pick')),
                style: OutlinedButton.styleFrom(foregroundColor: C.accent, side: BorderSide(color: C.tileOnBorder), minimumSize: const Size(0, 48)),
              ),
              if (_progress != null)
                LinearProgressIndicator(value: _progress, minHeight: 6, color: C.accent, backgroundColor: C.surface2, borderRadius: BorderRadius.circular(3)),
            ]),
            const SizedBox(height: 14),
            section(t('sfw_strips'), [
              if (online.isEmpty) Text(t('sfw_no_strips'), style: TextStyle(color: C.muted)),
              if (online.isNotEmpty)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: allPicked,
                  onChanged: busy ? null : (v) => setState(() => v == true ? _picked.addAll(online.map((x) => x.mac)) : _picked.clear()),
                  title: Text(t('sfw_all'), style: const TextStyle(fontWeight: FontWeight.w700)),
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: C.accent,
                ),
              for (final x in online)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _picked.contains(x.mac),
                  onChanged: busy ? null : (v) => setState(() => v == true ? _picked.add(x.mac) : _picked.remove(x.mac)),
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: C.accent,
                  title: Text(_name(x), style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${x.mac}  ·  fw ${x.fw.isEmpty ? '—' : x.fw}', textDirection: TextDirection.ltr, style: mono(12, color: C.muted)),
                ),
            ]),
            const SizedBox(height: 16),
            if (_running)
              OutlinedButton.icon(
                onPressed: () async {
                  await s.stripFwCancel();
                  _refresh();
                },
                icon: const Icon(Icons.stop_circle_outlined),
                label: Text(t('sfw_cancel')),
                style: OutlinedButton.styleFrom(foregroundColor: C.danger, side: BorderSide(color: C.danger), minimumSize: const Size(0, 48)),
              )
            else
              primaryButton(t('sfw_start'), _hasFile && _picked.isNotEmpty && s.mode == ConnMode.local && _progress == null ? _start : null,
                  icon: Icons.system_update_alt),
            if (_running) ...[const SizedBox(height: 8), Center(child: Text(t('sfw_keep_power'), style: TextStyle(color: C.muted, fontSize: 12)))],
            if (_error != null) ...[const SizedBox(height: 12), emptyCard(_error!, icon: Icons.error_outline)],
            if (_items.isNotEmpty) ...[
              const SizedBox(height: 14),
              section(t('sfw_progress'), [
                for (final it in _items)
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(() {
                          final m = (it['mac'] ?? '').toString();
                          final x = s.strips.where((e) => e.mac == m);
                          return x.isEmpty ? m : _name(x.first);
                        }(), style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                            [
                              if ((it['from'] ?? '').toString().isNotEmpty) it['from'],
                              if ((it['to'] ?? '').toString().isNotEmpty) '→ ${it['to']}',
                              if ((it['msg'] ?? '').toString().isNotEmpty) it['msg'],
                            ].join('  '),
                            textDirection: TextDirection.ltr,
                            style: mono(11, color: C.muted)),
                      ]),
                    ),
                    _stateChip(it),
                  ]),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}
