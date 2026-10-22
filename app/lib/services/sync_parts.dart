import 'dart:convert';

/// One kind of data the Google sync can carry. The owner switches each one on or off in the sync page.
class SyncCat {
  final String id;
  final String ar, en, subAr, subEn;
  const SyncCat(this.id, this.ar, this.en, this.subAr, this.subEn);
}

/// What travels in the Google copy, split into kinds the user can choose from. Pure functions: the same
/// filtering runs when the copy is uploaded and when it is restored, and the tests cover both.
class SyncParts {
  static const cats = <SyncCat>[
    SyncCat('names', 'أسماء المشتركات والمخارج', 'Strip and outlet names', 'الاسم اللي إنت كاتبه لكل مشترك ولكل مخرج.', 'The name you gave each strip and outlet.'),
    SyncCat('icons', 'الأيقونات', 'Icons', 'أيقونة كل مشترك وكل مخرج.', 'The icon of each strip and outlet.'),
    SyncCat('rooms', 'الغرف والسيناريوهات والترتيب', 'Rooms, scenes and order', 'تجميع المشتركات في غرف، والسيناريوهات، وترتيب الكروت.', 'Rooms, scenes and the order of the cards.'),
    SyncCat('schedules', 'المواعيد والأتمتة', 'Schedules and automations', 'المواعيد والمؤقتات وقواعد الأتمتة المحفوظة في الهاب.', 'Schedules and automation rules kept on the hub.'),
    SyncCat('protection', 'الحماية والقفل', 'Protection and locks', 'حدود الفولت والتيار والحرارة، وقفل الأطفال، والمخرج المحمي والتشغيل الدائم والإطفاء التلقائي.', 'Voltage, current and temperature limits, child lock, protected outlets, keep-on and auto-off.'),
    SyncCat('energy', 'سجل الاستهلاك والتعريفة', 'Usage history and tariff', 'استهلاك كل يوم لكل مخرج وسعر الكيلووات.', 'Daily use per outlet and the price per kWh.'),
    SyncCat('family', 'العيلة والصلاحيات', 'Family and permissions', 'الأعضاء وصلاحياتهم.', 'The members and what each may do.'),
    SyncCat('notifications', 'الإشعارات', 'Notifications', 'أنواع الإشعارات المفعّلة وقناة ntfy.', 'The notification types switched on and the ntfy topic.'),
    SyncCat('biometric', 'بصمة المخارج', 'Outlet fingerprint', 'المخارج اللي ليها بصمة.', 'Which outlets need a fingerprint.'),
    SyncCat('app', 'إعدادات التطبيق', 'App settings', 'المظهر واللغة وطريقة العرض والاتصال وإعدادات المزامنة.', 'Theme, language, view, connection and sync settings.'),
  ];

  static Set<String> get allIds => {for (final c in cats) c.id};

  /// keys that never travel: they belong to this phone (and the update-center cache is only a cache)
  static const neverSync = {
    'lastSync', 'accountType', 'googleEmail', 'googlePhoto', 'pendingOps', 'notifyFilter', 'syncCats', 'backupEnc', 'backupBio', 'upd_at', 'upd_cache', 'upd_dismissed',
  };

  /// the kind a SharedPreferences key belongs to; anything not listed is an app setting
  static String appCategoryOf(String key) {
    if (key == 'names') return 'names';
    if (key.startsWith('strip_icon_') || key.startsWith('outlet_icon_')) return 'icons';
    if (key == 'rooms' || key == 'scenes' || key == 'order') return 'rooms';
    if (key == 'tariff') return 'energy';
    if (key == 'notifyStatus') return 'notifications';
    if (key.startsWith('bio_')) return 'biometric';
    if (key == 'hubMirror') return 'hubMirror';
    return 'app';
  }

