import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/strip_card.dart';
import '../widgets/strip_mini.dart';
import 'add_strip_screen.dart';
import 'automations_screen.dart';
import 'events_screen.dart';
import 'rooms_screen.dart';
import 'scenes_screen.dart';

class HomeScreen extends StatefulWidget {
  final AppState state;
  const HomeScreen({super.key, required this.state});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppState get s => widget.state;
  Timer? _tick;
  final _scroll = ScrollController();
  final Set<String> _collapsedRooms = {};
  bool _compact = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final c = _scroll.hasClients && _scroll.offset > 230;
      if (c != _compact) setState(() => _compact = c);
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {}); // "updated Xs ago"
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: SizedBox(
          height: 44,
          child: FloatingActionButton.extended(
            onPressed: () => _push(AddStripScreen(state: s)),
            elevation: 4,
            backgroundColor: C.accent,
            foregroundColor: C.onAccent,
            icon: const Icon(Icons.add, size: 20),
            label: Text(t('add_strip'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: s,
          builder: (context, _) {
            final strips = s.strips;
            final header = _header();
            const pad = EdgeInsets.fromLTRB(18, 12, 18, 96);
            Widget body;
            if (strips.isEmpty) {
              body = ListView(controller: _scroll, padding: pad, children: [header, const SizedBox(height: 10), _empty()]);
            } else if (s.rooms.isNotEmpty) {
              body = ListView(controller: _scroll, padding: pad, children: [
                header,
                const SizedBox(height: 10),
                ..._buildRoomSections(strips),
              ]);
            } else if (s.viewMode == ViewMode.grid) {
              body = ListView(controller: _scroll, padding: pad, children: [
                header,
                const SizedBox(height: 10),
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
                scrollController: _scroll,
                padding: pad,
                header: Padding(padding: const EdgeInsets.only(bottom: 10), child: header),
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
              body = ListView(controller: _scroll, padding: pad, children: [
                header,
                const SizedBox(height: 10),
                for (final st in strips) Padding(padding: const EdgeInsets.only(bottom: 14), child: StripCard(state: s, strip: st)),
              ]);
            }
            return Stack(children: [
              RefreshIndicator(color: C.accent, onRefresh: s.refresh, child: body),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  ignoring: !_compact,
                  child: AnimatedSlide(
                    offset: _compact ? Offset.zero : const Offset(0, -1.2),
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    child: AnimatedOpacity(opacity: _compact ? 1 : 0, duration: const Duration(milliseconds: 200), child: _compactBar()),
                  ),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }

  Widget _header() {
    final String kicker;
    if (s.userName.isNotEmpty) {
      final hour = DateTime.now().hour;
      if (Tr.isAr) {
        kicker = hour < 12 ? 'صباح الخير، ${s.userName} 👋' : 'مساء الخير، ${s.userName} 👋';
      } else {
        kicker = hour < 12 ? 'Good morning, ${s.userName} 👋' : 'Good evening, ${s.userName} 👋';
      }
    } else {
      kicker = t('app_name');
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const BrandMark(size: 32),
        const SizedBox(width: 6),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(kicker, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: C.accent, fontWeight: FontWeight.w700)),
            Text(t('home_title'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          ]),
        ),
        _modePill(),
        const SizedBox(width: 6),
        IconButton(
          tooltip: t('q_events'),
          visualDensity: VisualDensity.compact,
          onPressed: () => _push(EventsScreen(state: s)),
          icon: Badge(
            isLabelVisible: s.unread > 0,
            label: Text('${s.unread}'),
            backgroundColor: C.danger,
            child: Icon(Icons.notifications_outlined, size: 22, color: C.textSoft),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      _summary(),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _quick(Icons.auto_awesome, Tr.isAr ? 'السيناريوهات' : 'Scenarios', () => _push(ScenesScreen(state: s)))),
        const SizedBox(width: 8),
        Expanded(child: _quick(Icons.schedule, t('q_sched'), () => s.setTab(1))),
        const SizedBox(width: 8),
        Expanded(child: _quick(Icons.bolt, t('q_auto'), () => _push(AutomationsScreen(state: s)))),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: SizedBox(
            height: 38,
            child: TextField(
              onChanged: s.setQuery,
              style: const TextStyle(fontSize: 13),
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
        const SizedBox(width: 4),
        IconButton(
          tooltip: Tr.isAr ? 'الغرف' : 'Rooms',
          icon: Icon(Icons.meeting_room_outlined, color: C.muted, size: 20),
          visualDensity: VisualDensity.compact,
          onPressed: () => _push(RoomsScreen(state: s)),
        ),
      ]),
    ]);
  }

  /// The summary shrinks into this bar and stays on top while scrolling.
  Widget _compactBar() {
    final (modeColor, modeLabel) = switch (s.mode) {
      ConnMode.local => (C.green, t('mode_local')),
      ConnMode.cloud => (C.blue, t('mode_cloud')),
      ConnMode.offline => (C.danger, t('mode_offline')),
    };
    final cap = (s.onlineCount == 0 ? 1 : s.onlineCount) * kStripMaxW;
    Widget chip(IconData icon, String text, {Color? color}) => Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: color ?? C.muted),
          const SizedBox(width: 3),
          Text(text, textDirection: TextDirection.ltr, style: mono(12.5, color: color ?? C.textSoft, weight: FontWeight.w600)),
        ]);
    return GestureDetector(
      onTap: () => _scroll.animateTo(0, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic),
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 6, 10, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: C.surface.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: C.border),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: C.dark ? 0.35 : 0.12), blurRadius: 18, offset: const Offset(0, 6))],
        ),
        child: Row(children: [
          const BrandMark(size: 24),
          const SizedBox(width: 6),
          Row(textDirection: TextDirection.ltr, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            AnimatedNumber(value: s.totalPower, style: mono(19, color: loadColor(s.totalPower, cap))),
            const SizedBox(width: 2),
            Text('W', style: mono(11, color: C.muted, weight: FontWeight.w500)),
          ]),
          const Spacer(),
          chip(Icons.power_outlined, '${s.onCount}/${s.outletCount}'),
          const SizedBox(width: 10),
          chip(Icons.thermostat, s.allStrips.isEmpty ? '—' : '${s.maxTemp}°C', color: s.allStrips.isEmpty ? null : tempColor(s.maxTemp)),
          const SizedBox(width: 10),
          Tooltip(message: modeLabel, child: PulseDot(color: modeColor, active: s.mode != ConnMode.offline)),
        ]),
      ),
    );
  }

  Widget _modePill() {
    final (label, color) = switch (s.mode) {
      ConnMode.local => (t('mode_local'), C.green),
      ConnMode.cloud => (t('mode_cloud'), C.blue),
      ConnMode.offline => (t('mode_offline'), C.danger),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: cardBox(radius: 999),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        PulseDot(color: color, active: s.mode != ConnMode.offline),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 10, color: C.textSoft)),
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
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Column(children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t('power_now'), style: TextStyle(fontSize: 11, color: C.muted)),
                  const SizedBox(height: 4),
                  Row(
                    textDirection: TextDirection.ltr,
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      AnimatedNumber(value: s.totalPower, style: mono(34, color: loadColor(s.totalPower, (s.onlineCount == 0 ? 1 : s.onlineCount) * kStripMaxW))),
                      const SizedBox(width: 4),
                      Text('W', style: mono(13, color: C.muted, weight: FontWeight.w500)),
                    ],
                  ),
                ],
                ),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(v == null ? '— V' : '${v.toStringAsFixed(0)} V',
                    textDirection: TextDirection.ltr, style: mono(11, color: C.textSoft, weight: FontWeight.w500)),
                const SizedBox(height: 6),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  PulseDot(color: fresh ? C.green : C.faint, active: fresh),
                  const SizedBox(width: 2),
                  Text(
                    ago == null ? '—' : (ago < 3 ? t('live_now') : t('updated_ago', {'s': ago})),
                    style: TextStyle(fontSize: 10, color: C.muted),
                  ),
                ]),
              ]),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _stat('${s.onlineCount}', t('stat_online'))),
              const SizedBox(width: 8),
              Expanded(child: _stat('${s.onCount}/${s.outletCount}', t('stat_on'))),
              const SizedBox(width: 8),
              Expanded(child: _stat(s.allStrips.isEmpty ? '—' : '${s.maxTemp}°C', t('stat_temp'), color: s.allStrips.isEmpty ? null : tempColor(s.maxTemp))),
            ]),
          ]),
        ),
        LiveWave(level: s.mode == ConnMode.offline ? 0 : 0.15 + level * 0.85, color: C.accent),
      ]),
    );
  }

  Widget _stat(String value, String label, {Color? color}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, textDirection: TextDirection.ltr, style: mono(14, color: color)),
          const SizedBox(height: 2),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: C.muted)),
        ]),
      );

  Widget _quick(IconData icon, String label, VoidCallback onTap, {int badge = 0}) => Material(
        color: C.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: C.border)),
            child: Column(children: [
              Badge(
                isLabelVisible: badge > 0,
                label: Text('$badge'),
                backgroundColor: C.danger,
                child: Icon(icon, color: C.accent, size: 22),
              ),
              const SizedBox(height: 6),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
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

  List<Widget> _buildRoomSections(List<Strip> strips) {
    final widgets = <Widget>[];
    final allAssigned = s.rooms.expand((r) => r.stripMacs).toSet();

    for (final room in s.rooms) {
      final rStrips = strips.where((st) => room.stripMacs.contains(st.mac)).toList();
      if (rStrips.isEmpty && s.query.trim().isNotEmpty) continue;
      final roomW = rStrips.fold<double>(0.0, (sum, st) => sum + (st.online ? st.livePower : 0));
      final isCollapsed = _collapsedRooms.contains(room.id);

      widgets.add(_roomHeader(room.name, roomW, rStrips.length, isCollapsed, () {
        setState(() {
          if (isCollapsed) {
            _collapsedRooms.remove(room.id);
          } else {
            _collapsedRooms.add(room.id);
          }
        });
      }));
      if (!isCollapsed) {
        widgets.add(const SizedBox(height: 10));
        if (s.viewMode == ViewMode.grid) {
          widgets.add(
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.92,
              children: rStrips.map((st) => StripMini(state: s, strip: st, onTap: () => s.setViewMode(ViewMode.list))).toList(),
            ),
          );
        } else {
          for (final st in rStrips) {
            widgets.add(Padding(padding: const EdgeInsets.only(bottom: 14), child: StripCard(state: s, strip: st)));
          }
        }
      }
      widgets.add(const SizedBox(height: 14));
    }

    final unassigned = strips.where((st) => !allAssigned.contains(st.mac)).toList();
    if (unassigned.isNotEmpty) {
      final isCollapsed = _collapsedRooms.contains('__unassigned__');
      final unassignedW = unassigned.fold<double>(0.0, (sum, st) => sum + (st.online ? st.livePower : 0));

      widgets.add(_roomHeader(Tr.isAr ? 'بدون غرفة' : 'Unassigned', unassignedW, unassigned.length, isCollapsed, () {
        setState(() {
          if (isCollapsed) {
            _collapsedRooms.remove('__unassigned__');
          } else {
            _collapsedRooms.add('__unassigned__');
          }
        });
      }));
      if (!isCollapsed) {
        widgets.add(const SizedBox(height: 10));
        if (s.viewMode == ViewMode.grid) {
          widgets.add(
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.92,
              children: unassigned.map((st) => StripMini(state: s, strip: st, onTap: () => s.setViewMode(ViewMode.list))).toList(),
            ),
          );
        } else {
          for (final st in unassigned) {
            widgets.add(Padding(padding: const EdgeInsets.only(bottom: 14), child: StripCard(state: s, strip: st)));
          }
        }
      }
    }

    return widgets;
  }

  Widget _roomHeader(String name, double totalW, int count, bool isCollapsed, VoidCallback onToggle) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: C.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: C.border),
        ),
        child: Row(children: [
          Icon(isCollapsed ? Icons.chevron_right : Icons.expand_more, size: 20, color: C.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Row(children: [
              Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(8)),
                child: Text('$count', style: mono(11, color: C.muted, weight: FontWeight.w600)),
              ),
            ]),
          ),
          Row(
            textDirection: TextDirection.ltr,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              AnimatedNumber(value: totalW, style: mono(15, color: loadColor(totalW, (count == 0 ? 1 : count) * kStripMaxW))),
              const SizedBox(width: 2),
              Text('W', style: mono(11, color: C.muted, weight: FontWeight.w500)),
            ],
          ),
        ]),
      ),
    );
  }
}
