import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../services/hub_setup.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/hub_setup_sheet.dart';

String _tr(String ar, String en) => Tr.isAr ? ar : en;

/// Settings ← Hubs: every hub this phone knows, with its name, which one the app opens on (the star) and the hub in use.
class HubsScreen extends StatelessWidget {
  final AppState state;
  const HubsScreen({super.key, required this.state});

  Future<void> _rename(BuildContext context, int i) async {
    final c = TextEditingController(text: state.hubs[i].name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        title: Text(_tr('اسم الهاب', 'Hub name')),
        content: TextField(controller: c, autofocus: true, maxLength: 24),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'), style: TextStyle(color: C.muted))),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(_tr('تمام', 'OK'), style: TextStyle(color: C.accent, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    c.dispose();
    if (name != null) await state.renameHub(i, name);
  }

  Future<void> _remove(BuildContext context, int i) async {
    final ok = await confirmDialog(
        context,
        _tr('إزالة ${state.hubs[i].name}؟', 'Remove ${state.hubs[i].name}?'),
        _tr('بتتشال من التطبيق ده بس. اللي جوه الهاب والمشتركات بيفضل شغال.', 'It is removed from this phone only. What is stored on the hub and the strips keeps working.'));
    if (ok) await state.removeHub(i);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final active = state.activeHubIndex;
        return Scaffold(
          backgroundColor: C.bg,
          appBar: AppBar(
            backgroundColor: C.bg,
            surfaceTintColor: Colors.transparent,
            title: Text(_tr('الهابات', 'Hubs'), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          body: SafeArea(
            child: ListView(padding: const EdgeInsets.fromLTRB(18, 4, 18, 90), children: [
              Text(_tr('الهاب الأساسي (النجمة) هو اللي بيفتح أول ما تفتح التطبيق. دوسة على أي هاب تبدّل ليه.', 'The primary hub (the star) is the one the app opens on. Tap a hub to switch to it.'),
                  style: TextStyle(color: C.muted, fontSize: 12.5, height: 1.5)),
              const SizedBox(height: 12),
              if (state.hubs.isEmpty) emptyCard(_tr('مفيش هابات لسه. ضيف أول هاب.', 'No hubs yet. Add the first one.'), icon: Icons.router_outlined),
              for (var i = 0; i < state.hubs.length; i++)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: cardBox(radius: 18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    InkWell(
                      onTap: () => state.switchHub(i),
                      child: Row(children: [
                        Icon(Icons.router_outlined, color: i == active ? C.accent : C.muted),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(state.hubs[i].name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                            Text(
                              i == active
                                  ? (state.mode == ConnMode.local ? _tr('متصل محلي', 'Connected locally') : state.mode == ConnMode.cloud ? _tr('عن طريق السحابة', 'Through the cloud') : _tr('فاصل', 'Offline'))
                                  : _tr('دوس للتبديل', 'Tap to switch'),
                              style: TextStyle(color: i == active ? C.accent : C.muted, fontSize: 12),
                            ),
                          ]),
                        ),
                        IconButton(
                          onPressed: () => state.setPrimaryHub(i),
                          icon: Icon(state.hubs[i].primary ? Icons.star : Icons.star_border, color: state.hubs[i].primary ? C.warn : C.muted),
                          tooltip: _tr('خليه أساسي', 'Make primary'),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: OutlinedButton.icon(onPressed: () => _rename(context, i), icon: const Icon(Icons.edit_outlined, size: 18), label: Text(_tr('تغيير الاسم', 'Rename')))),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _remove(context, i),
                          icon: Icon(Icons.delete_outline, size: 18, color: C.danger),
                          label: Text(_tr('إزالة', 'Remove'), style: TextStyle(color: C.danger)),
                        ),
                      ),
                    ]),
                  ]),
                ),
            ]),
          ),
          floatingActionButton: HubSetup.supported
              ? FloatingActionButton.extended(
                  backgroundColor: C.accent,
                  foregroundColor: C.onAccent,
                  onPressed: () => showHubSetup(context, state),
                  icon: const Icon(Icons.add),
                  label: Text(_tr('إضافة هاب', 'Add a hub')),
                )
              : null,
        );
      },
    );
  }
}

/// the sheet opened from the hub chip on Home: switch to another hub, or manage them
void showHubSwitcher(BuildContext context, AppState state) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: C.surface,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < state.hubs.length; i++)
          ListTile(
            leading: Icon(Icons.router_outlined, color: i == state.activeHubIndex ? C.accent : C.muted),
            title: Row(children: [
              Flexible(child: Text(state.hubs[i].name, overflow: TextOverflow.ellipsis)),
              if (state.hubs[i].primary) ...[const SizedBox(width: 6), Icon(Icons.star, size: 16, color: C.warn)],
            ]),
            trailing: i == state.activeHubIndex ? Icon(Icons.check, color: C.accent) : null,
            onTap: () {
              Navigator.pop(ctx);
              state.switchHub(i);
            },
          ),
        ListTile(
          leading: Icon(Icons.settings_outlined, color: C.muted),
          title: Text(_tr('إدارة الهابات', 'Manage hubs')),
          onTap: () {
            Navigator.pop(ctx);
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => HubsScreen(state: state)));
          },
        ),
      ]),
    ),
  );
}
