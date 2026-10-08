import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'backup_screen.dart';

String _tr(String ar, String en) => Tr.isAr ? ar : en;

/// A scenario sets several outlets at once ("Leaving home", "Night"...). Kept on the phone.
class Scene {
  String id;
  String name;
  Map<String, bool> actions; // "MAC|n" -> on
  Scene(this.id, this.name, this.actions);
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'actions': actions};
  factory Scene.fromJson(Map<String, dynamic> j) =>
      Scene((j['id'] ?? '').toString(), (j['name'] ?? '').toString(), Map<String, bool>.from((j['actions'] as Map?) ?? {}));
}

class SceneStore {
  static Future<List<Scene>> load() async {
    final raw = (await SharedPreferences.getInstance()).getString('scenes');
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).whereType<Map<String, dynamic>>().map(Scene.fromJson).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<Scene> list) async =>
      (await SharedPreferences.getInstance()).setString('scenes', jsonEncode([for (final s in list) s.toJson()]));
}

/// Runs a scenario. Offline strips are skipped; protected outlets are never switched off by a scenario.
Future<int> runScene(AppState state, Scene sc) async {
  var done = 0;
  bool? bioPassed;
  for (final e in sc.actions.entries) {
    final p = e.key.split('|');
    if (p.length != 2) continue;
    final strip = state.live(p[0]);
    final n = int.tryParse(p[1]) ?? 0;
    if (strip == null || !strip.online || n < 1) continue;
    final o = strip.outlets.firstWhere((x) => x.n == n, orElse: () => strip.outlets.first);
    if (!e.value && o.protected) continue;
    if (o.on == e.value) {
      done++;
      continue;
    }
    if (state.requiresBio(strip.mac, n)) {
      bioPassed ??= await authenticateBio(
        _tr('تأكيد بالبصمة لتشغيل السيناريو', 'Authenticate to run scenario'),
      );
      if (bioPassed != true) continue;
    }
    await state.setOutlet(strip.mac, n, e.value);
    done++;
  }
  return done;
}

class ScenesScreen extends StatefulWidget {
  final AppState state;
  const ScenesScreen({super.key, required this.state});

  @override
  State<ScenesScreen> createState() => _ScenesScreenState();
}

class _ScenesScreenState extends State<ScenesScreen> {
  List<Scene> _scenes = [];
  String? _running;

  @override
  void initState() {
    super.initState();
    SceneStore.load().then((v) => mounted ? setState(() => _scenes = v) : null);
  }

  Future<void> _edit([Scene? sc]) async {
    final r = await Navigator.of(context).push<Scene?>(MaterialPageRoute(builder: (_) => _SceneEditor(state: widget.state, initial: sc)));
    if (r == null) return;
    setState(() {
      final i = _scenes.indexWhere((x) => x.id == r.id);
      if (r.actions.isEmpty) {
        if (i >= 0) _scenes.removeAt(i);
      } else if (i >= 0) {
        _scenes[i] = r;
      } else {
        _scenes.add(r);
      }
    });
    await SceneStore.save(_scenes);
  }

