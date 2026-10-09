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
    'timer' => t('ev_timer', {'x': m == 'on' ? t('turn_on') : t('turn_off')}),
    'cycle' => t('ev_cycle', {'x': m}),
    'lock' => t('ev_lock'),
    'added' => t('ev_added'),
    'button' => t(m == 'on' ? 'ev_button_on' : 'ev_button_off'),
    'remote' => t(m == 'on' ? 'ev_remote_on' : 'ev_remote_off'),
    'online' => t('ev_online'),
    'offline' => t('ev_offline'),
    'voltage' => t('ev_voltage', {'x': m}),
    'overvolt' => t('ev_overvolt', {'x': m}),
    'overcurrent' => t('ev_overcurrent', {'x': m}),
    'test' => t('ev_test'),
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
      'voltage' || 'overvolt' => Icons.electric_bolt,
      'overcurrent' => Icons.electric_meter_outlined,
      _ => Icons.info_outline,
    };

class EventsScreen extends StatefulWidget {
  final AppState state;
  const EventsScreen({super.key, required this.state});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  AppState get s => widget.state;

  @override
  void initState() {
    super.initState();
    s.loadEvents();
    WidgetsBinding.instance.addPostFrameCallback((_) => s.markEventsRead());
  }

  String _time(int ts) {
    if (ts <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    return '${two(d.day)}/${two(d.month)}  ${fmtTime12(d.hour, d.minute)}';
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
          builder: (context, _) => RefreshIndicator(
            color: C.accent,
            onRefresh: s.loadEvents,
            child: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 24), children: [
              if (!s.hubV2) emptyCard(t('err_old_fw')),
              if (s.hubV2 && s.events.isEmpty) emptyCard(t('events_empty'), icon: Icons.notifications_none),
              for (final e in s.events)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: cardBox(radius: 16),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(_icon(e.type), color: e.type == 'temp' || e.type == 'load' ? C.danger : C.accent, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(eventText(s, e), style: const TextStyle(height: 1.4)),
                        if (e.ts > 0) ...[
                          const SizedBox(height: 4),
                          Text(_time(e.ts), style: mono(11, color: C.muted, weight: FontWeight.w500)),
                        ],
                      ]),
                    ),
                  ]),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
