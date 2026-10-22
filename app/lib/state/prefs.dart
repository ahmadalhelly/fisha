part of '../app_state.dart';

/// Saved preferences, provisioning and UI prefs (moved verbatim from app_state.dart; behavior unchanged).
extension AppStatePrefs on AppState {
  void _loadPrefs() {
    final p = _prefs;
    if (p == null) return;
    final s = p.getString('settings');
    if (s != null) {
      try {
        settings = HubSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);
        // the hub address moved from .110 to .100
        if (!settings.isShared && settings.localHost == '192.168.1.110') settings.localHost = '192.168.1.100';
      } catch (_) {}
    }
    _loadHubs();
    _applyPrimaryHub();
    int idx(String k, int len) => (p.getInt(k) ?? 0).clamp(0, len - 1);
    viewMode = ViewMode.values[idx('viewMode', ViewMode.values.length)];
    sortMode = SortMode.values[idx('sortMode', SortMode.values.length)];
    themePref = ThemePref.values[idx('themePref', ThemePref.values.length)];
    langPref = LangPref.values[idx('langPref', LangPref.values.length)];
    showMac = p.getBool('showMac') ?? false;
    tariff = p.getDouble('tariff') ?? 1.0;
    otaPass = p.getString('otaPass') ?? '';
    accountType = p.getString('accountType') ?? '';
    googleEmail = p.getString('googleEmail') ?? '';
    googlePhoto = p.getString('googlePhoto') ?? '';
    syncEveryMin = p.getInt('syncEvery') ?? 0;
    syncPaused = p.getBool('syncPaused') ?? false;
    syncKeepVersions = (p.getInt('syncKeep') ?? 5).clamp(1, 10);
    final sc = p.getStringList('syncCats');
    syncCats = sc == null ? SyncParts.allIds : sc.where(SyncParts.allIds.contains).toSet();
    final ls = p.getString('lastSync');
    lastSync = ls == null ? null : DateTime.tryParse(ls);
    userName = p.getString('userName') ?? '';
    _order = p.getStringList('order') ?? [];
    final n = p.getString('names');
    if (n != null) {
      try {
        _names = Map<String, String>.from(jsonDecode(n) as Map);
      } catch (_) {}
    }
    final rm = p.getString('rooms');
    if (rm != null) {
      try {
        rooms = (jsonDecode(rm) as List).whereType<Map<String, dynamic>>().map(Room.fromJson).toList();
      } catch (_) {}
    }
  }

  // ---------- provisioning ----------
  Future<CmdResult> startProvision() async {
    if (!hubHasConfig) return CmdResult(false, t('err_old_fw'));
    final r = await api('provision');
    if (r.ok) {
      provState = 'queued';
      provMsg = '';
      _notify();
    }
    return r;
  }

  // ---------- UI prefs ----------
  Future<void> reorder(int oldIndex, int newIndex) async {
    final visible = strips.map((s) => s.mac).toList();
    if (newIndex > oldIndex) newIndex -= 1;
    final mac = visible.removeAt(oldIndex);
    visible.insert(newIndex, mac);
    final rest = _order.where((m) => !visible.contains(m)).toList();
    _order = [...visible, ...rest];
    await _prefs?.setStringList('order', _order);
    _notify();
  }

  Future<void> setViewMode(ViewMode m) async {
    viewMode = m;
    await _prefs?.setInt('viewMode', m.index);
    _notify();
  }

  Future<void> setSortMode(SortMode m) async {
    sortMode = m;
    await _prefs?.setInt('sortMode', m.index);
    _notify();
  }

  Future<void> setThemePref(ThemePref m) async {
    themePref = m;
    await _prefs?.setInt('themePref', m.index);
    _notify();
  }

  Future<void> setLangPref(LangPref m) async {
    langPref = m;
    await _prefs?.setInt('langPref', m.index);
    _notify();
  }

  Future<void> setShowMac(bool v) async {
    showMac = v;
    await _prefs?.setBool('showMac', v);
    _notify();
  }

  Future<void> setTariff(double v) async {
    tariff = v;
    await _prefs?.setDouble('tariff', v);
    _notify();
  }

  void setQuery(String q) {
    query = q;
    _notify();
  }

  void setTab(int i) {
    tab = i;
    _notify();
  }

  Future<void> setUserName(String name) async {
    userName = name.trim();
    await _prefs?.setString('userName', userName);
    _notify();
  }

  bool requiresBio(String mac, int n) => _prefs?.getBool('bio_${mac.toUpperCase()}_$n') ?? false;

  Future<void> setRequiresBio(String mac, int n, bool val) async {
    await _prefs?.setBool('bio_${mac.toUpperCase()}_$n', val);
    _notify();
  }

  Room? roomForStrip(String mac) {
    final upper = mac.toUpperCase();
    for (final r in rooms) {
      if (r.stripMacs.contains(upper)) return r;
    }
    return null;
  }

  Future<void> saveRooms() async {
    await _prefs?.setString('rooms', jsonEncode([for (final r in rooms) r.toJson()]));
    _notify();
  }

  Future<void> addRoom(String name) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    rooms.add(Room(id: id, name: name.trim()));
    await saveRooms();
  }

  Future<void> renameRoom(String id, String newName) async {
    final i = rooms.indexWhere((r) => r.id == id);
    if (i >= 0) {
      rooms[i] = rooms[i].copyWith(name: newName.trim());
      await saveRooms();
    }
  }

  Future<void> deleteRoom(String id) async {
    rooms.removeWhere((r) => r.id == id);
    await saveRooms();
  }

  Future<void> assignStripToRoom(String mac, String? roomId) async {
    final upper = mac.toUpperCase();
    for (var i = 0; i < rooms.length; i++) {
      if (rooms[i].stripMacs.contains(upper)) {
        final updated = List<String>.from(rooms[i].stripMacs)..remove(upper);
        rooms[i] = rooms[i].copyWith(stripMacs: updated);
      }
    }
    if (roomId != null && roomId.isNotEmpty) {
      final i = rooms.indexWhere((r) => r.id == roomId);
      if (i >= 0) {
        final updated = List<String>.from(rooms[i].stripMacs);
        if (!updated.contains(upper)) updated.add(upper);
        rooms[i] = rooms[i].copyWith(stripMacs: updated);
      }
    }
    await saveRooms();
  }

  Future<void> setRoomIcon(String id, String icon) async {
    final i = rooms.indexWhere((r) => r.id == id);
    if (i >= 0) {
      rooms[i] = rooms[i].copyWith(icon: icon);
      await saveRooms();
      _notify();
    }
  }

  String outletIcon(String mac, int n) => _prefs?.getString('outlet_icon_${mac.toUpperCase()}_$n') ?? '';

  Future<void> setOutletIcon(String mac, int n, String icon) async {
    await _prefs?.setString('outlet_icon_${mac.toUpperCase()}_$n', icon);
    _notify();
  }

  String stripIcon(String mac) => _prefs?.getString('strip_icon_${mac.toUpperCase()}') ?? '';

  Future<void> setStripIcon(String mac, String icon) async {
    await _prefs?.setString('strip_icon_${mac.toUpperCase()}', icon);
    _notify();
  }

  void updateWidgetThrottled() {
    if (kIsWeb) return; // the home-screen widget is Android-only
    final now = DateTime.now();
    if (_lastWidgetUpdate != null && now.difference(_lastWidgetUpdate!) < const Duration(seconds: 15)) {
      if (_widgetThrottleTimer == null || !_widgetThrottleTimer!.isActive) {
        final remaining = const Duration(seconds: 15) - now.difference(_lastWidgetUpdate!);
        _widgetThrottleTimer = Timer(remaining, _updateWidget);
      }
      return;
    }
    _updateWidget();
  }

  String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  Future<void> _updateWidget() async {
    _widgetThrottleTimer?.cancel();
    _lastWidgetUpdate = DateTime.now();
    try {
      _wHist.add(totalPower);
      if (_wHist.length > 48) _wHist.removeAt(0);
      if (mode != ConnMode.offline && _strips.isNotEmpty && (_wEnergyAt == null || DateTime.now().difference(_wEnergyAt!) > const Duration(minutes: 10))) {
        _wEnergyAt = DateTime.now();
        try {
          final en = await loadEnergy();
          _wTodayKwh = en.fold<double>(0, (a, e) => a + e.todayWh.fold<int>(0, (x, y) => x + y) / 1000);
        } catch (_) {}
      }
      final ar = Tr.isAr;
      const hues = [162.0, 222.0, 36.0, 300.0, 100.0, 0.0];
      final strips = <Map<String, dynamic>>[];
      for (var i = 0; i < _strips.length; i++) {
        final st = _strips[i];
        final h = hues[i % hues.length];
        strips.add({
          'mac': st.mac,
          'name': stripName(st),
          'on': st.online,
          'w': st.livePower.round(),
          't': st.maxTemp,
          'c': _hex(HSLColor.fromAHSL(1, h, .85, .6).toColor()),
          ...stripWidgetJson(this, st),
        });
      }
      final conn = switch (mode) {
        ConnMode.local => t('mode_local'),
        ConnMode.cloud => t('mode_cloud'),
        ConnMode.offline => t('mode_offline'),
      };
      final j = {
        'ar': ar,
        'mode': conn,
        'total': totalPower.round(),
        'hot': maxTemp,
        'hist': [for (final v in _wHist) v.round()],
        'kwh': _wTodayKwh,
        'cost': _wTodayKwh * tariff,
        'on': '$onCount/$outletCount',
        'strips': strips,
        'url': mode == ConnMode.local && settings.hasLocal ? _localUri('/api/onoff').toString() : '',
        'hdr': _localHeaders,
        'l_now': ar ? 'الاستهلاك دلوقتي' : 'Power now',
        'l_today': ar ? 'النهارده' : 'Today',
        'l_cost': ar ? 'تكلفة' : 'Cost',
        'l_run': ar ? 'شغال' : 'On',
        'l_total': ar ? 'الإجمالي' : 'Total',
        'l_none': ar ? 'افتح فيشة وسجّل الدخول' : 'Open Fisha and sign in',
        't_lock': ar ? 'ده محتاج تأكيد، افتح التطبيق' : 'This needs a confirmation, open the app',
        't_away': ar ? 'التحكم من الويدجت على شبكة البيت بس' : 'Widget control works on the home network only',
        't_fail': ar ? 'الأمر ماوصلش' : 'The command did not go through',
      };
      await HomeWidget.saveWidgetData<String>('widget_json', jsonEncode(j));
      await HomeWidget.updateWidget(
        name: 'FishaWidgetProvider',
        androidName: 'FishaWidgetProvider',
        qualifiedAndroidName: 'com.mttlhub.mttl_hub.FishaWidgetProvider',
      );
    } catch (_) {}
  }
}
