part of '../app_state.dart';

/// One hub this phone knows: its name, the settings used to reach it (address, key, cloud login) and whether it is the one
/// the app opens on.
class HubProfile {
  String name;
  Map<String, dynamic> settings;
  bool primary;
  HubProfile(this.name, this.settings, {this.primary = false});

  String get hubId => (settings['hubId'] ?? '').toString().toUpperCase();

  Map<String, dynamic> toJson() => {'name': name, 'settings': settings, 'primary': primary};
  factory HubProfile.fromJson(Map<String, dynamic> j) => HubProfile((j['name'] ?? '').toString(), Map<String, dynamic>.from(j['settings'] as Map), primary: j['primary'] == true);
}

/// Several hubs on one account: each keeps its own settings; the app talks to one at a time (the active one) and
/// switching saves the chosen hub's settings as the current ones.
extension AppStateHubs on AppState {
  void _loadHubs() {
    final raw = _prefs?.getString('hubs');
    hubs = [];
    if (raw != null) {
      try {
        hubs = [for (final j in jsonDecode(raw) as List) HubProfile.fromJson(Map<String, dynamic>.from(j as Map))];
      } catch (_) {}
    }
    // the hub this phone already talks to becomes the first entry
    if (hubs.isEmpty && _hubConfigured) {
      hubs = [HubProfile(Tr.isAr ? 'البيت' : 'Home', settings.toJson(), primary: true)];
    }
  }

  /// a real hub is set up here (not the placeholder id of a fresh install)
  bool get _hubConfigured => settings.hubId.isNotEmpty && settings.hubId.toUpperCase() != '80F3DA40F674';

  Future<void> _saveHubs() async => _prefs?.setString('hubs', jsonEncode([for (final h in hubs) h.toJson()]));

  /// the entry of the hub in use now (matched by its id)
  int get activeHubIndex => hubs.indexWhere((h) => h.hubId == settings.hubId.toUpperCase());

  /// keeps the entry of the hub in use in step with the current settings; a hub that is new here gets an entry
  void _syncActiveHub() {
    if (settings.hubId.isEmpty) return;
    final i = activeHubIndex;
    if (i >= 0) {
      hubs[i].settings = settings.toJson();
    } else if (_hubConfigured) {
      final n = hubs.length + 1;
      hubs.add(HubProfile(Tr.isAr ? 'هاب $n' : 'Hub $n', settings.toJson(), primary: hubs.isEmpty));
    } else {
      return;
    }
    _saveHubs();
  }

  /// the app opens on the primary hub
  void _applyPrimaryHub() {
    final p = hubs.indexWhere((h) => h.primary);
    if (p >= 0 && hubs[p].hubId != settings.hubId.toUpperCase()) settings = HubSettings.fromJson(hubs[p].settings);
  }

  Future<void> switchHub(int i) async {
    if (i < 0 || i >= hubs.length || i == activeHubIndex) return;
    await saveSettings(HubSettings.fromJson(hubs[i].settings));
  }

  Future<void> renameHub(int i, String name) async {
    if (i < 0 || i >= hubs.length || name.trim().isEmpty) return;
    hubs[i].name = name.trim();
    await _saveHubs();
    _notify();
  }

  Future<void> setPrimaryHub(int i) async {
    for (var k = 0; k < hubs.length; k++) {
      hubs[k].primary = k == i;
    }
    await _saveHubs();
    _notify();
  }

  /// removes the hub from this phone only; what is stored on the hub stays
  Future<void> removeHub(int i) async {
    if (i < 0 || i >= hubs.length) return;
    final wasActive = i == activeHubIndex;
    final wasPrimary = hubs[i].primary;
    hubs.removeAt(i);
    if (wasPrimary && hubs.isNotEmpty) hubs.first.primary = true;
    await _saveHubs();
    if (wasActive && hubs.isNotEmpty) {
      await saveSettings(HubSettings.fromJson(hubs.first.settings));
    } else {
      _notify();
    }
  }

  String get activeHubName {
    final i = activeHubIndex;
    return i >= 0 ? hubs[i].name : '';
  }
}