  /// the app part of a copy ({key: {t, v}}) cut down to the chosen kinds. [hubMirror] is cut by [filterHub].
  static Map<String, dynamic> filterApp(Map<String, dynamic> app, Set<String> on) {
    final out = <String, dynamic>{};
    for (final e in app.entries) {
      if (neverSync.contains(e.key)) continue;
      final c = appCategoryOf(e.key);
      if (c == 'hubMirror') {
        final cut = _filterMirrorEntry(e.value, on);
        if (cut != null) out[e.key] = cut;
      } else if (on.contains(c)) {
        out[e.key] = e.value;
      }
    }
    return out;
  }

  static Map<String, dynamic>? _filterMirrorEntry(dynamic item, Set<String> on) {
    if (item is! Map || item['v'] is! String) return null;
    try {
      final m = jsonDecode(item['v'] as String);
      if (m is! Map) return null;
      final cut = filterHub(Map<String, dynamic>.from(m), on);
      return {'t': 's', 'v': jsonEncode(cut)};
    } catch (_) {
      return null;
    }
  }

  static const _outletNames = {'n', 'label'};
  static const _outletProtection = {'n', 'locked', 'protected', 'autooff', 'auto_off_min', 'keep_on', 'keepOn', 'amp_limit'};
  static const _limits = {'temp_max', 'temp_protect', 'v_protect', 'v_restore', 'v_max', 'v_min', 'a_protect', 'a_max', 'hold_s', 'tz_min', 'tz_zone'};

  /// the hub part of a copy (users, schedules, automations, strips, energy, config) cut down to the chosen kinds.
  /// The bookkeeping keys of the mirror (nvs, hub_id, at) always stay.
  static Map<String, dynamic> filterHub(Map<String, dynamic> hub, Set<String> on) {
    final out = <String, dynamic>{};
    for (final e in hub.entries) {
      switch (e.key) {
        case 'users':
          if (on.contains('family')) out[e.key] = e.value;
        case 'schedules':
        case 'automations':
          if (on.contains('schedules')) out[e.key] = e.value;
        case 'energy':
          if (on.contains('energy')) out[e.key] = e.value;
        case 'strips':
          final s = _filterStrips(e.value, on);
          if (s != null) out[e.key] = s;
        case 'config':
          final c = _filterConfig(e.value, on);
          if (c != null) out[e.key] = c;
        default:
          out[e.key] = e.value; // nvs, hub_id, at
      }
    }
    return out;
  }

  static List<dynamic>? _filterStrips(dynamic strips, Set<String> on) {
    if (strips is! List) return null;
    final names = on.contains('names'), prot = on.contains('protection'), notif = on.contains('notifications');
    if (!names && !prot && !notif) return null;
    final out = <dynamic>[];
    for (final raw in strips) {
      if (raw is! Map) continue;
      final s = <String, dynamic>{'mac': raw['mac']};
      if (names && raw.containsKey('label')) s['label'] = raw['label'];
      if (notif) {
        if (raw.containsKey('notify')) s['notify'] = raw['notify'];
        if (raw.containsKey('notifyMask')) s['notifyMask'] = raw['notifyMask'];
      }
      final outlets = raw['outlets'];
      if (outlets is List && (names || prot)) {
        final keep = {if (names) ..._outletNames, if (prot) ..._outletProtection};
        s['outlets'] = [
          for (final o in outlets)
            if (o is Map) {for (final k in o.keys) if (keep.contains(k)) k: o[k]},
        ];
      }
      out.add(s);
    }
    return out;
  }

  static Map<String, dynamic>? _filterConfig(dynamic cfg, Set<String> on) {
    if (cfg is! Map) return null;
    final out = <String, dynamic>{};
    for (final e in cfg.entries) {
      final k = e.key.toString();
      if (_limits.contains(k) && on.contains('protection')) out[k] = e.value;
      if ((k == 'ntfy' || k == 'notifyTypes') && on.contains('notifications')) out[k] = e.value;
    }
    return out.isEmpty ? null : out;
  }
}
