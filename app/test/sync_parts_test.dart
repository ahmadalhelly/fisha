import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mttl_hub/services/sync_parts.dart';

Map<String, dynamic> _app() => {
      'names': {'t': 's', 'v': '{"AA":"Kitchen"}'},
      'strip_icon_AABBCC': {'t': 's', 'v': 'icon:bolt'},
      'outlet_icon_AABBCC_2': {'t': 's', 'v': 'icon:fire'},
      'rooms': {'t': 's', 'v': '[]'},
      'scenes': {'t': 's', 'v': '[]'},
      'order': {'t': 'l', 'v': ['AABBCC']},
      'tariff': {'t': 'd', 'v': 1.5},
      'notifyStatus': {'t': 's', 'v': '{}'},
      'bio_AABBCC_1': {'t': 'b', 'v': true},
      'themePref': {'t': 'i', 'v': 2},
      'settings': {'t': 's', 'v': '{"localHost":"192.168.1.100"}'},
      'lastSync': {'t': 's', 'v': '2026-10-22'},
      'accountType': {'t': 's', 'v': 'google'},
      'upd_cache': {'t': 's', 'v': '[]'},
      'syncCats': {'t': 'l', 'v': ['names']},
      'hubMirror': {'t': 's', 'v': jsonEncode(_mirror())},
    };

Map<String, dynamic> _mirror() => {
      'nvs': 'abc',
      'hub_id': 'C88A7BAB95BC',
      'at': '2026-10-22T10:00:00',
      'users': [
        {'id': 'u1', 'name': 'Mona'}
      ],
      'schedules': [
        {'sid': 1}
      ],
      'automations': [
        {'aid': 1}
      ],
      'energy': {'AABBCC': '20261022:100:0:0:0:50'},
      'strips': [
        {
          'mac': 'AABBCC',
          'label': 'Kitchen',
          'notifyMask': 3,
          'outlets': [
            {'n': 1, 'label': 'Fridge', 'locked': true, 'protected': true, 'keep_on': false, 'amp_limit': 10.0, 'autooff': 0},
          ],
        }
      ],
      'config': {'temp_max': 70, 'v_min': 180, 'hold_s': 3, 'tz_min': 180, 'ntfy': 'topic', 'notifyTypes': 7},
    };

Map<String, dynamic> _mirrorOf(Map<String, dynamic> app) => jsonDecode(app['hubMirror']['v'] as String) as Map<String, dynamic>;

