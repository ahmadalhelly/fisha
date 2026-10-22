part of '../app_state.dart';

/// Hub settings, restart and password push (moved verbatim from app_state.dart; behavior unchanged).
extension AppStateSettingsLink on AppState {
  void _stopAll() {
    _gen++;
    _pollTimer?.cancel();
    _pollTimer = null;
    _mqttRetry?.cancel();
    _sseRunning = false;
    _sseClient?.close();
    _sseClient = null;
    sseLive = false;
    _stopMqtt();
  }

  Future<void> saveSettings(HubSettings s) async {
    final passChanged = s.hubPass != settings.hubPass;
    settings = s;
    await _prefs?.setString('settings', jsonEncode(s.toJson()));
    _syncActiveHub();
    if (passChanged) _passPushedValue = '';
    await restart();
  }

  /// Hands the hub its server password (home Wi-Fi only). The hub keeps it and reconnects only if it changed.
  Future<CmdResult> pushHubPass({bool force = false}) async {
    final p = settings.hubPass;
    if (p.isEmpty || settings.isShared) return CmdResult(false, t('cloud_need_pass'));
    if (!_localFresh) return CmdResult(false, t('err_local_only'));
    if (!force && _passPushedValue == p && _passPushedAt != null && DateTime.now().difference(_passPushedAt!) < const Duration(minutes: 2)) {
      return const CmdResult(true);
    }
    _passPushedAt = DateTime.now();
    _passPushedValue = p;
    return api('cloud', {'pass': p, 'host': settings.brokerHost, 'user': 'ESP_hub'});
  }

  /// Owner only: the hub's address on the home network. The hub restarts to use it.
  Future<CmdResult> pushHubLocalIp(String ip) async {
    if (settings.isShared || !_localFresh) return CmdResult(false, t('err_local_only'));
    return api('cloud', {'lip': ip});
  }

  bool get hubSupportsCloudCfg => hubCloudUp != null;

  Future<void> restart() async {
    _stopAll();
    _strips = [];
    timers = [];
    _lastLocalOk = null;
    mode = ConnMode.offline;
    hubOnline = false;
    hubCloudUp = null;
    hubCloudErr = '';
    _notify();
    final gen = _gen;
    // https web page: the hub's plain-http LAN API is blocked as mixed content, so cloud only
    if (kLocalCapable && settings.hasLocal) {
      _pollLocal();
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (!sseLive) _pollLocal();
        _updateMode();
      });
      _runSse(gen);
    }
    if (settings.hasCloud) _startMqtt();
    Future.delayed(const Duration(seconds: 3), () {
      if (gen == _gen) loadEvents();
    });
  }
}
