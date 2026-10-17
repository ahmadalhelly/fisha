part of '../app_state.dart';

/// Google account: optional sign-in + settings sync (moved verbatim from app_state.dart; behavior unchanged).
extension AppStateAccountSync on AppState {
  Future<void> setSyncEvery(int m) async {
    syncEveryMin = m;
    await _prefs?.setInt('syncEvery', m);
    _notify();
  }

  Future<void> setSyncPaused(bool v) async {
    syncPaused = v;
    await _prefs?.setBool('syncPaused', v);
    if (!v) _startAutoSync();
    _notify();
  }

  Future<void> setSyncKeepVersions(int n) async {
    syncKeepVersions = n.clamp(1, 10);
    await _prefs?.setInt('syncKeep', syncKeepVersions);
    _notify();
  }

  /// Every saved copy on Drive, newest first; throws on a Drive error.
  Future<List<SyncVersion>> listGoogleVersions() => GoogleSync.I.listVersions();

  Future<Map<String, dynamic>> _syncPayload() async {
    // 2.0.18: the copy of the hub's data (rules, schedules, names, protection, family) is refreshed first, so the
    // upload carries everything as it is now, not as it was at the last 15-minute refresh
    if (!settings.isShared && mode != ConnMode.offline && _hubNvs.isNotEmpty) await _refreshMirror();
    final b = await exportBackup(parts: {'app'}, withSecrets: true);
    final app = b['app'];
    if (app is Map) app.removeWhere((k, _) => AppState._noSyncKeys.contains(k));
    return b;
  }

  String _googleErr(Object e, [String fallback = 'g_sync_failed']) {
    if (e is GoogleSyncError) {
      switch (e.code) {
        case 'not_configured':
          return t('g_err_not_configured');
        case 'network':
          return t('g_err_network');
        case 'drive_disabled':
          return t('g_err_drive_disabled');
        case 'auth':
          return t('g_err_auth');
      }
      return '${t(fallback)} (${e.detail})';
    }
    return t(fallback);
  }

  /// null = signed in; otherwise a message for the user.
  /// Auto-sync starts only after the first restore or upload, so it can never overwrite the Google copy
  /// while the user is still deciding whether to restore it.
  Future<String?> googleSignIn() async {
    try {
      final e = await GoogleSync.I.signIn();
      if (e == null) return t('g_cancelled');
      await setAccount('google', email: e);
      googlePhoto = GoogleSync.I.photoUrl ?? '';
      await _prefs?.setString('googlePhoto', googlePhoto);
      if (userName.isEmpty) {
        final dn = GoogleSync.I.displayName;
        await setUserName(dn != null && dn.trim().isNotEmpty ? dn : e.split('@').first);
      }
      return null;
    } catch (e) {
      return _googleErr(e, 'g_failed');
    }
  }

  /// true / false, or null when Google could not be checked (then nothing must be uploaded).
  Future<bool?> googleHasData() async {
    try {
      return await GoogleSync.I.download() != null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> syncNow() async {
    try {
      final b = await _syncPayload();
      await GoogleSync.I.upload(b, keep: syncKeepVersions);
      _lastSyncSig = jsonEncode(b['app']);
      await markSynced();
      if (_syncTimer == null) _startAutoSync();
      return null;
    } catch (e) {
      return _googleErr(e);
    }
  }

  /// Restores a specific saved copy ([id]), or the newest one when [id] is null.
  Future<String?> restoreFromGoogle([String? id]) async {
    try {
      final b = await GoogleSync.I.download(id);
      if (b == null) return t('g_no_data');
      final app = b['app'];
      if (app is Map) app.removeWhere((k, _) => AppState._noSyncKeys.contains(k));
      final r = await importBackup(b, parts: {'app'});
      _lastSyncSig = jsonEncode(b['app']);
      await markSynced();
      if (_syncTimer == null) _startAutoSync();
      return r;
    } catch (e) {
      return _googleErr(e);
    }
  }

  Future<void> useLocalAccount() async {
    _syncTimer?.cancel();
    _syncTimer = null;
    if (accountType == 'google') {
      try {
        await GoogleSync.I.signOut();
      } catch (_) {}
    }
    await setAccount('local');
  }

  /// Leaves the account (Google or local) and goes back to the welcome screen. Data on this phone stays.
  Future<void> logout() async {
    _syncTimer?.cancel();
    _syncTimer = null;
    if (accountType == 'google') {
      await _autoSync();
      try {
        await GoogleSync.I.signOut();
      } catch (_) {}
    }
    // 2.0.18: signing out leaves nothing behind: no hub key, no family login, no strips on screen
    _strips = [];
    timers = [];
    ownerPhones = [];
    pairRequests = [];
    await saveSettings(HubSettings());
    await setAccount('');
  }

  void _startAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(minutes: 10), (_) => _autoSync());
  }

  Future<void> _autoSync() async {
    if (accountType != 'google' || syncPaused) return;
    if (syncEveryMin > 0 && lastSync != null && DateTime.now().difference(lastSync!) < Duration(minutes: syncEveryMin)) return;
    try {
      final b = await _syncPayload();
      final sig = jsonEncode(b['app']);
      if (sig == _lastSyncSig) return;
      await GoogleSync.I.upload(b, keep: syncKeepVersions);
      _lastSyncSig = sig;
      await markSynced();
    } catch (_) {}
  }
}
