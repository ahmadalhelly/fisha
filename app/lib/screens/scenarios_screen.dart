import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

String _tr(String ar, String en) => Tr.isAr ? ar : en;

/// One action of a scenario: on, off, delay, cycle, lock, unlock or notify.
class ScenAction {
  String type; // on | off | delay | cycle | lock | unlock | notify
  String mac;
  int outlet;
  int secs;
  String msg;
  ScenAction(this.type, {this.mac = '', this.outlet = 0, this.secs = 0, this.msg = ''});

  static List<ScenAction> parse(String text) {
    final out = <ScenAction>[];
    for (final item in text.split(';')) {
      if (item.trim().isEmpty) continue;
      final f = item.split(',');
      String at(int i) => i < f.length ? f[i] : '';
      out.add(ScenAction(at(0), mac: at(1), outlet: int.tryParse(at(2)) ?? 0, secs: int.tryParse(at(3)) ?? 0, msg: at(4)));
    }
    return out;
  }

  static String encode(List<ScenAction> l) => [for (final a in l) '${a.type},${a.mac},${a.outlet},${a.secs},${a.msg.replaceAll(RegExp(r'[,;"\\]'), ' ')}'].join(';');
}

/// A scenario as the hub keeps it (flat JSON, see hub_scen.h).
class Scenario {
  int id;
  bool en;
  String name;
  int tt; // 1 reading, 2 outlet, 3 time of day, 4 power came back, 5 cloud link down
  String tmac;
  int tn, tmet, top, tv, th, thh, tmm, tdays;
  int cfh, cfm, cth, ctm, cd; // time window (cfh < 0 = none) and days
  String cmac;
  int cn, cv; // outlet condition (cv < 0 = none)
  List<ScenAction> act, els;

  Scenario({
    this.id = 0,
    this.en = true,
    this.name = '',
    this.tt = 1,
    this.tmac = '',
    this.tn = 1,
    this.tmet = 0,
    this.top = 0,
    this.tv = 5,
    this.th = 600,
    this.thh = 22,
    this.tmm = 0,
    this.tdays = 127,
    this.cfh = -1,
    this.cfm = 0,
    this.cth = 0,
    this.ctm = 0,
    this.cd = 127,
    this.cmac = '',
    this.cn = 1,
    this.cv = -1,
    List<ScenAction>? act,
    List<ScenAction>? els,
  })  : act = act ?? [],
        els = els ?? [];

  factory Scenario.fromJson(Map<String, dynamic> j) {
    int n(String k, int d) => j[k] is num ? (j[k] as num).toInt() : (int.tryParse('${j[k] ?? ''}') ?? d);
    return Scenario(
      id: n('id', 0),
      en: j['en'] != false,
      name: (j['name'] ?? '').toString(),
      tt: n('tt', 1),
      tmac: (j['tmac'] ?? '').toString(),
      tn: n('tn', 1),
      tmet: n('tmet', 0),
      top: n('top', 0),
      tv: n('tv', 0),
      th: n('th', 0),
      thh: n('thh', 0),
      tmm: n('tmm', 0),
      tdays: n('tdays', 127),
      cfh: n('cfh', -1),
      cfm: n('cfm', 0),
      cth: n('cth', 0),
      ctm: n('ctm', 0),
      cd: n('cd', 127),
      cmac: (j['cmac'] ?? '').toString(),
      cn: n('cn', 1),
      cv: n('cv', -1),
      act: ScenAction.parse((j['a'] ?? '').toString()),
      els: ScenAction.parse((j['e'] ?? '').toString()),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'en': en,
        'name': name.replaceAll(RegExp(r'["\\]'), ' '),
        'tt': tt,
        'tmac': tmac,
        'tn': tn,
        'tmet': tmet,
        'top': top,
        'tv': tv,
        'th': th,
        'thh': thh,
        'tmm': tmm,
        'tdays': tdays,
        'cfh': cfh,
        'cfm': cfm,
        'cth': cth,
        'ctm': ctm,
        'cd': cd,
        'cmac': cmac,
        'cn': cn,
        'cv': cv,
        'a': ScenAction.encode(act),
        'e': ScenAction.encode(els),
      };
}

/// The scenarios of the hub: a list with switches, ready-made starting points and the editor.
class ScenariosScreen extends StatefulWidget {
  final AppState state;
  const ScenariosScreen({super.key, required this.state});

  @override
  State<ScenariosScreen> createState() => _ScenariosScreenState();
}

class _ScenariosScreenState extends State<ScenariosScreen> {
  AppState get s => widget.state;
  List<Scenario> _list = const [];
  bool _loading = true, _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final r = await s.api('scen_list');
    final l = r.data?['scens'];
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (!r.ok || l is! List) {
        _failed = true;
      } else {
        _list = [for (final j in l) if (j is Map<String, dynamic>) Scenario.fromJson(j)];
      }
    });
  }

