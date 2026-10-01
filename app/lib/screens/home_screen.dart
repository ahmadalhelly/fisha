import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/strip_card.dart';
import '../widgets/strip_mini.dart';
import 'add_strip_screen.dart';
import 'automations_screen.dart';
import 'events_screen.dart';

class HomeScreen extends StatefulWidget {
  final AppState state;
  const HomeScreen({super.key, required this.state});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppState get s => widget.state;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {}); // "updated Xs ago"
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _push(AddStripScreen(state: s)),
        backgroundColor: C.accent,
        foregroundColor: C.onAccent,
        icon: const Icon(Icons.add),
        label: Text(t('add_strip'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: s,
          builder: (context, _) {
            final strips = s.strips;
            final header = _header();
            const pad = EdgeInsets.fromLTRB(18, 16, 18, 96);
            Widget body;
            if (strips.isEmpty) {
              body = ListView(padding: pad, children: [header, const SizedBox(height: 16), _empty()]);
            } else if (s.viewMode == ViewMode.grid) {
              body = ListView(padding: pad, children: [
                header,
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.92,
                  children: strips.map((st) => StripMini(state: s, strip: st, onTap: () => s.setViewMode(ViewMode.list))).toList(),
                ),
              ]);
            } else if (s.sortMode == SortMode.manual && s.query.trim().isEmpty) {
              body = ReorderableListView.builder(
                padding: pad,
                header: Padding(padding: const EdgeInsets.only(bottom: 16), child: header),
                buildDefaultDragHandles: false,
                itemCount: strips.length,
                onReorder: s.reorder,
                itemBuilder: (context, i) => Padding(
                  key: ValueKey(strips[i].mac),
                  padding: const EdgeInsets.only(bottom: 14),
                  child: StripCard(
                    state: s,
                    strip: strips[i],
                    dragHandle: ReorderableDragStartListener(
                      index: i,
                      child: Padding(padding: const EdgeInsets.all(6), child: Icon(Icons.drag_indicator, color: C.faint, size: 20)),
                    ),
                  ),
                ),
              );
            } else {
              body = ListView(padding: pad, children: [
                header,
                const SizedBox(height: 16),
                for (final st in strips) Padding(padding: const EdgeInsets.only(bottom: 14), child: StripCard(state: s, strip: st)),
              ]);
            }
            return RefreshIndicator(color: C.accent, onRefresh: s.refresh, child: body);
          },
        ),
      ),
    );
  }

  Widget _header() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const BrandMark(size: 40),
        const SizedBox(width: 6),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('app_name'), style: TextStyle(fontSize: 13, color: C.accent, fontWeight: FontWeight.w700)),
            Text(t('home_title'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          ]),
        ),
        _modePill(),
      ]),
      const SizedBox(height: 16),
      _summary(),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: _quick(Icons.bar_chart, t('q_energy'), () => s.setTab(2))),
        const SizedBox(width: 8),
        Expanded(child: _quick(Icons.schedule, t('q_sched'), () => s.setTab(1))),
        const SizedBox(width: 8),
        Expanded(child: _quick(Icons.bolt, t('q_auto'), () => _push(AutomationsScreen(state: s)))),
        const SizedBox(width: 8),
        Expanded(child: _quick(Icons.notifications_none, t('q_events'), () => _push(EventsScreen(state: s)), badge: s.unread)),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
          child: SizedBox(
            height: 44,
            child: TextField(
              onChanged: s.setQuery,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: t('search_hint'),
                prefixIcon: Icon(Icons.search, color: C.muted, size: 20),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _viewToggle(),
        const SizedBox(width: 8),
        _sortButton(),
      ]),
    ]);
  }

  Widget _modePill() {
    final (label, color) = switch (s.mode) {
      ConnMode.local => (t('mode_local'), C.green),
      ConnMode.cloud => (t('mode_cloud'), C.blue),
      ConnMode.offline => (t('mode_offline'), C.danger),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: cardBox(radius: 999),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        PulseDot(color: color, active: s.mode != ConnMode.offline),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: C.textSoft)),
      ]),
    );
  }

  Widget _summary() {
    final v = s.voltage;
    final ago = s.lastUpdate == null ? null : DateTime.now().difference(s.lastUpdate!).inSeconds;
    final fresh = ago != null && ago < 8;
    final level = (s.totalPower / 1500).clamp(0.0, 1.0);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: cardBox(),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 4),
          child: Column(children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t('power_now'), style: TextStyle(fontSize: 13, color: C.muted)),
                  const SizedBox(height: 6),
                  Row(
                    textDirection: TextDirection.ltr,
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      AnimatedNumber(value: s.totalPower, style: mono(42, color: C.accent)),
                      const SizedBox(width: 6),
                      Text('W', style: mono(16, color: C.muted, weight: FontWeight.w500)),
                    ],
                  ),
                ],
                ),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(v == null ? '— V' : '${v.toStringAsFixed(0)} V',
                    textDirection: TextDirection.ltr, style: mono(13, color: C.textSoft, weight: FontWeight.w500)),
                const SizedBox(height: 8),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  PulseDot(color: fresh ? C.green : C.faint, active: fresh),
                  const SizedBox(width: 2),
                  Text(
                    ago == null ? '—' : (ago < 3 ? t('live_now') : t('updated_ago', {'s': ago})),
                    style: TextStyle(fontSize: 12, color: C.muted),
                  ),
                ]),
              ]),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: _stat('${s.onlineCount}', t('stat_online'))),
              const SizedBox(width: 8),
              Expanded(child: _stat('${s.onCount}/${s.outletCount}', t('stat_on'))),
              const SizedBox(width: 8),
              Expanded(child: _stat(s.allStrips.isEmpty ? '—' : '${s.maxTemp}°C', t('stat_temp'))),
            ]),
          ]),
        ),
        LiveWave(level: s.mode == ConnMode.offline ? 0 : 0.15 + level * 0.85, color: C.accent),
      ]),
    );
  }

  Widget _stat(String value, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, textDirection: TextDirection.ltr, style: mono(17)),
          const SizedBox(height: 2),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: C.muted)),
        ]),
      );

  Widget _quick(IconData icon, String label, VoidCallback onTap, {int badge = 0}) => Material(
        color: C.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: C.border)),
            child: Column(children: [
              Badge(
                isLabelVisible: badge > 0,
                label: Text('$badge'),
                backgroundColor: C.danger,
                child: Icon(icon, color: C.accent, size: 22),
              ),
              const SizedBox(height: 8),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
            ]),
          ),
        ),
      );

  Widget _viewToggle() {
    Widget btn(ViewMode m, IconData icon, String tip) {
      final sel = s.viewMode == m;
      return Tooltip(
        message: tip,
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: () => s.setViewMode(m),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: sel ? C.accentBg : Colors.transparent, borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, size: 18, color: sel ? C.accent : C.muted),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: cardBox(radius: 14),
      child: Row(children: [
        btn(ViewMode.list, Icons.view_agenda_outlined, t('view_list')),
        btn(ViewMode.grid, Icons.grid_view, t('view_grid')),
      ]),
    );
  }

  Widget _sortButton() {
    final labels = {
      SortMode.manual: t('sort_manual'),
      SortMode.power: t('sort_power'),
      SortMode.name: t('sort_name'),
      SortMode.status: t('sort_status'),
    };
    return PopupMenuButton<SortMode>(
      tooltip: t('sort'),
      color: C.surface2,
      onSelected: s.setSortMode,
      itemBuilder: (_) => [
        for (final e in labels.entries) CheckedPopupMenuItem(value: e.key, checked: s.sortMode == e.key, child: Text(e.value)),
      ],
      child: Container(
        width: 44,
        height: 44,
        decoration: cardBox(radius: 14),
        child: Icon(Icons.swap_vert, color: C.textSoft, size: 20),
      ),
    );
  }

  Widget _empty() {
    final st = s.settings;
    final String title;
    final String body;
    if (!st.hasLocal && !st.hasCloud) {
      title = t('empty_nocfg_t');
      body = t('empty_nocfg_b');
    } else if (s.mode == ConnMode.offline) {
      title = t('empty_off_t');
      body = st.hasCloud ? t('empty_off_cloud') : t('empty_off_local');
    } else if (s.query.isNotEmpty) {
      title = t('empty_noq_t');
      body = t('empty_noq_b');
    } else {
      title = t('empty_none_t');
      body = t('empty_none_b');
    }
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: cardBox(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(body, style: TextStyle(color: C.textSoft, height: 1.6)),
        const SizedBox(height: 14),
        OutlinedButton(
          onPressed: () => s.setTab(3),
          style: OutlinedButton.styleFrom(
            foregroundColor: C.accent,
            side: BorderSide(color: C.tileOnBorder),
            minimumSize: const Size(0, 44),
          ),
          child: Text(t('settings')),
        ),
      ]),
    );
  }
}
