import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

String eventText(AppState s, HubEvent e) {
  final who = e.mac.isEmpty ? '' : s.nameForMac(e.mac, e.outlet);
  final m = e.msg;
  final body = switch (e.type) {
    'temp' => t('ev_temp', {'x': m}),
    'load' => t('ev_load', {'x': m}),
    'auto_off' => t('ev_auto_off', {'x': m}),
    'automation' => t('ev_automation', {'x': m}),
    'schedule' => t('ev_schedule', {'x': m}),
    'missed' => t('ev_missed', {'x': m}),
    'skipped' => t('ev_skipped', {'x': m}),
    'timer' => t('ev_timer', {'x': m == 'on' ? t('turn_on') : t('turn_off')}),
    'cycle' => t('ev_cycle', {'x': m}),
    'lock' => t('ev_lock'),
    'added' => t('ev_added'),
    'button' => t(m == 'on' ? 'ev_button_on' : 'ev_button_off'),
    'remote' => t(m == 'on' ? 'ev_remote_on' : 'ev_remote_off'),
    'online' => t('ev_online'),
    'offline' => m == 'socket stuck' ? t('ev_offline_stuck') : (m == 'stale' ? t('ev_offline_stale') : t('ev_offline')),
    'wifi' => t('ev_wifi', {'x': m}),
    'voltage' => t('ev_voltage', {'x': m}),
    'overvolt' => t('ev_overvolt', {'x': m}),
    'overcurrent' => t('ev_overcurrent', {'x': m}),
    'test' => t('ev_test'),
    'stall' => t('ev_stall', {'x': m}),
    'save_fail' => t('ev_save_fail', {'x': m}),
    'strip_fw' => t('ev_strip_fw', {'x': m}),
    'strip_fw_fail' => t('ev_strip_fw_fail', {'x': m}),
    _ => '${e.type} $m',
  };
  return who.isEmpty ? body.trim() : '$who — ${body.trim()}';
}

IconData _icon(String type) => switch (type) {
      'temp' => Icons.thermostat,
      'load' => Icons.warning_amber,
      'auto_off' || 'timer' => Icons.hourglass_bottom,
      'automation' => Icons.bolt,
      'schedule' => Icons.schedule,
      'missed' => Icons.report_gmailerrorred,
      'cycle' => Icons.restart_alt,
      'lock' => Icons.lock_outline,
      'added' => Icons.add_circle_outline,
      'button' => Icons.touch_app_outlined,
      'remote' => Icons.phone_android,
      'online' => Icons.wifi,
      'offline' => Icons.wifi_off,
      'wifi' => Icons.router_outlined,
      'voltage' || 'overvolt' => Icons.electric_bolt,
      'overcurrent' => Icons.electric_meter_outlined,
      'stall' => Icons.hourglass_empty,
      'save_fail' => Icons.sd_card_alert_outlined,
      'strip_fw' => Icons.system_update_alt,
      'strip_fw_fail' => Icons.error_outline,
      _ => Icons.info_outline,
    };

String _tr(String ar, String en) => Tr.isAr ? ar : en;

/// One colour per kind of event, used for the icon chip.
Color _tone(String type) => switch (type) {
      'temp' || 'load' || 'overvolt' || 'undervolt' || 'overcurrent' || 'offline' || 'save_fail' || 'strip_fw_fail' || 'missed' => C.danger,
      'voltage' || 'warn' || 'stall' || 'wifi' || 'skipped' => C.warn,
      'schedule' || 'timer' || 'auto_off' || 'cycle' || 'strip_fw' => C.blue,
      _ => C.accent,
    };

/// System-log filter of a hub event: wifi / hub / fw
String _sysGroup(String type) => switch (type) {
      'wifi' => 'wifi',
      'strip_fw' || 'strip_fw_fail' => 'fw',
      _ => 'hub',
    };

/// 2.0.11. Two lists with clear, non-overlapping rules:
///  • "My notifications": the types that have a switch in notification settings, only when switched on and the
///    strip/outlet is not muted (the same set that reaches the phone).
///  • "System log": the hub's own events that have no switch (Wi-Fi drops, stalls, failed saves, firmware updates,
///    protection trips, skipped runs).
/// A switchable type that is turned off shows nowhere.
class EventsScreen extends StatefulWidget {
  final AppState state;
  const EventsScreen({super.key, required this.state});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  AppState get s => widget.state;
  bool _system = false; // "My notifications" is the default tab
  String _filter = 'all';
  late int _newCount; // how many of the newest "mine" events were unread when the screen opened

  @override
  void initState() {
    super.initState();
    _newCount = s.unread;
    s.loadEvents();
    WidgetsBinding.instance.addPostFrameCallback((_) => s.markEventsRead());
  }

  List<HubEvent> get _mine => s.events.where(s.eventNotifies).toList();
  List<HubEvent> get _sys => [
        for (final e in s.events)
          if (AppState.isSystemEvent(e.type) && (_filter == 'all' || _sysGroup(e.type) == _filter)) e
      ];

