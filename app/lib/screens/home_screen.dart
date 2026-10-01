import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/strip_card.dart';
import '../widgets/strip_mini.dart';
import 'add_strip_screen.dart';

class HomeScreen extends StatefulWidget {
  final AppState state;
  final VoidCallback onOpenSettings;
  const HomeScreen({super.key, required this.state, required this.onOpenSettings});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppState get s => widget.state;

  @override
  void initState() {
    super.initState();
    s.addListener(_onState);
  }

  @override
  void dispose() {
    s.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    final err = s.lastError;
    if (err != null && mounted) {
      s.clearError();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  void _soon(String what) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('soon', {'x': what}))));
  }

  void _addStrip() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AddStripScreen(state: s)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addStrip,
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
            final header = _header(context);
            const pad = EdgeInsets.fromLTRB(18, 16, 18, 96);

            Widget body;
            if (strips.isEmpty) {
              body = ListView(padding: pad, children: [header, const SizedBox(height: 16), _empty()]);
            } else if (s.viewMode == ViewMode.grid) {
              body = ListView(
                padding: pad,
                children: [
                  header,
                  const SizedBox(height: 16),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.92,
                    children: strips
                        .map((st) => StripMini(state: s, strip: st, onTap: () => s.setViewMode(ViewMode.list)))
                        .toList(),
                  ),
                ],
              );
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
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(Icons.drag_indicator, color: C.faint, size: 20),
                      ),
                    ),
                  ),
                ),
              );
            } else {
              body = ListView(
                padding: pad,
                children: [
                  header,
                  const SizedBox(height: 16),
                  for (final st in strips)
                    Padding(padding: const EdgeInsets.only(bottom: 14), child: StripCard(state: s, strip: st)),
                ],
              );
            }
            return RefreshIndicator(color: C.accent, onRefresh: s.refresh, child: body);
          },
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('home_kicker'), style: TextStyle(fontSize: 13, color: C.muted)),
                  Text(t('home_title'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            _modePill(),
          ],
        ),
        const SizedBox(height: 16),
        _summary(),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _quick(Icons.bar_chart, t('q_energy'), () => _soon(t('q_energy')))),
            const SizedBox(width: 8),
            Expanded(child: _quick(Icons.schedule, t('q_sched'), () => _soon(t('q_sched')))),
            const SizedBox(width: 8),
            Expanded(child: _quick(Icons.bolt, t('q_auto'), () => _soon(t('q_auto')))),
            const SizedBox(width: 8),
            Expanded(child: _quick(Icons.home_outlined, t('q_rooms'), () => _soon(t('q_rooms')))),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
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
          ],
        ),
      ],
    );
  }

  Widget _modePill() {
    final (label, color) = switch (s.mode) {
      ConnMode.local => (t('mode_local'), C.green),
      ConnMode.cloud => (t('mode_cloud'), C.blue),
      ConnMode.offline => (t('mode_offline'), C.danger),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: cardBox(radius: 999),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, color: C.textSoft)),
        ],
      ),
    );
  }

  Widget _summary() {
    final v = s.voltage;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: cardBox(),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('power_now'), style: TextStyle(fontSize: 13, color: C.muted)),
                    const SizedBox(height: 6),
                    Row(
                      textDirection: TextDirection.ltr,
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(s.totalPower.toStringAsFixed(1), style: mono(42, color: C.accent)),
                        const SizedBox(width: 6),
                        Text('W', style: mono(16, color: C.muted, weight: FontWeight.w500)),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(v == null ? '— V' : '${v.toStringAsFixed(0)} V',
                      textDirection: TextDirection.ltr, style: mono(13, color: C.textSoft, weight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  Text(s.mode == ConnMode.local ? t('refresh_2s') : t('live'),
                      style: TextStyle(fontSize: 12, color: C.muted)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _stat('${s.onlineCount}', t('stat_online'))),
              const SizedBox(width: 8),
              Expanded(child: _stat('${s.onCount}/${s.outletCount}', t('stat_on'))),
              const SizedBox(width: 8),
              Expanded(child: _stat(s.allStrips.isEmpty ? '—' : '${s.maxTemp}°C', t('stat_temp'))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, textDirection: TextDirection.ltr, style: mono(17)),
            const SizedBox(height: 2),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: C.muted)),
          ],
        ),
      );

  Widget _quick(IconData icon, String label, VoidCallback onTap) => Material(
        color: C.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: C.border)),
            child: Column(
              children: [
                Icon(icon, color: C.accent, size: 22),
                const SizedBox(height: 8),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
              ],
            ),
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
        for (final e in labels.entries)
          CheckedPopupMenuItem(value: e.key, checked: s.sortMode == e.key, child: Text(e.value)),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(body, style: TextStyle(color: C.textSoft, height: 1.6)),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: widget.onOpenSettings,
            style: OutlinedButton.styleFrom(
              foregroundColor: C.accent,
              side: BorderSide(color: C.tileOnBorder),
              minimumSize: const Size(0, 44),
            ),
            child: Text(t('settings')),
          ),
        ],
      ),
    );
  }
}

/// Shared helper for rename dialogs.
Future<String?> askName(BuildContext context, String title, String current) {
  final ctrl = TextEditingController(text: current);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: C.surface,
      title: Text(title, style: const TextStyle(fontSize: 18)),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLength: 32,
        textInputAction: TextInputAction.done,
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'), style: TextStyle(color: C.muted))),
        TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(t('save'))),
      ],
    ),
  );
}