  String get _firstMac => s.allStrips.isEmpty ? '' : s.allStrips.first.mac;

  List<(String, String, IconData, Scenario Function())> get _templates => [
        (
          _tr('الشاحن اكتمل', 'Charger finished'),
          _tr('لو الوات أقل من 5 لمدة 10 دقايق، اطفي المخرج وابعتلي إشعار.', 'If the power stays under 5 W for 10 minutes, switch the outlet off and notify me.'),
          Icons.battery_charging_full,
          () => Scenario(name: _tr('الشاحن اكتمل', 'Charger finished'), tt: 1, tmac: _firstMac, tn: 1, tmet: 0, top: 0, tv: 5, th: 600, act: [
                ScenAction('off', mac: _firstMac, outlet: 1),
                ScenAction('notify', mac: _firstMac, outlet: 1, msg: _tr('الشحن خلص', 'Charging is done')),
              ]),
        ),
        (
          _tr('بعد انقطاع الكهربا', 'After a power cut'),
          _tr('لما الكهربا ترجع، شغّل المخرج بعد 3 دقايق.', 'When the power is back, switch the outlet on after 3 minutes.'),
          Icons.flash_on,
          () => Scenario(name: _tr('بعد انقطاع الكهربا', 'After a power cut'), tt: 4, act: [
                ScenAction('delay', secs: 180),
                ScenAction('on', mac: _firstMac, outlet: 1),
              ]),
        ),
        (
          _tr('السخان', 'Heater'),
          _tr('لو المخرج اشتغل، اطفيه بعد ساعة.', 'When the outlet goes on, switch it off after an hour.'),
          Icons.thermostat,
          () => Scenario(name: _tr('السخان', 'Heater'), tt: 2, tmac: _firstMac, tn: 1, tv: 1, act: [
                ScenAction('delay', secs: 3600),
                ScenAction('off', mac: _firstMac, outlet: 1),
              ]),
        ),
        (
          _tr('الراوتر', 'Router'),
          _tr('لو النت وقع 3 دقايق، أعيد تشغيل المخرج 30 ثانية.', 'If the internet is down for 3 minutes, restart the outlet for 30 seconds.'),
          Icons.router_outlined,
          () => Scenario(name: _tr('الراوتر', 'Router'), tt: 5, th: 180, act: [ScenAction('cycle', mac: _firstMac, outlet: 1, secs: 30)]),
        ),
      ];

