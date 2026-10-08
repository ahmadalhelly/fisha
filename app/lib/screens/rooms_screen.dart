import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/notion_icon_picker.dart';
import '../widgets/strip_card.dart';
import 'backup_screen.dart';

String _tr(String ar, String en) => Tr.isAr ? ar : en;

class RoomsScreen extends StatefulWidget {
  final AppState state;
  const RoomsScreen({super.key, required this.state});

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  AppState get s => widget.state;

  Future<void> _addRoom() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        title: Text(_tr('غرفة جديدة', 'New Room'), style: const TextStyle(fontSize: 18)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: _tr('مثلاً: الصالة، المطبخ، المكتب', 'e.g. Living room, Kitchen')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'), style: TextStyle(color: C.muted))),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(t('save'))),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await s.addRoom(name);
    }
  }

  Future<void> _renameRoom(Room room) async {
    final ctrl = TextEditingController(text: room.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        title: Text(_tr('تغيير اسم الغرفة', 'Rename Room'), style: const TextStyle(fontSize: 18)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: _tr('اسم الغرفة', 'Room name')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'), style: TextStyle(color: C.muted))),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(t('save'))),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await s.renameRoom(room.id, name);
    }
  }

  Future<void> _deleteRoom(Room room) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        title: Text(_tr('حذف الغرفة؟', 'Delete Room?'), style: const TextStyle(fontSize: 18)),
        content: Text(_tr('المشتركات اللي فيها هترجع بدون غرفة.', 'Strips in this room will become unassigned.'), style: TextStyle(color: C.textSoft)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'), style: TextStyle(color: C.muted))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('delete'), style: TextStyle(color: C.danger))),
        ],
      ),
    );
    if (ok == true) {
      await s.deleteRoom(room.id);
    }
  }

  Future<void> _manageStrips(Room room) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListenableBuilder(
        listenable: s,
        builder: (ctx, _) {
          final all = s.allStrips;
          final currentRoom = s.rooms.firstWhere((r) => r.id == room.id, orElse: () => room);
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
              children: [
                Text(
                  _tr('مشتركات ${currentRoom.name}', 'Strips in ${currentRoom.name}'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                if (all.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_tr('مفيش مشتركات متصلة', 'No strips connected'), style: TextStyle(color: C.muted)),
                  ),
                for (final st in all)
                  CheckboxListTile(
                    value: currentRoom.stripMacs.contains(st.mac),
                    activeColor: C.accent,
                    checkColor: C.onAccent,
                    title: Text(s.stripName(st), style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      st.online ? '${st.onCount}/${st.outlets.length} ${t('on_word')}' : t('offline'),
                      style: TextStyle(color: C.muted, fontSize: 12),
                    ),
                    onChanged: (checked) {
                      if (checked == true) {
                        s.assignStripToRoom(st.mac, currentRoom.id);
                      } else {
                        s.assignStripToRoom(st.mac, null);
                      }
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final rooms = s.rooms;
        final allAssigned = rooms.expand((r) => r.stripMacs).toSet();
        final unassigned = s.allStrips.where((st) => !allAssigned.contains(st.mac)).toList();

        return Scaffold(
          backgroundColor: C.bg,
          appBar: AppBar(
            backgroundColor: C.bg,
            surfaceTintColor: Colors.transparent,
            title: Text(_tr('الغرف', 'Rooms'), style: const TextStyle(fontWeight: FontWeight.w700)),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_backup_restore),
                tooltip: t('backup_title'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BackupScreen(state: s))),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _addRoom,
            backgroundColor: C.accent,
            foregroundColor: C.onAccent,
            icon: const Icon(Icons.add),
            label: Text(_tr('غرفة جديدة', 'New Room'), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 96),
              children: [
                if (rooms.isEmpty)
                  emptyCard(
                    _tr(
                      'مفيش غرف لسه. ضيف غرف (زي الصالة، المطبخ، أو أوضة النوم) عشان ترتّب المشتركات جواها.',
                      'No rooms yet. Add rooms to group and organize your strips.',
                    ),
                    icon: Icons.meeting_room_outlined,
                  )
                else ...[
                  for (final room in rooms) ...[
                    _roomCard(room),
                    const SizedBox(height: 12),
                  ],
                ],
                if (unassigned.isNotEmpty && rooms.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(_tr('مشتركات بدون غرفة', 'Unassigned Strips'), style: TextStyle(color: C.muted, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Container(
                    decoration: cardBox(),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final st in unassigned)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(s.stripName(st), style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(st.mac, textDirection: TextDirection.ltr, style: mono(11, color: C.faint)),
                            trailing: TextButton.icon(
                              icon: const Icon(Icons.add, size: 16),
                              label: Text(_tr('تعيين', 'Assign')),
                              style: TextButton.styleFrom(foregroundColor: C.accent),
                              onPressed: () => _pickRoomForStrip(st.mac),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickRoomForStrip(String mac) async {
    final room = await showDialog<Room>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        title: Text(_tr('اختيار الغرفة', 'Pick Room'), style: const TextStyle(fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final r in s.rooms)
              ListTile(
                title: Text(r.name),
                onTap: () => Navigator.pop(ctx, r),
              ),
          ],
        ),
      ),
    );
    if (room != null) {
      await s.assignStripToRoom(mac, room.id);
    }
  }

  Future<void> _pickRoomIcon(Room room) async {
    await showNotionIconPicker(
      context: context,
      currentIcon: room.icon,
      onSelected: (ico) => s.setRoomIcon(room.id, ico),
      title: _tr('اختر أيقونة الغرفة', 'Choose Room Icon'),
    );
  }

  Widget _roomCard(Room room) {
    final roomStrips = s.allStrips.where((st) => room.stripMacs.contains(st.mac)).toList();
    final roomW = roomStrips.fold<double>(0.0, (sum, st) => sum + (st.online ? st.livePower : 0));

    return Container(
      decoration: cardBox(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _pickRoomIcon(room),
              child: Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: C.accentBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: FishaIcon(
                  icon: room.icon,
                  defaultIcon: Icons.meeting_room,
                  size: 22,
                  color: C.accent,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(room.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    _tr('${roomStrips.length} مشترك', '${roomStrips.length} strips'),
                    style: TextStyle(color: C.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            Row(
              textDirection: TextDirection.ltr,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                AnimatedNumber(value: roomW, style: mono(18, color: loadColor(roomW, (roomStrips.isEmpty ? 1 : roomStrips.length) * kStripMaxW))),
                const SizedBox(width: 3),
                Text('W', style: mono(11, color: C.muted, weight: FontWeight.w500)),
              ],
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: C.muted),
              color: C.surface2,
              onSelected: (action) {
                if (action == 'icon') _pickRoomIcon(room);
                if (action == 'rename') _renameRoom(room);
                if (action == 'manage') _manageStrips(room);
                if (action == 'delete') _deleteRoom(room);
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(value: 'icon', child: Text(_tr('اختيار أيقونة', 'Choose icon'))),
                PopupMenuItem(value: 'manage', child: Text(_tr('تحديد المشتركات', 'Manage strips'))),
                PopupMenuItem(value: 'rename', child: Text(_tr('تغيير الاسم', 'Rename'))),
                PopupMenuItem(value: 'delete', child: Text(_tr('حذف', 'Delete'), style: TextStyle(color: C.danger))),
              ],
            ),
          ]),
          if (roomStrips.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final st in roomStrips)
                  Chip(
                    backgroundColor: C.surface2,
                    side: BorderSide(color: C.border),
                    avatar: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: st.online ? C.green : C.faint),
                    ),
                    label: Text(s.stripName(st), style: const TextStyle(fontSize: 12)),
                    deleteIcon: const Icon(Icons.close, size: 14),
                    onDeleted: () => s.assignStripToRoom(st.mac, null),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.tune, size: 16),
            label: Text(_tr('تعديل المشتركات', 'Edit strips')),
            style: OutlinedButton.styleFrom(
              foregroundColor: C.textSoft,
              side: BorderSide(color: C.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => _manageStrips(room),
          ),
        ],
      ),
    );
  }
}
