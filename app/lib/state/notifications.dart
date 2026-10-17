part of '../app_state.dart';

/// Notifications (moved verbatim from app_state.dart; behavior unchanged).
extension AppStateNotifications on AppState {
  /// Whether [e] is one the user gets as a phone notification (type switched on, and that strip/outlet not muted).
  bool eventNotifies(HubEvent e) {
    if (e.type == 'test' || AppState.safetyTypes.contains(e.type)) return true;
    final bit = AppState.notifyBitTypes.indexOf(e.type);
    if (bit < 0 || notifyTypes & (1 << bit) == 0) return false;
    if (e.mac.isEmpty) return true;
    final st = _strips.where((x) => x.mac.toUpperCase() == e.mac);
    if (st.isEmpty) return true;
    final mask = st.first.notifyMask;
    return e.outlet == 0 ? mask & 0x10 != 0 : mask & (1 << (e.outlet - 1)) != 0;
  }

  void _saveNotifyFilter() {
    final f = jsonEncode({'types': notifyTypes, 'masks': {for (final x in _strips) x.mac: x.notifyMask}});
    if (f == _notifyFilterSaved) return;
    _notifyFilterSaved = f;
    _prefs?.setString('notifyFilter', f);
  }

  Future<bool> setNotifyConfig({String? topic, int? types}) async {
    if (topic != null) ntfyTopic = topic;
    if (types != null) notifyTypes = types;
    _saveNotifyFilter();
    _notify();
    final r = await api('notify', {if (topic != null) 'ntfy': topic, if (types != null) 'types': types});
    _fail(r);
    return r.ok;
  }

  Future<void> setNotifyMask(Strip s, int mask) async {
    final before = _strips;
    _strips = _strips.map((x) => x.mac == s.mac ? Strip(mac: x.mac, fw: x.fw, online: x.online, voltage: x.voltage, rssi: x.rssi, upS: x.upS, ip: x.ip, outlets: x.outlets, label: x.label, notifyMask: mask, hasSchedule: x.hasSchedule, hasRule: x.hasRule) : x).toList();
    _saveNotifyFilter();
    _notify();
    final r = await api('notify', {'mac': s.mac, 'mask': mask});
    if (!r.ok) _strips = before;
    _fail(r);
    _notify();
  }

  Future<bool> testNotify() async {
    final r = await api('notify', {'test': true});
    _fail(r);
    return r.ok;
  }
}