void main() {
  test('every kind of data has a name, and the ids are unique', () {
    final ids = SyncParts.cats.map((c) => c.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final c in SyncParts.cats) {
      expect(c.ar.isNotEmpty && c.en.isNotEmpty && c.subAr.isNotEmpty && c.subEn.isNotEmpty, isTrue, reason: c.id);
    }
  });

  test('with everything on, only the per-phone keys are dropped', () {
    final out = SyncParts.filterApp(_app(), SyncParts.allIds);
    for (final k in ['lastSync', 'accountType', 'upd_cache', 'syncCats']) {
      expect(out.containsKey(k), isFalse, reason: k);
    }
    for (final k in ['names', 'strip_icon_AABBCC', 'outlet_icon_AABBCC_2', 'rooms', 'scenes', 'order', 'tariff', 'notifyStatus', 'bio_AABBCC_1', 'themePref', 'settings', 'hubMirror']) {
      expect(out.containsKey(k), isTrue, reason: k);
    }
    final m = _mirrorOf(out);
    expect((m['users'] as List).length, 1);
    expect((m['schedules'] as List).length, 1);
    expect(m['energy'], isNotNull);
    final outlet = ((m['strips'] as List).first['outlets'] as List).first as Map;
    expect(outlet['label'], 'Fridge');
    expect(outlet['locked'], true);
    expect((m['config'] as Map)['tz_min'], 180);
  });

  test('icons off removes the strip and outlet icons and nothing else', () {
    final out = SyncParts.filterApp(_app(), SyncParts.allIds..remove('icons'));
    expect(out.keys.any((k) => k.contains('icon')), isFalse);
    expect(out.containsKey('names'), isTrue);
    expect(out.containsKey('rooms'), isTrue);
  });

  test('names off keeps the protection fields but drops every label', () {
    final out = SyncParts.filterApp(_app(), SyncParts.allIds..remove('names'));
    expect(out.containsKey('names'), isFalse);
    final strip = (_mirrorOf(out)['strips'] as List).first as Map;
    expect(strip.containsKey('label'), isFalse);
    final outlet = (strip['outlets'] as List).first as Map;
    expect(outlet.containsKey('label'), isFalse);
    expect(outlet['locked'], true);
    expect(outlet['amp_limit'], 10.0);
  });

  test('protection off drops the limits and the lock fields, keeps the names and notifications', () {
    final out = SyncParts.filterApp(_app(), SyncParts.allIds..remove('protection'));
    final m = _mirrorOf(out);
    final cfg = m['config'] as Map;
    expect(cfg.containsKey('tz_min'), isFalse);
    expect(cfg.containsKey('v_min'), isFalse);
    expect(cfg['ntfy'], 'topic');
    final strip = (m['strips'] as List).first as Map;
    expect(strip['label'], 'Kitchen');
    expect(strip['notifyMask'], 3);
    final outlet = (strip['outlets'] as List).first as Map;
    expect(outlet['label'], 'Fridge');
    expect(outlet.containsKey('locked'), isFalse);
    expect(outlet.containsKey('amp_limit'), isFalse);
  });

  test('energy off drops the history and the tariff', () {
    final out = SyncParts.filterApp(_app(), SyncParts.allIds..remove('energy'));
    expect(out.containsKey('tariff'), isFalse);
    expect(_mirrorOf(out).containsKey('energy'), isFalse);
  });

  test('schedules, family and notifications switch independently', () {
    var out = SyncParts.filterApp(_app(), SyncParts.allIds..remove('schedules'));
    var m = _mirrorOf(out);
    expect(m.containsKey('schedules'), isFalse);
    expect(m.containsKey('automations'), isFalse);
    expect(m.containsKey('users'), isTrue);
    out = SyncParts.filterApp(_app(), SyncParts.allIds..remove('family'));
    m = _mirrorOf(out);
    expect(m.containsKey('users'), isFalse);
    expect(m.containsKey('schedules'), isTrue);
    out = SyncParts.filterApp(_app(), SyncParts.allIds..remove('notifications'));
    m = _mirrorOf(out);
    expect(out.containsKey('notifyStatus'), isFalse);
    expect((m['config'] as Map).containsKey('ntfy'), isFalse);
    expect(((m['strips'] as List).first as Map).containsKey('notifyMask'), isFalse);
  });

  test('the mirror bookkeeping stays so a restore can tell which hub the copy is of', () {
    final out = SyncParts.filterApp(_app(), {'icons'});
    final m = _mirrorOf(out);
    expect(m['hub_id'], 'C88A7BAB95BC');
    expect(m['nvs'], 'abc');
    expect(m.containsKey('users'), isFalse);
    expect(m.containsKey('strips'), isFalse);
  });

  test('everything off leaves nothing to upload except the mirror bookkeeping', () {
    final out = SyncParts.filterApp(_app(), <String>{});
    expect(out.keys.toSet(), {'hubMirror'});
    expect(_mirrorOf(out).keys.toSet(), {'nvs', 'hub_id', 'at'});
  });

  test('a mirror that cannot be read is dropped, not uploaded as it is', () {
    final bad = {
      'hubMirror': {'t': 's', 'v': 'not json'},
      'rooms': {'t': 's', 'v': '[]'},
    };
    final out = SyncParts.filterApp(bad, SyncParts.allIds);
    expect(out.containsKey('hubMirror'), isFalse);
    expect(out.containsKey('rooms'), isTrue);
  });
}
