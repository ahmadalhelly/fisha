part of '../app_state.dart';

/// Backup export / import (moved verbatim from app_state.dart; behavior unchanged).
extension AppStateBackup on AppState {
  Future<Map<String, dynamic>> exportBackup({Set<String> parts = const {'app', 'hub'}, bool withSecrets = false}) async {
    final out = <String, dynamic>{
      'fisha_backup': 1,
      'created': DateTime.now().toIso8601String(),
      'app_version': AppState.appVersion,
    };

    if (parts.contains('app')) {
      final appMap = <String, dynamic>{};
      final p = _prefs ?? await SharedPreferences.getInstance();
      _prefs = p;
      for (final k in p.getKeys()) {
        if (k == 'pendingOps' || k == 'notifyFilter') continue;      // this phone's queue / cache, not a setting
        final v = p.get(k);
        if (v is bool) {
          appMap[k] = {'t': 'b', 'v': v};
        } else if (v is int) {
          appMap[k] = {'t': 'i', 'v': v};
        } else if (v is double) {
          appMap[k] = {'t': 'd', 'v': v};
        } else if (v is List) {
          appMap[k] = {'t': 'l', 'v': v.map((e) => e.toString()).toList()};
        } else if (v is String) {
          appMap[k] = {'t': 's', 'v': v};
        }
      }
      if (!withSecrets) {
        appMap.removeWhere((k, _) => AppState._secretPrefs.contains(k));
        final st = appMap['settings'];
        if (st is Map && st['v'] is String) {
          try {
            final m = Map<String, dynamic>.from(jsonDecode(st['v'] as String) as Map)
              ..removeWhere((k, _) => AppState._secretSettings.contains(k));
            appMap['settings'] = {'t': 's', 'v': jsonEncode(m)};
          } catch (_) {
            appMap.remove('settings');
          }
        }
      }
      out['app'] = appMap;
    }

    if (parts.contains('hub') && mode != ConnMode.offline) {
      await loadSchedules();
      await loadAutomations();
      final users = settings.isShared ? null : await _exportUsers();
      out['hub'] = <String, dynamic>{
        if (users != null) 'users': users,
        'schedules': [for (final s in schedules) if (s.sid > 0) s.toJson()],
        'automations': [for (final a in automations) if (a.aid > 0) a.toJson()],
        'strips': [
          for (final s in allStrips)
            {
              'mac': s.mac,
              'label': s.label,
              'notify': s.notifyMask,
              'notifyMask': s.notifyMask,
              'outlets': [
                for (final o in s.outlets)
                  {
                    'n': o.n,
                    'label': o.label,
                    'locked': o.locked,
                    'protected': o.protected,
                    'autooff': o.autoOffMin,
                    'auto_off_min': o.autoOffMin,
                    'keep_on': o.keepOn,
                    'keepOn': o.keepOn,
                    'amp_limit': o.ampLimit,
                  }
              ],
            }
        ],
        // 2.0.23: the daily energy history travels with every backup / Google sync (compact rows yyyymmdd:wh1:wh2:wh3:wh4:peak)
        'energy': await _exportEnergy(),
        'config': {
          'temp_max': tempMax,
          'temp_protect': tempProtect,
          if (hubHasStripProt) ...{
            'v_protect': vProtect,
            'v_restore': vRestore,
            'v_max': vMax,
            'v_min': vMin,
            'a_protect': aProtect,
            'a_max': aMax,
            'hold_s': protHoldS,
            'tz_min': tzOffsetMin,
          },
          'ntfy': ntfyTopic,
          'notifyTypes': notifyTypes,
        },
      };
    }

    return out;
  }