  Future<void> _run(Scene sc) async {
    setState(() => _running = sc.id);
    final n = await runScene(widget.state, sc);
    if (!mounted) return;
    setState(() => _running = null);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_tr('اتنفذ "${sc.name}" على $n مخرج', 'Ran "${sc.name}" on $n outlets'))));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: C.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(_tr('السيناريوهات', 'Scenarios'), style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_backup_restore),
            tooltip: t('backup_title'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BackupScreen(state: widget.state))),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        backgroundColor: C.accent,
        foregroundColor: C.onAccent,
        icon: const Icon(Icons.add),
        label: Text(_tr('سيناريو جديد', 'New scenario'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 96), children: [
          if (_scenes.isEmpty)
            emptyCard(_tr('السيناريو بيشغّل ويقفل كذا مخرج بضغطة واحدة. مثلاً "خارج من البيت" يقفل كل حاجة ما عدا الراوتر، أو "وقت الشغل" يشغّل الكمبيوتر والشاشة واللمبة.',
                'A scenario switches several outlets with one tap. E.g. "Leaving home" turns everything off except the router.'), icon: Icons.auto_awesome),
          for (final sc in _scenes)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: C.card,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: C.cardEdge)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: _running == null ? () => _run(sc) : null,
                  onLongPress: () => _edit(sc),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(color: C.accentBg, borderRadius: BorderRadius.circular(14)),
                        child: _running == sc.id
                            ? Padding(padding: const EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: C.accent))
                            : ScenesIcon(size: 24, color: C.accent),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(sc.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                          Text(
                            _tr('${sc.actions.values.where((v) => v).length} تشغيل · ${sc.actions.values.where((v) => !v).length} قفل',
                                '${sc.actions.values.where((v) => v).length} on · ${sc.actions.values.where((v) => !v).length} off'),
                            style: TextStyle(color: C.muted, fontSize: 12),
                          ),
                        ]),
                      ),
                      IconButton(icon: Icon(Icons.edit_outlined, color: C.muted), onPressed: () => _edit(sc)),
                      Icon(Icons.play_arrow_rounded, color: C.accent),
                    ]),
                  ),
                ),
              ),
            ),
          if (_scenes.isNotEmpty) Text(_tr('اضغط على السيناريو لتشغيله، ومطوّلاً لتعديله.', 'Tap a scenario to run it, long-press to edit.'), textAlign: TextAlign.center, style: TextStyle(color: C.muted, fontSize: 12)),
        ]),
      ),
    );
  }
}

class _SceneEditor extends StatefulWidget {
  final AppState state;
  final Scene? initial;
  const _SceneEditor({required this.state, this.initial});

  @override
  State<_SceneEditor> createState() => _SceneEditorState();
}

class _SceneEditorState extends State<_SceneEditor> {
  late final TextEditingController _name = TextEditingController(text: widget.initial?.name ?? '');
  late final Map<String, bool> _actions = Map.of(widget.initial?.actions ?? {});

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty || _actions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_tr('اكتب اسم واختار مخرج واحد على الأقل', 'Enter a name and pick at least one outlet'))));
      return;
    }
    Navigator.of(context).pop(Scene(widget.initial?.id ?? DateTime.now().millisecondsSinceEpoch.toString(), name, _actions));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: C.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(widget.initial == null ? _tr('سيناريو جديد', 'New scenario') : _tr('تعديل السيناريو', 'Edit scenario'), style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          if (widget.initial != null)
            IconButton(
              icon: Icon(Icons.delete_outline, color: C.danger),
              onPressed: () => Navigator.of(context).pop(Scene(widget.initial!.id, widget.initial!.name, {})),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 24), children: [
          TextField(controller: _name, maxLength: 24, decoration: InputDecoration(labelText: _tr('اسم السيناريو', 'Scenario name'), hintText: _tr('مثلاً: خارج من البيت', 'e.g. Leaving home'))),
          Text(_tr('لكل مخرج اختار: تجاهل، تشغيل، أو قفل', 'For each outlet choose: skip, on or off'), style: TextStyle(color: C.muted, fontSize: 12)),
          const SizedBox(height: 10),
          for (final st in s.allStrips) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 6),
              child: Text(s.stripName(st), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            for (final o in st.outlets)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Expanded(
                    child: Row(children: [
                      if (o.protected) Padding(padding: const EdgeInsetsDirectional.only(end: 4), child: Icon(Icons.shield, size: 14, color: C.accent)),
                      Flexible(child: Text(s.outletName(st, o.n), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ]),
                  ),
                  SizedBox(
                    width: 190,
                    child: Segmented<int>(
                      value: !_actions.containsKey('${st.mac}|${o.n}') ? 0 : (_actions['${st.mac}|${o.n}']! ? 1 : 2),
                      items: {0: '—', 1: t('turn_on'), 2: t('turn_off')},
                      onChanged: (v) => setState(() {
                        final k = '${st.mac}|${o.n}';
                        if (v == 0) {
                          _actions.remove(k);
                        } else {
                          _actions[k] = v == 1;
                        }
                      }),
                    ),
                  ),
                ]),
              ),
          ],
          const SizedBox(height: 6),
          emptyCard(_tr('المخارج المحمية (زي الراوتر) مش هتتقفل من السيناريو حتى لو اخترت "قفل".', 'Protected outlets (like the router) are never switched off by a scenario.'), icon: Icons.shield_outlined),
          const SizedBox(height: 16),
          primaryButton(t('save'), _save, icon: Icons.check),
        ]),
      ),
    );
  }
}