  int _dayKey(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    return d.year * 10000 + d.month * 100 + d.day;
  }

  String _dayLabel(int k) {
    final now = DateTime.now();
    final y = DateTime(now.year, now.month, now.day - 1);
    if (k == now.year * 10000 + now.month * 100 + now.day) return _tr('اليوم', 'Today');
    if (k == y.year * 10000 + y.month * 100 + y.day) return _tr('أمس', 'Yesterday');
    final d = k % 100, m = (k ~/ 100) % 100, yr = k ~/ 10000;
    return yr == now.year ? '$d/$m' : '$d/$m/$yr';
  }

  String _time(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    return fmtTime12(d.hour, d.minute);
  }

  Widget _dayHeader(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
        child: Text(label, style: TextStyle(color: C.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
      );

  Widget _card(HubEvent e, bool unread) {
    final tone = _tone(e.type);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      decoration: cardBox(radius: 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: tone.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(11)),
          child: Icon(_icon(e.type), color: tone, size: 19),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(eventText(s, e), style: const TextStyle(height: 1.45, fontSize: 14))),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (e.ts > 0) Text(_time(e.ts), style: mono(11, color: C.muted, weight: FontWeight.w500)),
          if (unread) ...[
            const SizedBox(height: 8),
            Container(width: 7, height: 7, decoration: BoxDecoration(color: C.accent, shape: BoxShape.circle)),
          ],
        ]),
      ]),
    );
  }

  Widget _row(HubEvent e) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: C.border.withValues(alpha: 0.55)))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: Icon(_icon(e.type), color: _tone(e.type), size: 17)),
          const SizedBox(width: 10),
          Expanded(child: Text(eventText(s, e), style: TextStyle(height: 1.4, fontSize: 13, color: C.textSoft))),
          const SizedBox(width: 10),
          if (e.ts > 0) Text(_time(e.ts), style: mono(10.5, color: C.muted, weight: FontWeight.w500)),
        ]),
      );

  Widget _chip(String key, String label) {
    final on = _filter == key;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => setState(() => _filter = key),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            color: on ? C.accentBg : C.surface2,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: on ? Colors.transparent : C.border),
          ),
          child: Text(label, style: TextStyle(fontSize: 12, color: on ? C.accent : C.textSoft, fontWeight: on ? FontWeight.w600 : FontWeight.w500)),
        ),
      ),
    );
  }

  List<Widget> _grouped(List<HubEvent> list, Widget Function(HubEvent e, int i) item, {bool boxed = false}) {
    final out = <Widget>[];
    int? day;
    var group = <Widget>[];
    void flush() {
      if (group.isEmpty) return;
      out.add(boxed ? Container(padding: const EdgeInsets.symmetric(horizontal: 14), decoration: cardBox(radius: 16), child: Column(children: group)) : Column(children: group));
      group = <Widget>[];
    }

    for (var i = 0; i < list.length; i++) {
      final e = list[i];
      final k = e.ts > 0 ? _dayKey(e.ts) : 0;
      if (k != day) {
        flush();
        day = k;
        out.add(_dayHeader(k == 0 ? _tr('بدون وقت', 'No time') : _dayLabel(k)));
      }
      group.add(item(e, i));
    }
    flush();
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: C.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(t('events_title'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: s,
          builder: (context, _) {
            final mine = _mine;
            final sys = _sys;
            return RefreshIndicator(
              color: C.accent,
              onRefresh: s.loadEvents,
              child: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 24), children: [
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                        value: false,
                        label: Text(_newCount > 0 ? '${t('events_mine')} · $_newCount' : t('events_mine')),
                        icon: const Icon(Icons.notifications_outlined)),
                    ButtonSegment(value: true, label: Text(t('events_system')), icon: const Icon(Icons.list_alt)),
                  ],
                  selected: {_system},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => setState(() => _system = v.first),
                ),
                const SizedBox(height: 4),
                if (!s.hubV2) ...[const SizedBox(height: 8), emptyCard(t('err_old_fw'))],
                if (_system && s.hubV2) ...[
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      _chip('all', _tr('الكل', 'All')),
                      _chip('wifi', _tr('الواي فاي', 'Wi-Fi')),
                      _chip('hub', _tr('الـ Hub', 'Hub')),
                      _chip('fw', _tr('الفيرموير', 'Firmware')),
                    ]),
                  ),
                  if (sys.isEmpty) ...[const SizedBox(height: 12), emptyCard(t('events_empty'), icon: Icons.notifications_none)],
                  ..._grouped(sys, (e, _) => _row(e), boxed: true),
                ],
                if (!_system && s.hubV2) ...[
                  if (mine.isEmpty) ...[const SizedBox(height: 8), emptyCard(t('events_mine_empty'), icon: Icons.notifications_none)],
                  ..._grouped(mine, (e, i) => _card(e, i < _newCount)),
                ],
              ]),
            );
          },
        ),
      ),
    );
  }
}