  Future<Map<String, String>> _exportEnergy() async {
    final out = <String, String>{};
    for (final s in allStrips) {
      // 2.0.25: the history lives on the hub, so an offline strip's days are exported too
      final r = await api('energy', {'mac': s.mac});
      final days = r.data?['days'];
      if (!r.ok || days is! List) continue;
      final rows = <String>[];
      for (final d in days) {
        if (d is! Map) continue;
        final wh = d['wh'];
        if (wh is! List || wh.length < 4) continue;
        rows.add('${d['date']}:${wh[0]}:${wh[1]}:${wh[2]}:${wh[3]}:${(d['peak_w'] as num?)?.toInt().clamp(0, 65535) ?? 0}');
      }
      if (rows.isNotEmpty) out[s.mac] = rows.join(';');
    }
    return out;
  }

  Future<String?> importBackup(Map<String, dynamic> j, {Set<String> parts = const {'app', 'hub'}, bool replace = false}) async {
    if (j['fisha_backup'] != 1) return t('backup_err_invalid');

    int skipped = 0;
    if (parts.contains('hub') && j['hub'] is Map<String, dynamic>) {
      if (mode == ConnMode.offline) return t('err_no_conn');
      final hubData = j['hub'] as Map<String, dynamic>;

      // schedules
      if (hubData['schedules'] is List) {
        if (replace) {
          await loadSchedules();
          for (final s in schedules) {
            await api('schedule_delete', {'sid': s.sid});
          }
        }
        for (final raw in hubData['schedules']) {
          if (raw is Map) {
            final m = Map<String, dynamic>.from(raw)..remove('sid');
            await api('schedule_save', m);
          }
        }
      }

      // automations
      if (hubData['automations'] is List) {
        if (replace) {
          await loadAutomations();
          for (final a in automations) {
            await api('automation_delete', {'aid': a.aid});
          }
        }
        for (final raw in hubData['automations']) {
          if (raw is Map) {
            final m = Map<String, dynamic>.from(raw)..remove('aid');
            await api('automation_save', m);
          }
        }
      }

      // family members (hub 2.15+), with their own passwords so their phones keep working
      if (hubData['users'] is List && !settings.isShared) {
        for (final raw in hubData['users']) {
          if (raw is! Map || (raw['pw'] ?? '').toString().isEmpty) continue;
          final st = raw['strips'];
          await api('user_restore', {
            'id': raw['id'],
            'name': raw['name'],
            'role': raw['role'],
            'perms': raw['perms'] ?? 0,
            'all': raw['all'] == true,
            'strips': st is List ? st.join(',') : (st ?? '').toString(),
            'pw': raw['pw'],
          });
        }
      }

      // strips
      final currentMacs = allStrips.map((s) => s.mac.toUpperCase()).toSet();
      // energy history (hub 2.15.27+): days the hub already has are never overwritten
      final en = hubData['energy'];
      if (en is Map && !settings.isShared) {
        for (final e in en.entries) {
          if (e.value is String && (e.value as String).isNotEmpty) await api('energy_restore', {'mac': e.key.toString(), 'd': e.value});
        }
      }

      if (hubData['strips'] is List) {
        for (final raw in hubData['strips']) {
          if (raw is! Map) continue;
          final mac = (raw['mac'] ?? '').toString().toUpperCase();
          if (mac.isEmpty || !currentMacs.contains(mac)) {
            skipped++;
            continue;
          }
          final label = (raw['label'] ?? '').toString();
          if (label.isNotEmpty) {
            await api('label', {'mac': mac, 'outlet': 0, 'label': label});
          }
          final mask = raw['notifyMask'] ?? raw['notify'];
          if (mask is num) {
            await api('notify', {'mac': mac, 'mask': mask.toInt()});
          }
          final outlets = raw['outlets'];
          if (outlets is List) {
            for (final o in outlets) {
              if (o is! Map) continue;
              final n = (o['n'] as num?)?.toInt() ?? 0;
              if (n <= 0) continue;
              final oLabel = (o['label'] ?? '').toString();
              if (oLabel.isNotEmpty) {
                await api('label', {'mac': mac, 'outlet': n, 'label': oLabel});
              }
              if (o.containsKey('locked')) {
                await api('lock', {'mac': mac, 'outlet': n, 'locked': o['locked'] == true});
              }
              if (o.containsKey('protected')) {
                await api('protect', {'mac': mac, 'outlet': n, 'protected': o['protected'] == true});
              }
              if (o.containsKey('keep_on') || o.containsKey('keepOn')) {
                final keep = (o['keep_on'] ?? o['keepOn']) == true;
                await api('keepon', {'mac': mac, 'outlet': n, 'on': keep});
              }
              if (o['amp_limit'] is num) {
                await api('amplimit', {'mac': mac, 'outlet': n, 'max_a': (o['amp_limit'] as num).toDouble()});
              }
              if (o.containsKey('autooff') || o.containsKey('auto_off_min') || o.containsKey('autoOffMin')) {
                final min = num.tryParse('${o['autooff'] ?? o['auto_off_min'] ?? o['autoOffMin'] ?? 0}')?.toInt() ?? 0;
                await api('autooff', {'mac': mac, 'outlet': n, 'minutes': min});
              }
            }
          }
        }
      }

      // config & notify
      final cfg = hubData['config'] is Map ? hubData['config'] as Map : hubData;
      final tempMax = (cfg['temp_max'] as num?)?.toInt();
      final tempProtect = cfg['temp_protect'] is bool ? cfg['temp_protect'] as bool : null;
      if (tempMax != null || tempProtect != null) {
        await api('config', {
          if (tempProtect != null) 'temp_protect': tempProtect,
          if (tempMax != null) 'temp_max': tempMax,
        });
      }
      // 2.0.18: whole-strip protection (voltage and current limits)
      final prot = <String, dynamic>{
        for (final k in ['v_protect', 'v_restore', 'a_protect'])
          if (cfg[k] is bool) k: cfg[k],
        for (final k in ['v_max', 'v_min', 'a_max', 'hold_s', 'tz_min'])
          if (cfg[k] is num) k: cfg[k],
      };
      if (prot.isNotEmpty) await api('config', prot);
      final ntfy = (cfg['ntfy'] ?? cfg['ntfy_topic'])?.toString();
      final nt = cfg['notifyTypes'] ?? cfg['notify_types'] ?? cfg['ntypes'];
      final ntypes = nt == null ? null : num.tryParse('$nt')?.toInt();
      if (ntfy != null || ntypes != null) {
        await api('notify', {
          if (ntfy != null) 'ntfy': ntfy,
          if (ntypes != null) 'types': ntypes,
        });
      }

      await loadSchedules();
      await loadAutomations();
      await refresh();
    }

    if (parts.contains('app') && j['app'] is Map<String, dynamic>) {
      final appMap = j['app'] as Map<String, dynamic>;
      final p = _prefs ?? await SharedPreferences.getInstance();
      _prefs = p;
      for (final entry in appMap.entries) {
        final k = entry.key;
        var item = entry.value;
        if (k == 'settings' && item is Map && item['v'] is String) {
          // a backup file has no passwords: keep the ones already on this phone
          try {
            final m = Map<String, dynamic>.from(jsonDecode(item['v'] as String) as Map);
            final cur = settings.toJson();
            for (final sk in AppState._secretSettings) {
              if ((m[sk] ?? '').toString().isEmpty) m[sk] = cur[sk];
            }
            item = {'t': 's', 'v': jsonEncode(m)};
          } catch (_) {}
        }
        if (item is Map) {
          final t = item['t'];
          final v = item['v'];
          if (t == 'b' && v is bool) {
            await p.setBool(k, v);
          } else if (t == 'i' && v is num) {
            await p.setInt(k, v.toInt());
          } else if (t == 'd' && v is num) {
            await p.setDouble(k, v.toDouble());
          } else if (t == 's' && v is String) {
            await p.setString(k, v);
          } else if (t == 'l' && v is List) {
            await p.setStringList(k, v.map((e) => e.toString()).toList());
          }
        }
      }
      _loadPrefs();
      await restart();
    }

    if (skipped > 0) {
      return t('backup_skipped', {'n': '$skipped'});
    }
    return null;
  }
}
