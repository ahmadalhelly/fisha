import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme.dart';
import 'time_zone_screen.dart';
import '../widgets/common.dart';

part 'automations/editor.dart';

String _actText(int a) => a == 3 ? t('act_both') : (a == 2 ? t('act_off') : t('act_notify'));

class AutomationsScreen extends StatefulWidget {
  final AppState state;
  const AutomationsScreen({super.key, required this.state});

  @override
  State<AutomationsScreen> createState() => _AutomationsScreenState();
}

class _AutomationsScreenState extends State<AutomationsScreen> {
  AppState get s => widget.state;
  bool _loading = true;
  int _focus = 0; // the rule opened from a strip or outlet card: scrolled to and flashed once

  @override
  void initState() {
    super.initState();
    _focus = s.focusAid;
    s.focusAid = 0;
    _load();
  }

  Future<void> _load() async {
    if (s.hubV2) await s.loadAutomations();
    if (mounted) setState(() => _loading = false);
  }

  void _edit([Automation? a]) {
    if (s.allStrips.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AutomationEditor(state: s, initial: a)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final grouped = <String, List<Automation>>{};
        for (final a in s.automations) {
          grouped.putIfAbsent(a.mac, () => []).add(a);
        }
        final macs = <String>[];
        for (final st in s.allStrips) {
          if (grouped.containsKey(st.mac)) macs.add(st.mac);
        }
        for (final mac in grouped.keys) {
          if (!macs.contains(mac)) macs.add(mac);
        }

        return Scaffold(
          backgroundColor: C.bg,
          appBar: AppBar(
            backgroundColor: C.bg,
            surfaceTintColor: Colors.transparent,
            title: Text(t('auto_title'), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          floatingActionButton: s.hubV2 && s.allStrips.isNotEmpty && s.can(Perm.auto)
              ? FloatingActionButton.extended(
                  onPressed: () => _edit(),
                  backgroundColor: C.accent,
                  foregroundColor: C.onAccent,
                  icon: const Icon(Icons.add),
                  label: Text(t('auto_new'), style: const TextStyle(fontWeight: FontWeight.w700)),
                )
              : null,
          body: SafeArea(
            child: RefreshIndicator(
              color: C.accent,
              onRefresh: _load,
              child: ListView(cacheExtent: 4000, padding: const EdgeInsets.fromLTRB(18, 8, 18, 96), children: [
                if (!s.hubV2) emptyCard(t('err_old_fw')) else ...[
                  _sectionHead(Icons.public, Tr.isAr ? 'الحماية العامة' : 'General protection',
                      Tr.isAr
                          ? 'إلزامية على كل المشتركات والمخارج. لو مشترك أو مخرج ليه قاعدة خاصة تحت، هي اللي بتتطبق عليه بدالها.'
                          : 'Applies to every strip and outlet. A strip or outlet with its own rule below follows that rule instead.'),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: C.accent.withValues(alpha: 0.35)),
                      color: C.accent.withValues(alpha: 0.04),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _tempCard(),
                      if (s.hubHasStripProt) ...[const SizedBox(height: 8), _stripProtCard()],
                    ]),
                  ),
                  const SizedBox(height: 22),
                  _sectionHead(Icons.electrical_services, Tr.isAr ? 'أتمتة المشتركات والمخارج' : 'Strip and outlet rules',
                      Tr.isAr ? 'قواعد لمشترك أو مخرج معيّن. قواعد المشترك كله فوق، وقواعد كل مخرج تحتها.' : 'Rules for one strip or outlet. Whole-strip rules come first, outlet rules under them.'),
                  const SizedBox(height: 10),
                  if (_loading) Center(child: CircularProgressIndicator(color: C.accent)),
                  if (!_loading && s.automations.isEmpty) emptyCard(t('auto_empty'), icon: Icons.bolt),
                  for (final mac in macs) ...[
                    _stripGroup(mac, grouped[mac]!),
                    const SizedBox(height: 14),
                  ],
                ],
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _stripGroup(String mac, List<Automation> rules) {
    rules = [...rules.where((a) => a.outlet == 0), ...rules.where((a) => a.outlet != 0)];
    final strip = s.live(mac);
    final stripName = strip != null ? s.stripName(strip) : (Tr.isAr ? 'مشترك غير معروف' : 'Unknown strip') + (mac.length >= 4 ? ' · ${mac.substring(mac.length - 4)}' : '');
    return Container(
      decoration: cardBox(radius: 20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onLongPress: s.can(Perm.auto) ? () => _stripMenu(mac, rules, stripName) : null,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      stripName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(10)),
                    child: Text('${rules.length}', style: mono(12, color: C.muted)),
                  ),
                  const SizedBox(width: 8),
                  // all of this strip's rules on or off at once
                  Tooltip(
                    message: Tr.isAr ? 'تفعيل أو إيقاف كل قواعد المشترك' : 'All of this strip\'s rules on or off',
                    child: Switch(
                      value: rules.every((x) => x.enabled),
                      activeTrackColor: C.accent,
                      onChanged: s.can(Perm.auto) ? (v) => _setAll(rules, v) : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: C.border),
          for (var i = 0; i < rules.length; i++) ...[
            if (i > 0) Divider(height: 1, color: C.border.withValues(alpha: 0.5), indent: 70),
            FocusFlash(active: !_loading && _focus != 0 && _focus == rules[i].aid, radius: 14, child: _ruleRow(rules[i])),
          ],
        ],
      ),
    );
  }

  Widget _stripProtCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: cardBox(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.bolt, color: C.warn),
            const SizedBox(width: 10),
            Expanded(child: Text(t('vprot'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            // over-voltage is always on: no switch, just a badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: C.warn.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: C.warn.withValues(alpha: 0.4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.lock, size: 12, color: C.warn),
                const SizedBox(width: 4),
                Text(Tr.isAr ? 'إجباري' : 'Always on', style: TextStyle(color: C.warn, fontSize: 11.5, fontWeight: FontWeight.w700)),
              ]),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            Tr.isAr
                ? 'لو الفولت عدّى ${s.vMax} V، المشترك كله بيقفل فوراً حتى المخارج المحمية'
                : 'Above ${s.vMax} V the whole strip shuts off at once, protected outlets included',
            style: TextStyle(color: C.muted, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 10),
          Text(t('vprot_max'), style: TextStyle(color: C.textSoft, fontSize: 13)),
          const SizedBox(height: 8),
          ValueStepper(
            value: s.vMax.toDouble(),
            min: 220,
            max: 280,
            step: 1,
            unit: 'V',
            onChanged: (v) => s.setStripProtection(vLimit: v.round()),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(Tr.isAr ? 'أدنى فولت (اختياري)' : 'Min voltage (optional)', style: TextStyle(color: C.textSoft, fontSize: 13)),
                Text(Tr.isAr ? 'فصل المشترك لو الفولت نزل عن ${s.vMin} V' : 'Cut the strip below ${s.vMin} V',
                    style: TextStyle(color: C.muted, fontSize: 12)),
              ]),
            ),
            Switch(value: s.vProtect, activeTrackColor: C.accent, onChanged: (v) => s.setStripProtection(vOn: v)),
          ]),
          const SizedBox(height: 8),
          ValueStepper(
            value: s.vMin.toDouble(),
            min: 100,
            max: 220,
            step: 1,
            unit: 'V',
            enabled: s.vProtect,
            onChanged: (v) => s.setStripProtection(vMinLimit: v.round()),
          ),
          const SizedBox(height: 6),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: s.vRestore,
            activeTrackColor: C.accent,
            title: Text(t('vprot_restore'), style: const TextStyle(fontSize: 13)),
            onChanged: (v) => s.setStripProtection(vBack: v),
          ),
          if (s.vRestore) ...[
            Text(Tr.isAr ? 'يرجّع بعد ما الفولت يستقر لمدة' : 'Back after the voltage is steady for', style: TextStyle(color: C.textSoft, fontSize: 13)),
            const SizedBox(height: 8),
            ValueStepper(
              value: s.vBackS.toDouble(),
              min: 10,
              max: 1800,
              step: 10,
              unit: Tr.isAr ? 'ث' : 's',
              enabled: s.vProtect,
              onChanged: (v) => s.setStripProtection(vBackSeconds: v.round()),
            ),
            // the window needs room between the two limits
            if (s.vMax - s.vMin >= 4) ...[
            const SizedBox(height: 10),
            Text(Tr.isAr ? 'الفولت يعتبر مستقر لما يبقى بين' : 'Steady means between', style: TextStyle(color: C.textSoft, fontSize: 13)),
            const SizedBox(height: 8),
            // one under the other, each as wide as the page: side by side the number wrapped a digit per line
            Text(Tr.isAr ? 'من' : 'From', style: TextStyle(color: C.muted, fontSize: 12)),
            const SizedBox(height: 4),
            ValueStepper(
              value: _backLo(),
              min: s.vMin + 1.0,
              max: _backHi() - 1, // under the upper end, or the window is empty and the strips never come back
              step: 1,
              unit: 'V',
              enabled: s.vProtect,
              onChanged: (v) => s.setStripProtection(vBackLow: v.round()),
            ),
            const SizedBox(height: 10),
            Text(Tr.isAr ? 'إلى' : 'To', style: TextStyle(color: C.muted, fontSize: 12)),
            const SizedBox(height: 4),
            ValueStepper(
              value: _backHi(),
              min: _backLo() + 1,
              max: s.vMax - 1.0,
              step: 1,
              unit: 'V',
              enabled: s.vProtect,
              onChanged: (v) => s.setStripProtection(vBackHigh: v.round()),
            ),
            ],
            const SizedBox(height: 4),
            Text(
                Tr.isAr
                    ? 'ده للهاب. المشترك نفسه لو فصل على الفولت وهو بعيد عن الهاب بيرجع بعد 30 ثانية من الاستقرار.'
                    : 'This is the hub\'s. A strip that cut on voltage by itself, away from the hub, comes back 30 s after it is steady.',
                style: TextStyle(color: C.muted, fontSize: 11.5, height: 1.4)),
          ],
          Divider(height: 22, color: C.border),
          Row(children: [
            Icon(Icons.electric_meter_outlined, color: C.danger),
            const SizedBox(width: 10),
            Expanded(child: Text(t('aprot'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            Switch(value: s.aProtect, activeTrackColor: C.accent, onChanged: (v) => s.setStripProtection(aOn: v)),
          ]),
          Text(t('aprot_sub', {'x': s.aMax.toStringAsFixed(1)}), style: TextStyle(color: C.muted, fontSize: 12, height: 1.5)),
          const SizedBox(height: 10),
          Text(t('aprot_max'), style: TextStyle(color: C.textSoft, fontSize: 13)),
          const SizedBox(height: 8),
          ValueStepper(
            value: s.aMax,
            min: 0.5,
            max: 16.5,
            step: 0.5,
            decimals: 1,
            unit: 'A',
            enabled: s.aProtect,
            onChanged: (v) => s.setStripProtection(aLimit: v),
          ),
          Divider(height: 22, color: C.border),
          Row(children: [
            Icon(Icons.bolt, color: C.danger),
            const SizedBox(width: 10),
            Expanded(child: Text(Tr.isAr ? 'أقصى قدرة للمشترك (وات)' : 'Maximum strip power (watts)', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
          ]),
          Text(
              Tr.isAr
                  ? 'لو مجموع المخارج عدّى ${s.wMax} وات المشترك بيفصل. الحد محفوظ جوه المشترك كمان.'
                  : 'The strip cuts when the outlets together pass ${s.wMax} W. The limit is also stored inside the strip.',
              style: TextStyle(color: C.muted, fontSize: 12, height: 1.5)),
          const SizedBox(height: 8),
          ValueStepper(
            value: s.wMax.toDouble(),
            min: 50,
            max: 3680,
            step: 50,
            unit: 'W',
            onChanged: (v) => s.setStripProtection(wLimit: v.round()),
          ),
          Divider(height: 22, color: C.border),
          Row(children: [
            Icon(Icons.timer_outlined, color: C.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                Tr.isAr ? 'مهلة تأكيد الفصل (ثواني / قراءات متتالية)' : 'Protection trip hold time (seconds / readings)',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            Tr.isAr
                ? 'عدد الثواني/القراءات المتتالية قبل الفصل عند تجاوز الحدود (محفوظة في الـ Hub وفلاش المشترك F1.0.90)'
                : 'Consecutive seconds/readings before disconnecting on overload/voltage trip',
            style: TextStyle(color: C.muted, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 8),
          ValueStepper(
            value: s.protHoldS.toDouble(),
            min: 1,
            max: 600,
            step: 1,
            unit: 's',
            onChanged: (v) => s.setStripProtection(holdSeconds: v.round()),
          ),
          Divider(height: 22, color: C.border),
          InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TimeZoneScreen(state: s))),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Icon(Icons.public, color: C.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    Tr.isAr ? 'الوقت والمنطقة الزمنية' : 'Time and time zone',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                Icon(Icons.chevron_left, color: C.muted),
              ]),
            ),
          ),
          const SizedBox(height: 6),
        ]),
      );

  Widget _tempCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: cardBox(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.thermostat, color: C.danger),
            const SizedBox(width: 10),
            Expanded(child: Text(t('temp_prot'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            Switch(value: s.tempProtect, activeTrackColor: C.accent, onChanged: (v) => s.setTempProtection(enabled: v)),
          ]),
          Text(t('temp_prot_sub', {'x': s.tempMax}), style: TextStyle(color: C.muted, fontSize: 12, height: 1.5)),
          const SizedBox(height: 10),
          Text(t('temp_max'), style: TextStyle(color: C.textSoft, fontSize: 13)),
          const SizedBox(height: 8),
          ValueStepper(
            value: s.tempMax.toDouble(),
            min: 15,
            max: 95,
            step: 1,
            unit: '°C',
            enabled: s.tempProtect,
            onChanged: (v) => s.setTempProtection(max: v.round()),
          ),
          const SizedBox(height: 6),
        ]),
      );

  /// Long-press on a rule: edit, duplicate or delete.
  Future<void> _setAll(List<Automation> rules, bool on) async {
    for (final r in rules) {
      if (r.enabled == on) continue;
      r.enabled = on;
      await s.saveAutomation(r);
    }
  }

  /// long press on a strip: copy its rules to another strip, or delete them all
  Future<void> _stripMenu(String mac, List<Automation> rules, String stripName) async {
    final act = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: C.surface,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(stripName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          ListTile(
              leading: Icon(Icons.copy_all_outlined, color: C.accent),
              title: Text(Tr.isAr ? 'نسخ كل قواعده لمشترك تاني' : 'Copy all its rules to another strip'),
              onTap: () => Navigator.pop(ctx, 'copy')),
          ListTile(
              leading: Icon(Icons.delete_outline, color: C.danger),
              title: Text(Tr.isAr ? 'حذف كل قواعده' : 'Delete all its rules', style: TextStyle(color: C.danger)),
              onTap: () => Navigator.pop(ctx, 'del')),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (!mounted || act == null) return;
    if (act == 'del') {
      if (!await confirmDialog(context, Tr.isAr ? 'حذف قواعد $stripName' : 'Delete the rules of $stripName', Tr.isAr ? '${rules.length} قاعدة' : '${rules.length} rules', ok: t('delete'), danger: true)) return;
      for (final r in List.of(rules)) {
        await s.deleteAutomation(r.aid);
      }
      return;
    }
    final others = s.allStrips.where((x) => x.mac != mac).toList();
    if (others.isEmpty) return;
    final to = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: C.surface,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(Tr.isAr ? 'انسخ لـ…' : 'Copy to…', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          for (final st in others) ListTile(leading: Icon(Icons.power_outlined, color: C.accent), title: Text(s.stripName(st)), onTap: () => Navigator.pop(ctx, st.mac)),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (!mounted || to == null) return;
    for (final r in rules) {
      await s.saveAutomation(Automation.fromJson(r.toJson())
        ..aid = 0
        ..mac = to);
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Tr.isAr ? 'اتنسخت ${rules.length} قاعدة' : 'Copied ${rules.length} rules')));
  }

  Future<void> _ruleMenu(Automation a) async {
    final name = a.label.isNotEmpty ? a.label : s.nameForMac(a.mac, a.outlet);
    final act = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: C.surface,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          ListTile(leading: Icon(Icons.edit_outlined, color: C.accent), title: Text(Tr.isAr ? 'تعديل' : 'Edit'), onTap: () => Navigator.pop(ctx, 'edit')),
          ListTile(leading: Icon(Icons.copy_all_outlined, color: C.accent), title: Text(Tr.isAr ? 'نسخة' : 'Duplicate'), onTap: () => Navigator.pop(ctx, 'dup')),
          ListTile(
              leading: Icon(Icons.delete_outline, color: C.danger),
              title: Text(t('delete'), style: TextStyle(color: C.danger)),
              onTap: () => Navigator.pop(ctx, 'del')),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (!mounted || act == null) return;
    switch (act) {
      case 'edit':
        _edit(a);
      case 'dup':
        final copy = Automation.fromJson(a.toJson())
          ..aid = 0
          ..label = a.label.isEmpty ? '' : '${a.label} (${Tr.isAr ? 'نسخة' : 'copy'})';
        await s.saveAutomation(copy);
      case 'del':
        if (!await confirmDialog(context, t('delete'), name, ok: t('delete'), danger: true)) return;
        await s.deleteAutomation(a.aid);
    }
  }

  // the steady window after a voltage cut as shown (0 = 5 V inside the limits), the low end always under the high one
  double _backHi() => (s.vBackHi == 0 ? s.vMax - 5 : s.vBackHi).toDouble().clamp(s.vMin + 2.0, s.vMax - 1.0);
  double _backLo() => (s.vBackLo == 0 ? s.vMin + 5 : s.vBackLo).toDouble().clamp(s.vMin + 1.0, _backHi() - 1);

  Widget _sectionHead(IconData icon, String title, String sub) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: C.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 2),
              Text(sub, style: TextStyle(color: C.muted, fontSize: 12, height: 1.45)),
            ]),
          ),
        ]),
      );

  /// "whole strip" or "outlet", so the two kinds of rule read apart at a glance
  Widget _scopeChip(bool wholeStrip) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: wholeStrip ? C.accent.withValues(alpha: 0.16) : C.surface2,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(wholeStrip ? (Tr.isAr ? 'المشترك كله' : 'Whole strip') : (Tr.isAr ? 'مخرج' : 'Outlet'),
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: wholeStrip ? C.accent : C.muted)),
      );

  Widget _ruleRow(Automation a) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: s.can(Perm.auto) ? () => _edit(a) : null,
          onLongPress: s.can(Perm.auto) ? () => _ruleMenu(a) : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: C.accentBg, borderRadius: BorderRadius.circular(14)),
                child: Icon(
                    a.isBoth
                        ? Icons.shield_moon_outlined
                        : a.isVoltage
                            ? Icons.bolt_outlined
                            : (a.isTemp
                            ? Icons.thermostat
                            : (a.isCurrent
                                ? Icons.electric_meter_outlined
                                : (a.above ? Icons.trending_up : Icons.trending_down))),
                    color: a.metric > 0 ? C.warn : C.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text(a.label.isNotEmpty ? a.label : s.nameForMac(a.mac, a.outlet),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 6),
                    _scopeChip(a.outlet == 0),
                  ]),
                  const SizedBox(height: 3),
                  Text(
                    automationCondText(a),
                    style: TextStyle(fontSize: 12, color: C.textSoft),
                  ),
                  Text('${s.nameForMac(a.mac, a.outlet)} ${Tr.isAr ? '←' : '→'} ${_actText(a.act)}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: C.muted)),
                ]),
              ),
              Switch(
                value: a.enabled,
                activeTrackColor: C.accent,
                onChanged: (v) {
                  a.enabled = v;
                  s.saveAutomation(a);
                },
              ),
            ]),
          ),
        ),
      );
}