  Future<void> _edit(Scenario sc) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => ScenarioEditor(state: s, scenario: sc)));
    if (changed == true) _load();
  }

  Future<void> _toggle(Scenario sc, bool v) async {
    sc.en = v;
    setState(() {});
    final r = await s.api('scen_save', sc.toJson());
    if (!r.ok && mounted) {
      sc.en = !v;
      setState(() {});
    }
  }

  String _summary(Scenario sc) {
    switch (sc.tt) {
      case 1:
        const m = ['W', 'A', '°C', 'V'];
        return '${m[sc.tmet.clamp(0, 3)]} ${sc.top == 0 ? '<' : '>'} ${sc.tv} · ${sc.th ~/ 60} ${_tr('د', 'min')}';
      case 2:
        return sc.tv == 1 ? _tr('لما المخرج يشتغل', 'when an outlet goes on') : _tr('لما المخرج يفصل', 'when an outlet goes off');
      case 3:
        return '${sc.thh.toString().padLeft(2, '0')}:${sc.tmm.toString().padLeft(2, '0')}';
      case 4:
        return _tr('لما الكهربا ترجع', 'when the power is back');
      default:
        return _tr('لما النت يقع', 'when the internet is down');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: C.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(_tr('السيناريوهات', 'Scenarios'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: C.accent,
        foregroundColor: C.onAccent,
        onPressed: () => _edit(Scenario(name: '', tmac: _firstMac)),
        icon: const Icon(Icons.add),
        label: Text(_tr('سيناريو جديد', 'New scenario')),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: C.accent,
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 96), children: [
            if (_loading) const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
            else if (_failed) emptyCard(_tr('الهاب مش بيرد على السيناريوهات. حدّث الهاب لآخر نسخة.', 'The hub does not answer. Update the hub to the latest version.'), icon: Icons.bolt)
            else ...[
              Text(_tr('سيناريوهاتي', 'My scenarios'), style: TextStyle(color: C.muted, fontSize: 12.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (_list.isEmpty)
                emptyCard(_tr('مفيش سيناريوهات لسه. ابدأ بقالب من تحت.', 'No scenarios yet. Start from a template below.'), icon: Icons.bolt)
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  decoration: cardBox(radius: 18),
                  child: Column(children: [
                    for (final sc in _list)
                      InkWell(
                        onTap: () => _edit(sc),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(children: [
                            Icon(Icons.bolt, color: sc.en ? C.accent : C.muted),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(sc.name.isEmpty ? _tr('بدون اسم', 'Unnamed') : sc.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                                Text(_summary(sc), style: TextStyle(color: C.muted, fontSize: 12)),
                              ]),
                            ),
                            Switch(value: sc.en, activeTrackColor: C.accent, onChanged: (v) => _toggle(sc, v)),
                          ]),
                        ),
                      ),
                  ]),
                ),
              const SizedBox(height: 18),
              Text(_tr('قوالب جاهزة', 'Templates'), style: TextStyle(color: C.muted, fontSize: 12.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (final tpl in _templates)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: cardBox(radius: 18),
                  child: Row(children: [
                    Icon(tpl.$3, color: C.accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tpl.$1, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                        const SizedBox(height: 2),
                        Text(tpl.$2, style: TextStyle(color: C.muted, fontSize: 12, height: 1.5)),
                      ]),
                    ),
                    TextButton(onPressed: s.allStrips.isEmpty ? null : () => _edit(tpl.$4()), child: Text(_tr('استخدم', 'Use'))),
                  ]),
                ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// The editor: when (trigger), if (conditions), do (actions), otherwise (else actions).
class ScenarioEditor extends StatefulWidget {
  final AppState state;
  final Scenario scenario;
  const ScenarioEditor({super.key, required this.state, required this.scenario});

  @override
  State<ScenarioEditor> createState() => _ScenarioEditorState();
}

class _ScenarioEditorState extends State<ScenarioEditor> {
  AppState get s => widget.state;
  late final Scenario sc = widget.scenario;
  late final TextEditingController _name = TextEditingController(text: sc.name);
  bool _busy = false;
  bool _showElse = false;

  @override
  void initState() {
    super.initState();
    _showElse = sc.els.isNotEmpty;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  List<Strip> get _strips => s.allStrips;

  String _stripLabel(String mac) {
    final l = _strips.where((x) => x.mac.toUpperCase() == mac.toUpperCase().replaceAll(':', ''));
    return l.isEmpty ? (mac.isEmpty ? '—' : mac) : s.stripName(l.first);
  }

  String _macOf(Strip st) => st.mac.toUpperCase().replaceAll(':', '');

  Widget _stripPicker(String mac, void Function(String) onPick, {bool outletZero = false, int? outlet, void Function(int)? onOutlet}) {
    final macs = [for (final x in _strips) _macOf(x)];
    final cur = macs.contains(mac.toUpperCase().replaceAll(':', '')) ? mac.toUpperCase().replaceAll(':', '') : null;
    return Row(children: [
      Expanded(
        child: DropdownButton<String>(
          isExpanded: true,
          value: cur,
          hint: Text(_tr('اختار مشترك', 'Pick a strip')),
          dropdownColor: C.surface2,
          items: [for (final x in _strips) DropdownMenuItem(value: _macOf(x), child: Text(s.stripName(x), overflow: TextOverflow.ellipsis))],
          onChanged: (v) {
            if (v != null) setState(() => onPick(v));
          },
        ),
      ),
      if (onOutlet != null) ...[
        const SizedBox(width: 10),
        DropdownButton<int>(
          value: outlet,
          dropdownColor: C.surface2,
          items: [
            if (outletZero) DropdownMenuItem(value: 0, child: Text(_tr('كله', 'All'))),
            for (var i = 1; i <= 4; i++) DropdownMenuItem(value: i, child: Text('${_tr('مخرج', 'Outlet')} $i')),
          ],
          onChanged: (v) {
            if (v != null) setState(() => onOutlet(v));
          },
        ),
      ],
    ]);
  }

  Future<int?> _pickTime(int h, int m) async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59)));
    return t == null ? null : t.hour * 60 + t.minute;
  }

  Widget _days(int mask, void Function(int) onChange) {
    const ar = ['أحد', 'اتنين', 'تلات', 'أربع', 'خميس', 'جمعة', 'سبت'];
    const en = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (var i = 0; i < 7; i++)
        FilterChip(
          label: Text(Tr.isAr ? ar[i] : en[i]),
          selected: mask & (1 << i) != 0,
          onSelected: (v) => setState(() => onChange(v ? mask | (1 << i) : mask & ~(1 << i))),
        ),
    ]);
  }

  Widget _block(String title, String sub, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: cardBox(radius: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: C.accent, borderRadius: BorderRadius.circular(8)),
              child: Text(title, style: TextStyle(color: C.onAccent, fontWeight: FontWeight.w800, fontSize: 13.5)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(sub, style: TextStyle(color: C.muted, fontSize: 12.5))),
          ]),
          const SizedBox(height: 10),
          ...children,
        ]),
      );

  Widget _trigger() {
    return _block(_tr('لو', 'When'), _tr('الحدث', 'the event'), [
      DropdownButton<int>(
        isExpanded: true,
        value: sc.tt,
        dropdownColor: C.surface2,
        items: [
          DropdownMenuItem(value: 1, child: Text(_tr('قراءة فوق أو تحت حد', 'A reading above or below a limit'))),
          DropdownMenuItem(value: 2, child: Text(_tr('مخرج اشتغل أو فصل', 'An outlet goes on or off'))),
          DropdownMenuItem(value: 3, child: Text(_tr('ميعاد', 'A time of day'))),
          DropdownMenuItem(value: 4, child: Text(_tr('الكهربا رجعت بعد انقطاع', 'The power came back'))),
          DropdownMenuItem(value: 5, child: Text(_tr('النت وقع', 'The internet is down'))),
        ],
        onChanged: (v) => setState(() => sc.tt = v ?? 1),
      ),
      if (sc.tt == 1) ...[
        _stripPicker(sc.tmac, (v) => sc.tmac = v, outletZero: true, outlet: sc.tn, onOutlet: (v) => sc.tn = v),
        Wrap(spacing: 6, children: [
          for (final e in [(0, 'W'), (1, 'A'), (2, '°C'), (3, 'V')]) ChoiceChip(label: Text(e.$2), selected: sc.tmet == e.$1, onSelected: (_) => setState(() => sc.tmet = e.$1)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          ChoiceChip(label: Text(_tr('أقل من', 'Below')), selected: sc.top == 0, onSelected: (_) => setState(() => sc.top = 0)),
          const SizedBox(width: 6),
          ChoiceChip(label: Text(_tr('أكتر من', 'Above')), selected: sc.top == 1, onSelected: (_) => setState(() => sc.top = 1)),
          const SizedBox(width: 12),
          SizedBox(
            width: 90,
            child: TextFormField(
              initialValue: '${sc.tv}',
              keyboardType: TextInputType.number,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: _tr('الحد', 'Limit')),
              onChanged: (v) => sc.tv = int.tryParse(v) ?? sc.tv,
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Text(_tr('لمدة', 'For')),
          const SizedBox(width: 10),
          SizedBox(
            width: 90,
            child: TextFormField(
              initialValue: '${sc.th ~/ 60}',
              keyboardType: TextInputType.number,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(suffixText: _tr('دقيقة', 'min')),
              onChanged: (v) => sc.th = (int.tryParse(v) ?? (sc.th ~/ 60)) * 60,
            ),
          ),
        ]),
      ],
      if (sc.tt == 2) ...[
        _stripPicker(sc.tmac, (v) => sc.tmac = v, outlet: sc.tn.clamp(1, 4), onOutlet: (v) => sc.tn = v),
        Row(children: [
          ChoiceChip(label: Text(_tr('اشتغل', 'goes on')), selected: sc.tv == 1, onSelected: (_) => setState(() => sc.tv = 1)),
          const SizedBox(width: 6),
          ChoiceChip(label: Text(_tr('فصل', 'goes off')), selected: sc.tv != 1, onSelected: (_) => setState(() => sc.tv = 0)),
        ]),
      ],
      if (sc.tt == 3) ...[
        OutlinedButton.icon(
          onPressed: () async {
            final v = await _pickTime(sc.thh, sc.tmm);
            if (v != null) setState(() {
              sc.thh = v ~/ 60;
              sc.tmm = v % 60;
            });
          },
          icon: const Icon(Icons.schedule),
          label: Text('${sc.thh.toString().padLeft(2, '0')}:${sc.tmm.toString().padLeft(2, '0')}', textDirection: TextDirection.ltr),
        ),
        const SizedBox(height: 8),
        _days(sc.tdays, (m) => sc.tdays = m),
      ],
      if (sc.tt == 4) Text(_tr('بيشتغل مرة واحدة بعد ما الهاب يقوم من انقطاع الكهربا.', 'Runs once, a minute after the hub starts following a power cut.'), style: TextStyle(color: C.muted, fontSize: 12, height: 1.5)),
      if (sc.tt == 5) ...[
        Row(children: [
          Text(_tr('لمدة', 'For')),
          const SizedBox(width: 10),
          SizedBox(
            width: 90,
            child: TextFormField(
              initialValue: '${sc.th ~/ 60}',
              keyboardType: TextInputType.number,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(suffixText: _tr('دقيقة', 'min')),
              onChanged: (v) => sc.th = (int.tryParse(v) ?? (sc.th ~/ 60)) * 60,
            ),
          ),
        ]),
        Text(_tr('يحتاج إعداد السحابة في الهاب.', 'Needs the cloud set up on the hub.'), style: TextStyle(color: C.muted, fontSize: 12)),
      ],
    ]);
  }

  Widget _conditions() {
    final window = sc.cfh >= 0;
    return _block(_tr('بشرط', 'If'), _tr('اختياري', 'optional'), [
      Row(children: [
        Expanded(child: Text(_tr('وقت من / لـ', 'Time window'))),
        Switch(value: window, activeTrackColor: C.accent, onChanged: (v) => setState(() => sc.cfh = v ? 22 : -1)),
      ]),
      if (window)
        Row(children: [
          OutlinedButton(
            onPressed: () async {
              final v = await _pickTime(sc.cfh, sc.cfm);
              if (v != null) setState(() {
                sc.cfh = v ~/ 60;
                sc.cfm = v % 60;
              });
            },
            child: Text('${sc.cfh.toString().padLeft(2, '0')}:${sc.cfm.toString().padLeft(2, '0')}', textDirection: TextDirection.ltr),
          ),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text(_tr('لـ', 'to'))),
          OutlinedButton(
            onPressed: () async {
              final v = await _pickTime(sc.cth, sc.ctm);
              if (v != null) setState(() {
                sc.cth = v ~/ 60;
                sc.ctm = v % 60;
              });
            },
            child: Text('${sc.cth.toString().padLeft(2, '0')}:${sc.ctm.toString().padLeft(2, '0')}', textDirection: TextDirection.ltr),
          ),
        ]),
      const SizedBox(height: 8),
      Text(_tr('الأيام', 'Days'), style: TextStyle(color: C.muted, fontSize: 12)),
      const SizedBox(height: 4),
      _days(sc.cd, (m) => sc.cd = m),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: Text(_tr('حالة مخرج', 'State of an outlet'))),
        Switch(value: sc.cv >= 0, activeTrackColor: C.accent, onChanged: (v) => setState(() => sc.cv = v ? 1 : -1)),
      ]),
      if (sc.cv >= 0) ...[
        _stripPicker(sc.cmac, (v) => sc.cmac = v, outlet: sc.cn.clamp(1, 4), onOutlet: (v) => sc.cn = v),
        Row(children: [
          ChoiceChip(label: Text(_tr('شغال', 'is on')), selected: sc.cv == 1, onSelected: (_) => setState(() => sc.cv = 1)),
          const SizedBox(width: 6),
          ChoiceChip(label: Text(_tr('مطفي', 'is off')), selected: sc.cv == 0, onSelected: (_) => setState(() => sc.cv = 0)),
        ]),
      ],
    ]);
  }

  String _actionText(ScenAction a) {
    final where = a.mac.isEmpty ? '' : ' · ${_stripLabel(a.mac)}${a.outlet == 0 ? '' : ' ${_tr('مخرج', 'outlet')} ${a.outlet}'}';
    switch (a.type) {
      case 'on':
        return '${_tr('شغّل', 'Switch on')}$where';
      case 'off':
        return '${_tr('اطفي', 'Switch off')}$where';
      case 'delay':
        return '${_tr('استنى', 'Wait')} ${a.secs ~/ 60} ${_tr('دقيقة', 'min')}';
      case 'cycle':
        return '${_tr('إعادة تشغيل', 'Restart')} ${a.secs} ${_tr('ثانية', 's')}$where';
      case 'lock':
        return '${_tr('قفل الأطفال', 'Child lock on')}$where';
      case 'unlock':
        return '${_tr('فتح قفل الأطفال', 'Child lock off')}$where';
      default:
        return '${_tr('إشعار', 'Notify')}: ${a.msg.isEmpty ? sc.name : a.msg}';
    }
  }

  Future<void> _addAction(List<ScenAction> into) async {
    var type = 'off';
    var mac = _strips.isEmpty ? '' : _macOf(_strips.first);
    var outlet = 1;
    var secs = 10;
    final msg = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: C.surface,
          title: Text(_tr('إضافة إجراء', 'Add an action')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              DropdownButton<String>(
                isExpanded: true,
                value: type,
                dropdownColor: C.surface2,
                items: [
                  DropdownMenuItem(value: 'on', child: Text(_tr('شغّل مخرج', 'Switch an outlet on'))),
                  DropdownMenuItem(value: 'off', child: Text(_tr('اطفي مخرج', 'Switch an outlet off'))),
                  DropdownMenuItem(value: 'delay', child: Text(_tr('تأخير', 'Wait'))),
                  DropdownMenuItem(value: 'cycle', child: Text(_tr('إعادة تشغيل مخرج', 'Restart an outlet'))),
                  DropdownMenuItem(value: 'lock', child: Text(_tr('قفل الأطفال', 'Child lock on'))),
                  DropdownMenuItem(value: 'unlock', child: Text(_tr('فتح قفل الأطفال', 'Child lock off'))),
                  DropdownMenuItem(value: 'notify', child: Text(_tr('إشعار', 'Notification'))),
                ],
                onChanged: (v) => setD(() => type = v ?? type),
              ),
              if (type != 'delay' && type != 'notify' || type == 'notify')
                Row(children: [
                  Expanded(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _strips.any((x) => _macOf(x) == mac) ? mac : null,
                      dropdownColor: C.surface2,
                      items: [for (final x in _strips) DropdownMenuItem(value: _macOf(x), child: Text(s.stripName(x), overflow: TextOverflow.ellipsis))],
                      onChanged: (v) => setD(() => mac = v ?? mac),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: outlet,
                    dropdownColor: C.surface2,
                    items: [for (var i = 0; i <= 4; i++) DropdownMenuItem(value: i, child: Text(i == 0 ? _tr('كله', 'All') : '${_tr('مخرج', 'Outlet')} $i'))],
                    onChanged: (v) => setD(() => outlet = v ?? outlet),
                  ),
                ]),
              if (type == 'delay' || type == 'cycle')
                TextFormField(
                  initialValue: type == 'delay' ? '5' : '10',
                  keyboardType: TextInputType.number,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: type == 'delay' ? _tr('دقايق', 'Minutes') : _tr('ثواني الإطفاء', 'Seconds off')),
                  onChanged: (v) => secs = (int.tryParse(v) ?? 0) * (type == 'delay' ? 60 : 1),
                ),
              if (type == 'notify') TextField(controller: msg, decoration: InputDecoration(labelText: _tr('نص الإشعار', 'Message'))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'), style: TextStyle(color: C.muted))),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_tr('تمام', 'OK'), style: TextStyle(color: C.accent, fontWeight: FontWeight.w700))),
          ],
        ),
      ),
    );
    final text = msg.text;
    msg.dispose();
    if (ok != true) return;
    if (type == 'delay' && secs == 0) secs = 300;
    if (type == 'cycle' && secs == 0) secs = 10;
    setState(() => into.add(ScenAction(type, mac: type == 'delay' ? '' : mac, outlet: outlet, secs: secs, msg: text)));
  }

  Widget _actions(String title, String sub, List<ScenAction> list) {
    return _block(title, sub, [
      for (var i = 0; i < list.length; i++)
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(_actionText(list[i])),
          trailing: IconButton(icon: Icon(Icons.close, color: C.muted), onPressed: () => setState(() => list.removeAt(i))),
        ),
      OutlinedButton.icon(onPressed: () => _addAction(list), icon: const Icon(Icons.add), label: Text(_tr('إضافة إجراء', 'Add an action'))),
    ]);
  }

  Future<void> _save() async {
    sc.name = _name.text.trim();
    if (sc.name.isEmpty) sc.name = _tr('سيناريو', 'Scenario');
    if (sc.act.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_tr('ضيف إجراء واحد على الأقل.', 'Add at least one action.'))));
      return;
    }
    if ((sc.tt == 1 || sc.tt == 2) && sc.tmac.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_tr('اختار المشترك اللي بيبدأ السيناريو.', 'Pick the strip that starts the scenario.'))));
      return;
    }
    setState(() => _busy = true);
    final r = await s.api('scen_save', sc.toJson());
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.error == 'too many scenarios' ? _tr('وصلت للحد الأقصى (8 سيناريوهات).', 'The limit is 8 scenarios.') : t('err_failed'))));
    }
  }

  Future<void> _delete() async {
    final r = await s.api('scen_delete', {'id': sc.id});
    if (mounted && r.ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: C.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(sc.id == 0 ? _tr('سيناريو جديد', 'New scenario') : _tr('تعديل السيناريو', 'Edit scenario'), style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [if (sc.id != 0) IconButton(onPressed: _delete, icon: Icon(Icons.delete_outline, color: C.danger))],
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(18, 4, 18, 28), children: [
          TextField(controller: _name, decoration: InputDecoration(labelText: _tr('الاسم', 'Name'))),
          const SizedBox(height: 12),
          _trigger(),
          _conditions(),
          _actions(_tr('إفعل', 'Do'), _tr('الإجراءات بالترتيب', 'actions in order'), sc.act),
          if (_showElse)
            _actions(_tr('وإلا', 'Otherwise'), _tr('لو الحدث حصل والشروط ما اتحققتش', 'the event happened but the conditions do not hold'), sc.els)
          else
            TextButton(onPressed: () => setState(() => _showElse = true), child: Text(_tr('+ وإلا', '+ Otherwise'))),
          const SizedBox(height: 8),
          primaryButton(_busy ? _tr('بيحفظ…', 'Saving…') : _tr('حفظ', 'Save'), _busy ? null : _save, icon: Icons.check),
        ]),
      ),
    );
  }
}
