/// Tiny i18n: `t('key')` and `t('key', {'n': 3})`. [Tr.lang] is set by the app root.
class Tr {
  static String lang = 'ar';
  static bool get isAr => lang == 'ar';
}

String t(String key, [Map<String, Object?> args = const {}]) {
  final row = _s[key];
  var v = row == null ? key : (Tr.isAr ? row[0] : row[1]);
  args.forEach((k, val) => v = v.replaceAll('{$k}', '$val'));
  return v;
}

const Map<String, List<String>> _s = {
  // home
  'home_kicker': ['البيت', 'Home'],
  'home_title': ['مشتركاتي', 'My strips'],
  'mode_local': ['محلي', 'Local'],
  'mode_cloud': ['عن بُعد', 'Remote'],
  'mode_offline': ['غير متصل', 'Offline'],
  'power_now': ['القدرة دلوقتي', 'Power now'],
  'refresh_2s': ['تحديث كل ثانيتين', 'Updates every 2 s'],
  'live': ['تحديث لحظي', 'Live updates'],
  'stat_online': ['مشترك متصل', 'strips online'],
  'stat_on': ['مخرج شغال', 'outlets on'],
  'stat_temp': ['أعلى حرارة', 'hottest'],
  'q_energy': ['الطاقة', 'Energy'],
  'q_sched': ['المواعيد', 'Schedules'],
  'q_auto': ['الأتمتة', 'Automations'],
  'q_rooms': ['الغرف', 'Rooms'],
  'soon': ['{x} جاية في الـ Sprints الجاية', '{x} is coming in a later sprint'],
  'search_hint': ['دوّر على مشترك أو مخرج', 'Search strips and outlets'],
  'view_list': ['عرض القائمة', 'List view'],
  'view_grid': ['عرض الشبكة', 'Grid view'],
  'sort': ['ترتيب', 'Sort'],
  'sort_manual': ['ترتيبي (بالسحب)', 'My order (drag)'],
  'sort_power': ['الأعلى استهلاكًا', 'Highest power'],
  'sort_name': ['بالاسم', 'By name'],
  'sort_status': ['الأكتر شغال', 'Most outlets on'],
  'empty_nocfg_t': ['لسه ماظبطتش الاتصال', 'Connection not set up yet'],
  'empty_nocfg_b': [
    'افتح الإعدادات وحط عنوان الـ Hub المحلي، أو بيانات السيرفر عشان تتحكم من برا البيت.',
    'Open settings and enter the local hub address, or the server details for remote control.'
  ],
  'empty_off_t': ['مش لاقي الـ Hub', "Can't reach the hub"],
  'empty_off_cloud': [
    'اتأكد إن الـ ESP32 شغالة ومتصلة بالنت، وإن باسورد السيرفر صح.',
    'Make sure the ESP32 is powered and online, and the server password is right.'
  ],
  'empty_off_local': [
    'اتأكد إنك على نفس شبكة الواي فاي، أو ضيف بيانات السيرفر من الإعدادات.',
    'Make sure you are on the same Wi-Fi, or add the server details in settings.'
  ],
  'empty_noq_t': ['مفيش نتايج', 'No results'],
  'empty_noq_b': ['مفيش مشترك أو مخرج بالاسم ده.', 'No strip or outlet matches that name.'],
  'empty_none_t': ['مفيش مشترك متصل بالـ Hub', 'No strip connected to the hub'],
  'empty_none_b': [
    'ضيف مشترك من زرار "إضافة مشترك"، أو لو متضاف قبل كده افصله من الكهربا ورجّعه.',
    'Add one with "Add strip", or power-cycle a strip that was set up before.'
  ],
  // common
  'settings': ['الإعدادات', 'Settings'],
  'cancel': ['إلغاء', 'Cancel'],
  'save': ['حفظ', 'Save'],
  'online': ['متصل', 'Online'],
  'offline': ['غير متصل', 'Offline'],
  'off': ['مقفول', 'Off'],
  'all_on': ['شغّل الكل', 'All on'],
  'all_off': ['اقفل الكل', 'All off'],
  'n_of_4': ['{a} من {b} شغالين', '{a} of {b} on'],
  'default_strip': ['مشترك {id}', 'Strip {id}'],
  'default_outlet': ['مخرج {n}', 'Outlet {n}'],
  // strip settings
  'strip_settings': ['إعدادات المشترك', 'Strip settings'],
  'rename_strip': ['تغيير اسم المشترك', 'Rename strip'],
  'strip_name': ['اسم المشترك', 'Strip name'],
  'outlet_name': ['اسم المخرج {n}', 'Outlet {n} name'],
  'child_lock': ['قفل الأطفال', 'Child lock'],
  'child_lock_sub': ['زرار المشترك نفسه مش هيغيّر المخرج ده', "The strip's own button won't change this outlet"],
  'outlets': ['المخارج', 'Outlets'],
  'device': ['الجهاز', 'Device'],
  'fw': ['الفيرموير', 'Firmware'],
  'voltage': ['الفولت', 'Voltage'],
  'rssi': ['قوة الإشارة', 'Signal'],
  // nav
  'nav_home': ['الرئيسية', 'Home'],
  'nav_sched': ['الجدولة', 'Schedules'],
  'nav_energy': ['الطاقة', 'Energy'],
  'nav_settings': ['الإعدادات', 'Settings'],
  'ph_sched': [
    'المواعيد والـ Auto-timers جايين في Sprint 3، وهيتنفذوا جوه الـ Hub نفسه حتى لو النت فاصل.',
    'Schedules and auto-timers arrive in Sprint 3 and run inside the hub, even offline.'
  ],
  'ph_energy': [
    'سجل الاستهلاك والتكلفة بشرائح الكهرباء المصرية جايين في Sprint 4.',
    'Usage history and cost with Egyptian tariff tiers arrive in Sprint 4.'
  ],
  // settings
  'conn_status': ['حالة الاتصال', 'Connection'],
  'st_local': ['محلي (نفس الشبكة)', 'Local (same Wi-Fi)'],
  'st_cloud': ['السيرفر (من برا البيت)', 'Server (remote)'],
  'st_hub': ['الـ Hub متصل بالسيرفر', 'Hub online on server'],
  'hub_fw': ['فيرموير الـ Hub', 'Hub firmware'],
  'sec_local': ['الـ Hub المحلي', 'Local hub'],
  'f_local': ['عنوان الـ Hub', 'Hub address'],
  'f_port': ['البورت', 'Port'],
  'sec_cloud': ['السيرفر (التحكم من برا البيت)', 'Server (remote control)'],
  'f_hubid': ['Hub ID', 'Hub ID'],
  'f_host': ['عنوان السيرفر', 'Server host'],
  'f_user': ['اسم المستخدم', 'Username'],
  'f_pass': ['الباسورد', 'Password'],
  'show': ['إظهار', 'Show'],
  'hide': ['إخفاء', 'Hide'],
  'save_reconnect': ['حفظ وإعادة الاتصال', 'Save & reconnect'],
  'saved': ['اتحفظ، وجاري إعادة الاتصال', 'Saved, reconnecting'],
  'sec_privacy': ['الخصوصية', 'Privacy'],
  'show_mac': ['إظهار الـ MAC', 'Show MAC address'],
  'show_mac_sub': [
    'مخفي افتراضيًا عشان تقدر تاخد سكرين شوت وتشاركها بأمان',
    'Hidden by default so screenshots are safe to share'
  ],
  'sec_look': ['المظهر واللغة', 'Appearance & language'],
  'theme': ['الثيم', 'Theme'],
  'th_system': ['تلقائي', 'Auto'],
  'th_dark': ['داكن', 'Dark'],
  'th_light': ['فاتح', 'Light'],
  'language': ['اللغة', 'Language'],
  // errors
  'err_not_confirmed': ['الأمر ماتأكدش', 'Command not confirmed'],
  'err_no_ack': ['الـ Hub مردّش', 'The hub did not answer'],
  'err_no_conn': ['مفيش اتصال بالـ Hub', 'No connection to the hub'],
  'err_failed': ['فشل الأمر', 'Command failed'],
  'err_old_fw': ['الميزة دي محتاجة فيرموير الـ Hub v1.1', 'This needs hub firmware v1.1'],
  // add strip
  'add_strip': ['إضافة مشترك', 'Add strip'],
  'add_step1_t': ['حط المشترك في وضع الإعداد', 'Put the strip in setup mode'],
  'add_step1_b': [
    'اضغط على الزرار الرئيسي في المشترك حوالي 10 ثواني لحد ما اللمبة ترمش بسرعة. الـ Hub هيعمل الباقي لوحده.',
    "Hold the strip's main button for about 10 seconds until the LED blinks fast. The hub does the rest."
  ],
  'add_tip': [
    'خلي المشترك قريب من الـ Hub. الـ Hub هيفصل عن الواي فاي حوالي 20 ثانية وهو بيظبط المشترك، وده طبيعي.',
    'Keep the strip near the hub. The hub leaves Wi-Fi for about 20 seconds while it configures the strip — that is normal.'
  ],
  'add_start': ['المشترك بيرمش، ابدأ', "It's blinking — start"],
  'add_sending': ['ببعت الطلب للـ Hub', 'Sending the request to the hub'],
  'add_running': ['الـ Hub بيكلّم المشترك…', 'The hub is talking to the strip…'],
  'add_wait': ['المشترك اتظبط، مستنيه يتصل', 'Strip configured, waiting for it to connect'],
  'add_done_t': ['المشترك اتضاف', 'Strip added'],
  'add_done_b': ['تقدر تسميه من زرار إعدادات المشترك.', 'You can rename it from strip settings.'],
  'add_error_t': ['ماكملش', "It didn't finish"],
  'add_timeout': [
    'خد وقت أكتر من اللازم. اتأكد إن المشترك بيرمش وقريب من الـ Hub وجرب تاني.',
    'This took too long. Make sure the strip is blinking and close to the hub, then try again.'
  ],
  'add_retry': ['جرب تاني', 'Try again'],
  'add_close': ['تمام', 'Done'],
};
