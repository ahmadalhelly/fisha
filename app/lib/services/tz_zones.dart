/// The time zones the app offers. The ids are the ones the hub knows (TZ_ZONES in the hub firmware), and the hub
/// holds the daylight-saving rule of each; the standard offset here is what a fixed offset uses when summer time is off.
class TzZoneInfo {
  final String id, ar, en, country;
  final int stdMin; // offset from UTC in winter time, minutes
  final bool dst; // the zone switches to summer time
  const TzZoneInfo(this.id, this.ar, this.en, this.country, this.stdMin, this.dst);
}

class TzZones {
  static const all = <TzZoneInfo>[
    TzZoneInfo('cairo', 'القاهرة', 'Cairo', 'EG', 120, true),
    TzZoneInfo('riyadh', 'الرياض', 'Riyadh', 'SA', 180, false),
    TzZoneInfo('dubai', 'دبي', 'Dubai', 'AE', 240, false),
    TzZoneInfo('kuwait', 'الكويت', 'Kuwait', 'KW', 180, false),
    TzZoneInfo('doha', 'الدوحة', 'Doha', 'QA', 180, false),
    TzZoneInfo('baghdad', 'بغداد', 'Baghdad', 'IQ', 180, false),
    TzZoneInfo('amman', 'عمّان', 'Amman', 'JO', 180, false),
    TzZoneInfo('istanbul', 'إسطنبول', 'Istanbul', 'TR', 180, false),
    TzZoneInfo('muscat', 'مسقط', 'Muscat', 'OM', 240, false),
    TzZoneInfo('khartoum', 'الخرطوم', 'Khartoum', 'SD', 120, false),
    TzZoneInfo('tunis', 'تونس', 'Tunis', 'TN', 60, false),
    TzZoneInfo('algiers', 'الجزائر', 'Algiers', 'DZ', 60, false),
    TzZoneInfo('casablanca', 'الدار البيضاء', 'Casablanca', 'MA', 60, false),
    TzZoneInfo('london', 'لندن', 'London', 'GB', 0, true),
    TzZoneInfo('paris', 'باريس', 'Paris', 'FR', 60, true),
    TzZoneInfo('newyork', 'نيويورك', 'New York', 'US', -300, true),
    TzZoneInfo('delhi', 'نيودلهي', 'New Delhi', 'IN', 330, false),
    TzZoneInfo('utc', 'التوقيت العالمي', 'UTC', 'UT', 0, false),
  ];

  static TzZoneInfo? byId(String id) {
    for (final z in all) {
      if (z.id == id) return z;
    }
    return null;
  }

  /// the zone that fits the phone's own clock: the offsets it has in January and in July tell a zone with
  /// summer time from one without, and which one (no plugin needed)
  /// null when no zone of the list has those offsets (the caller then keeps the phone's offset as it is)
  static TzZoneInfo? detect(int janMin, int julMin) {
    if (janMin != julMin) {
      final std = janMin < julMin ? janMin : julMin;
      for (final z in all) {
        if (z.dst && z.stdMin == std) return z;
      }
    }
    if (janMin != julMin) return null;
    for (final z in all) {
      if (!z.dst && z.stdMin == janMin) return z;
    }
    return null;
  }

  static String offsetText(int min) {
    final sign = min < 0 ? '-' : '+';
    final a = min.abs();
    final h = a ~/ 60, m = a % 60;
    return 'UTC$sign$h${m == 0 ? '' : ':${m.toString().padLeft(2, '0')}'}';
  }
}
