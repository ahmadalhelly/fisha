import 'package:flutter/material.dart';

import '../i18n.dart';
import '../theme.dart';

String _tr(String ar, String en) => Tr.isAr ? ar : en;

enum _G { tap, hold, slide, go }

class _Item {
  final IconData icon;
  final String title, summary;
  final List<(_G, String)> how;
  final List<String> steps;
  final String? warning;
  const _Item(this.icon, this.title, this.summary, {this.how = const [], this.steps = const [], this.warning});
}

class _Sec {
  final String title;
  final List<_Item> items;
  const _Sec(this.title, this.items);
}

/// User guide: every feature and how to use it, briefly. Search on top, sections of expandable rows.
class ManualScreen extends StatefulWidget {
  const ManualScreen({super.key});
  @override
  State<ManualScreen> createState() => _ManualScreenState();
}

class _ManualScreenState extends State<ManualScreen> {
  String _q = '';
  final Set<String> _open = {};

  static String get _sfwWarning => _tr(
      'تنبيه: فيرموير المشترك تعديل غير رسمي على فيرموير الشركة، والتحديث على مسؤوليتك. لو الكهربا أو الواي فاي قطعت وقت التحديث، المشترك ممكن يبطّل يشتغل ويحتاج إصلاح يدوي،. استخدم الملفات اللي من إصدارات فيشة بس، وجرّب على مشترك واحد الأول، وماتفصلش المشترك ولا الـ Hub لحد ما يخلص.',
      'Warning: strip firmware is an unofficial modification of the maker\'s firmware, and you update at your own risk. If power or Wi-Fi drops during an update, the strip may stop working and need a manual repair. Use only files from Fisha releases, try one strip first, and keep the strip and the hub powered until it finishes.');

  List<_Sec> get _secs => [
        _Sec(_tr('إضافة وضبط المشتركات', 'Adding and setting up strips'), [
          _Item(Icons.add_circle_outline, _tr('إضافة مشترك', 'Add a strip'),
              _tr('من الرئيسية دوس «إضافة مشترك»، والـ Hub بيظبط المشترك لوحده. لازم تكون على واي فاي البيت.', 'On Home tap "Add strip" and the hub sets the strip up by itself. You must be on the home Wi-Fi.'),
              how: [(_G.go, _tr('الرئيسية ← إضافة مشترك', 'Home → Add strip'))],
              steps: [
                _tr('دوس على زرار المشترك حوالي 10 ثواني لحد ما اللمبة ترمش بسرعة.', 'Hold the strip\'s button about 10 seconds until the LED blinks fast.'),
                _tr('دوس «دوّر على المشتركات» واختار المشترك. الرقم هو آخر 7 خانات من الـ MAC ومكتوب على الملصق تحته.', 'Tap "Search for strips" and pick it. The ID is the last 7 digits of the MAC, on the label underneath.'),
                _tr('الـ Hub بيدخل شبكة المشترك ويبعتله شبكة البيت ويعمله ريستارت. الـ Hub بيفصل عن الواي فاي ثواني، وده طبيعي.', 'The hub joins the strip\'s network, sends it the home Wi-Fi and restarts it. The hub leaves Wi-Fi for a few seconds; that is normal.'),
                _tr('أول ما يتصل هيظهر في الرئيسية، وتقدر تسمّيه من إعداداته.', 'Once it connects it shows on Home; rename it from its settings.'),
              ]),
          _Item(Icons.tips_and_updates_outlined, _tr('لو الإضافة ماكملتش', 'If adding fails'),
              _tr('قرّب المشترك من الـ Hub، واتأكد إن اللمبة لسه بترمش بسرعة، وجرب تاني.', 'Move the strip closer to the hub, check the LED still blinks fast, and retry.'),
              steps: [
                _tr('الشبكة لازم تكون 2.4GHz، واسمها وباسوردها مافيهمش علامة :', 'The Wi-Fi must be 2.4 GHz, with no ":" in its name or password.'),
                _tr('افصل أي موبايل أو لابتوب متوصل بشبكة المشترك (TONLY_TAP).', 'Disconnect any phone or laptop joined to the strip\'s network (TONLY_TAP).'),
                _tr('لو قال إن المشترك لسه في وضع الإعداد: افصله من الكهربا 10 ثواني ورجّعه.', 'If it says the strip is still in setup mode: unplug it for 10 seconds and plug it back.'),
              ]),
          _Item(Icons.wifi, _tr('تغيير شبكة الواي فاي', 'Changing the Wi-Fi'),
              _tr('غيّر الشبكة من التطبيق الأول وبعدين غيّر الراوتر. الـ Hub بيجرّبها ويبعتها للمشتركات وينقلوا معاه.', 'Change the network in the app first, then change the router. The hub tests it, hands it to the strips and they move with it.'),
              how: [(_G.go, _tr('الإعدادات ← شبكة الواي فاي', 'Settings → Wi-Fi network'))],
              steps: [
                _tr('اكتب اسم الشبكة الجديدة وباسوردها ودوس «جرّب واحفظ».', 'Enter the new network name and password and tap "Test & save".'),
                _tr('لو الشبكة اشتغلت، الـ Hub بيبعتها لكل مشترك متصل وبعدين ينقل عليها. لو فشلت بيرجع للقديمة.', 'If it works the hub hands it to every connected strip, then moves to it. If not, it stays on the old one.'),
                _tr('مشترك ما اتنقلش، أو غيّرت الراوتر الأول: دوس زراره 10 ثواني والـ Hub بيربطه لوحده.', 'A strip did not move, or you changed the router first: hold its button 10 seconds and the hub relinks it.'),
              ]),
          _Item(Icons.tune, _tr('إعدادات المشترك', 'Strip settings'),
              _tr('ضغطة على اسم المشترك أو أيقونة الإعدادات: الاسم، الإشعارات، البصمة للمفتاح الرئيسي، كارت الشبكة والاتصال، وبيانات الجهاز.', 'Tap the strip name or the settings icon: name, notifications, fingerprint for the master switch, the network card and device info.'),
              how: [(_G.tap, _tr('ضغطة على اسم المشترك', 'Tap the strip name'))],
              steps: [
                _tr('الشبكة والاتصال: نسبة الاتصال والانقطاعات والإشارة لآخر 7 أيام. دوس على أي يوم لتفاصيله.', 'Network & connection: uptime, drops and signal for 7 days. Tap a day for details.'),
                _tr('الجهاز: الفيرموير والفولت والإشارة وعنوان IP.', 'Device: firmware, voltage, signal and IP.'),
              ]),
          _Item(Icons.delete_outline, _tr('حذف مشترك', 'Delete a strip'),
              _tr('من إعدادات المشترك ← حذف المشترك. الـ Hub بيتجاهله حتى لو فضل في الكهربا، ولو عاوز ترجّعه ضيفه تاني.', 'Strip settings → Delete strip. The hub ignores it even if still plugged in; add it again to bring it back.'),
              how: [(_G.go, _tr('إعدادات المشترك ← حذف', 'Strip settings → Delete'))]),
        ]),
        _Sec(_tr('التحكم', 'Control'), [
          _Item(Icons.power_settings_new, _tr('تشغيل وإيقاف مخرج', 'Switch an outlet'),
              _tr('ضغطة على المخرج تشغّله أو تقفله. لو عليه بصمة هيطلبها الأول.', 'Tap an outlet to switch it. If it has a fingerprint lock, it asks first.'),
              how: [(_G.tap, _tr('ضغطة على المخرج', 'Tap the outlet'))]),
          _Item(Icons.swipe, _tr('المفتاح الرئيسي', 'Master switch'),
              _tr('ضغطة تشغّل أو تقفل المشترك كله. ضغطة مطولة واسحب يمين لتشغيل الكل أو شمال لإيقاف الكل.', 'Tap to switch the whole strip. Hold and slide right for all on, left for all off.'),
              how: [(_G.tap, _tr('تشغيل/إيقاف', 'On/off')), (_G.hold, ''), (_G.slide, _tr('يمين: تشغيل الكل · شمال: إيقاف الكل', 'Right: all on · Left: all off'))],
              steps: [
                _tr('الدائرة بتتمد لكبسولة. ارفع صباعك على الاختيار اللي عاوزه.', 'The circle stretches into a capsule. Lift your finger on the option you want.'),
                _tr('ارفع صباعك في النص عشان تلغي.', 'Lift in the middle to cancel.'),
                _tr('لو كله مقفول بيظهر «تشغيل الكل» بس، ولو كله شغال بيظهر «إيقاف الكل» بس.', 'All off shows only "All on"; all on shows only "All off".'),
                _tr('المخارج المحمية أو اللي عليها بصمة بتطلب تأكيد.', 'Protected or fingerprint outlets ask for confirmation.'),
              ]),
          _Item(Icons.settings_outlined, _tr('إعدادات المخرج', 'Outlet settings'),
              _tr('ضغطة مطولة على المخرج: الاسم والأيقونة، الحماية من القفل بالغلط، التشغيل دائماً، قفل الأطفال، البصمة، والقفل التلقائي.', 'Hold an outlet: name and icon, protect from accidental off, keep always on, child lock, fingerprint and auto-off.'),
              how: [(_G.hold, _tr('ضغطة مطولة على المخرج', 'Hold the outlet'))],
              steps: [
                _tr('الحماية مناسبة للراوتر: بيطلب تأكيد قبل ما يتقفل.', 'Protection suits the router: it asks before turning off.'),
                _tr('قفل الأطفال بيقفل زرار المشترك نفسه، والتحكم من التطبيق بس.', 'Child lock disables the strip\'s own button; only the app controls it.'),
              ]),
          _Item(Icons.auto_awesome_motion_outlined, _tr('السيناريوهات', 'Scenarios'),
              _tr('مجموعة أوامر لمخارج كتير بضغطة واحدة.', 'A set of commands for many outlets in one tap.'),
              how: [(_G.go, _tr('الرئيسية ← السيناريوهات', 'Home → Scenarios'))]),
          _Item(Icons.meeting_room_outlined, _tr('الغرف', 'Rooms'),
              _tr('جمّع مشتركات في غرفة وتحكم فيها مرة واحدة، ومعاها بصمة للغرفة.', 'Group strips into a room and control them together, with an optional room fingerprint.'),
              how: [(_G.go, _tr('الرئيسية ← الغرف', 'Home → Rooms')), (_G.go, _tr('الإعدادات ← الغرف', 'Settings → Rooms'))]),
        ]),
        _Sec(_tr('المواعيد والأتمتة', 'Schedules and automation'), [
          _Item(Icons.schedule, _tr('الجداول والمؤقتات', 'Schedules and timers'),
              _tr('جدولة تشغيل وإيقاف بأيام الأسبوع، مؤقت لمرة واحدة، تكرار، وإعادة تشغيل.', 'Weekly on/off schedules, one-off timers, loops and power-cycles.'),
              how: [(_G.go, _tr('تبويب الجدولة', 'Scheduling tab'))],
              steps: [
                _tr('إعادة التشغيل بتقفل المخرج وترجّعه، ومفيدة للأجهزة اللي بتهنّج.', 'A power-cycle turns the outlet off and back on; handy for devices that hang.'),
                _tr('المخرج المحمي مش بيتعمله إعادة تشغيل عشان لو عليه الراوتر النت هيقطع.', 'Protected outlets are not power-cycled: if the router is on it, the network drops.'),
              ]),
          _Item(Icons.bolt, _tr('الأتمتة', 'Automations'),
              _tr('قاعدة بتقفل أو تنبّه لما الوات أو الأمبير أو الحرارة يعدّوا حد لمدة معيّنة.', 'A rule that cuts or alerts when watts, amps or temperature pass a limit for a set time.'),
              how: [(_G.go, _tr('الرئيسية ← الأتمتة', 'Home → Automations'))]),
        ]),
        _Sec(_tr('الحماية', 'Protection'), [
          _Item(Icons.shield_outlined, _tr('حماية الفولت والتيار والحرارة', 'Voltage, current and temperature'),
              _tr('الـ Hub بيقفل لما الفولت يعلى أو يوطى، أو الحمل يعدّي 3500 وات، أو التيار أو الحرارة يعدّوا الحد.', 'The hub cuts on high or low voltage, a load over 3500 W, or current or temperature past the limit.'),
              steps: [
                _tr('الفولت العالي بيقفل المشترك كله حتى المخارج المحمية.', 'High voltage cuts the whole strip, protected outlets too.'),
                _tr('أقل حد للفولت الواطي 170.', 'The low-voltage limit starts at 170.'),
                _tr('فوق 3500 وات بيقفل أكبر المخارج غير المحمية لحد ما الحمل يرجع تحت الحد.', 'Over 3500 W it cuts the biggest unprotected outlets until the load is back under.'),
                _tr('الـ Hub بيتأكد إن المخرج اتقفل فعلاً ويعيد الأمر، ولو فشل يبعتلك إشعار.', 'The hub checks the outlet really went off and resends; if that fails it alerts you.'),
                _tr('إشعارات الحماية بتوصلك دايماً حتى لو المشترك مكتوم.', 'Safety alerts always reach you, even when the strip is muted.'),
              ]),
        ]),
        _Sec(_tr('مميزات محفوظة جوه المشترك', 'Features kept inside the strip'), [
          _Item(Icons.lock_person_outlined, _tr('قفل الأطفال على أزرار المشترك', 'Child lock on the strip buttons'),
              _tr('بتقفل الزرار الرئيسي وأي مخرج من أزرار المشترك نفسها. القفل محفوظ داخل إعدادات المشترك، يعني بيتنفذ حتى من غير اتصال بالهاب.',
                  'Locks the master button and any outlet on the strip itself. The lock is stored inside the strip, so it works even without the hub.'),
              how: [(_G.hold, _tr('ضغطة مطولة على المخرج ← قفل الأطفال', 'Long-press the outlet → Child lock'))]),
          _Item(Icons.tune, _tr('حدود الحماية جوه المشترك', 'Protection limits inside the strip'),
              _tr('الفولت الأقل والأعلى، أقصى تيار، أقصى وات، أقصى حرارة، ومهلة الفصل بالثواني. الحدود بتتحفظ داخل إعدادات المشترك وبتتنفذ حتى لو الهاب فاصل.',
                  'Low and high voltage, maximum current, maximum power, maximum temperature and the trip delay. The limits are stored inside the strip and apply even when the hub is offline.'),
              how: [(_G.go, _tr('الإعدادات ← حدود الحماية', 'Settings → Protection limits'))],
              steps: [
                _tr('الحدود لكل مشترك كله، مش لكل مخرج. حد الأمبير لكل مخرج بيتنفذ من الهاب.', 'Limits apply to the whole strip, not per outlet. A per-outlet amp limit is enforced by the hub.'),
                _tr('أي قاعدة أتمتة بتفصل عند وات أقل بتنزل للمشترك كحد أمان.', 'An automation that cuts at a lower wattage is also sent to the strip as a safety limit.'),
                _tr('في الأتمتة تقدر تختار «كل المشتركات» عشان نفس القاعدة تتنفذ على الهاب كله.', 'In Automations you can pick "All strips" so one rule covers the whole hub.'),
              ]),
          _Item(Icons.restart_alt, _tr('إعادة تشغيل مخرج أو المشترك كله', 'Restart an outlet or the whole strip'),
              _tr('بيفصل المخرج (أو المشترك كله) عدد ثواني ويرجّعه لوحده، حتى لو الاتصال بالهاب اتقطع. مفيد لمخرج الراوتر.',
                  'Switches the outlet (or the whole strip) off for a few seconds and back on by itself, even if the hub link drops. Handy for the router outlet.'),
              how: [(_G.go, _tr('تبويب الجدولة', 'Scheduling tab'))]),
          _Item(Icons.event_repeat, _tr('جدولة بدون هاب', 'Schedule without the hub'),
              _tr('ميعاد تشغيل أو إيقاف كل يوم أو في أيام محددة بيتحفظ في المشترك وبيتنفذ بساعته حتى لو الهاب فاصل.',
                  'An on or off time, every day or on chosen days, is saved in the strip and runs by its own clock even when the hub is offline.'),
              how: [(_G.go, _tr('تبويب الجدولة', 'Scheduling tab'))]),
          _Item(Icons.schedule_send_outlined, _tr('ساعة المشترك والمنطقة الزمنية', 'Strip clock and time zone'),
              _tr('الهاب بيظبط ساعة المشترك والمنطقة الزمنية لوحده، والجدولة الذاتية بتمشي عليهم.',
                  'The hub sets the strip clock and the time zone by itself, and the strip\'s own schedules follow them.'),
              how: [(_G.go, _tr('الرئيسية ← الأتمتة', 'Home → Automations'))]),
        ]),
        _Sec(_tr('الوقت والسيناريوهات والهابات', 'Time, scenarios and hubs'), [
          _Item(Icons.public, _tr('الوقت والمنطقة الزمنية', 'Time and time zone'),
              _tr('اختار منطقتك تلقائي من الموبايل أو بالبحث عن مدينة. الهاب بيغيّر الساعة للتوقيت الصيفي والشتوي لوحده (في مصر آخر جمعة في أبريل وآخر خميس في أكتوبر) وبيبلّغ المشتركات.',
                  'Pick your zone from the phone or by searching a city. The hub moves the clock for summer and winter time by itself and tells the strips.'),
              how: [(_G.go, _tr('الإعدادات ← الوقت والمنطقة الزمنية', 'Settings → Time and time zone'))],
              steps: [
                _tr('الصفحة بتعرض ساعة الموبايل والهاب وآخر مزامنة لكل مشترك.', 'The page shows the phone and hub clocks and the last sync of each strip.'),
                _tr('«زامن دلوقتي» بيبعت الوقت لكل المشتركات فوراً.', '"Sync now" sends the time to every strip at once.'),
              ]),
          _Item(Icons.history, _tr('سجل تشغيل المخرج', 'Outlet history'),
              _tr('كل دورة تشغيل لكل مخرج: وقتها ومدتها واستهلاكها وتكلفتها وإيه اللي شغّلها، لآخر 30 يوم. الهاب هو اللي بيسجّل، فالسجل بيكمل حتى لو التطبيق مقفول.',
                  'Every on/off cycle of every outlet: when, how long, energy, cost and what started it, for the last 30 days. The hub records it, so it keeps going while the app is closed.'),
              how: [(_G.hold, _tr('ضغطة مطولة على المخرج ← سجل التشغيل', 'Long-press an outlet → On/off history'))],
              steps: [
                _tr('الخط الزمني بيبدأ من 00 على الشمال، وتحته جراف الاستهلاك اليومي.', 'The timeline starts at 00 on the left, with the daily energy below it.'),
                _tr('«تصدير» بيعمل PDF أو CSV أو صورة للرسم.', '"Export" makes a PDF, a CSV or an image of the chart.'),
              ]),
          _Item(Icons.bolt, _tr('السيناريوهات', 'Scenarios'),
              _tr('لو حصل كذا (قراءة فوق أو تحت حد، مخرج اشتغل أو فصل، ميعاد، الكهربا رجعت بعد انقطاع، النت وقع) وبشرط معيّن، اعمل إجراءات: شغّل أو اطفي أو استنى أو أعد تشغيل أو اقفل أو ابعت إشعار. وإلا اعمل حاجة تانية.',
                  'When something happens (a reading above or below a limit, an outlet goes on or off, a time, the power is back after a cut, the internet is down), and a condition holds, do actions: switch on or off, wait, restart, lock or notify. Otherwise do something else.'),
              how: [(_G.go, _tr('الإعدادات ← السيناريوهات', 'Settings → Scenarios'))],
              steps: [
                _tr('فيه قوالب جاهزة: الشاحن اكتمل، بعد انقطاع الكهربا، السخان، الراوتر.', 'Ready templates: charger finished, after a power cut, heater, router.'),
                _tr('السيناريوهات بتنفذ في الهاب، فبتوقف لو الهاب فاصل.', 'Scenarios run on the hub, so they pause while the hub is offline.'),
              ]),
          _Item(Icons.router_outlined, _tr('أكتر من هاب', 'More than one hub'),
              _tr('ضيف هابات في بيوت أو شبكات مختلفة، واسم لكل واحد، وخلّي واحد أساسي يفتح عليه التطبيق. الشريحة اللي فوق في الرئيسية بتبدّل بينهم.',
                  'Add hubs in different homes or networks, name each one and make one primary: the app opens on it. The chip at the top of Home switches between them.'),
              how: [(_G.go, _tr('الإعدادات ← الهابات', 'Settings → Hubs'))]),
          _Item(Icons.lock_outline, _tr('تشفير النسخة الاحتياطية', 'Backup encryption'),
              _tr('الملف بيتشفّر بـ AES-256 بباسورد بتكتبه مرة واحدة ويتحفظ في تخزين الموبايل الآمن، وتقدر تفتحه بالبصمة. على موبايل جديد هتكتب الباسورد.',
                  'The file is sealed with AES-256 using a password you type once, kept in the phone\'s secure storage and optionally opened with your fingerprint. On a new phone you type it.'),
              how: [(_G.go, _tr('الإعدادات ← المزامنة والنسخ الاحتياطي', 'Settings → Sync and backup'))]),
          _Item(Icons.sync, _tr('إيه اللي يتزامن', 'What to sync'),
              _tr('اختار اللي يتحط في نسخة جوجل: الأسماء، الأيقونات، الغرف والسيناريوهات، المواعيد والأتمتة، الحماية والقفل، سجل الاستهلاك، العيلة، الإشعارات، البصمة، وإعدادات التطبيق.',
                  'Choose what goes into the Google copy: names, icons, rooms and scenes, schedules and automations, protection and locks, usage history, family, notifications, fingerprint and app settings.'),
              how: [(_G.go, _tr('الإعدادات ← المزامنة والنسخ الاحتياطي', 'Settings → Sync and backup'))]),
          _Item(Icons.swipe, _tr('السحب بين التابات', 'Swipe between tabs'),
              _tr('اسحب يمين أو شمال على أي صفحة رئيسية عشان تنتقل للتاب اللي جنبها.', 'Swipe left or right on any main page to move to the next tab.')),
        ]),
        _Sec(_tr('الاستهلاك والإشعارات', 'Energy and notifications'), [
          _Item(Icons.insights, _tr('الطاقة', 'Energy'),
              _tr('استهلاك وتكلفة كل مشترك ومخرج لحد 90 يوم، وأعلى حمل بوقته. زرار التنزيل فوق بيصدّر تقرير بالفترة والفلتر اللي مختارهم.', 'Usage and cost per strip and outlet for up to 90 days, with the peak load and its time. The download button on top exports a report of the chosen period and filter.'),
              how: [(_G.go, _tr('تبويب الطاقة', 'Energy tab')), (_G.tap, _tr('زرار التنزيل: تصدير تقرير', 'Download button: export a report'))]),
          _Item(Icons.notifications_outlined, _tr('الإشعارات', 'Notifications'),
              _tr('«إشعاراتي» فيها الأنواع اللي مفعّلها بس، و«سجل النظام» فيه أحداث الـ Hub بفلاتر. النوع المقفول مش بيظهر في أي مكان.', '"My notifications" holds only the types you enabled; "System log" has hub events with filters. A disabled type shows nowhere.'),
              how: [(_G.tap, _tr('الجرس في الرئيسية', 'Bell on Home')), (_G.go, _tr('الإعدادات ← الإشعارات', 'Settings → Notifications'))]),
        ]),
        _Sec(_tr('الحساب والتحديثات', 'Account and updates'), [
          _Item(Icons.phonelink_lock_outlined, _tr('قفل الهاب', 'Hub lock'),
              _tr('من غير القفل أي حد على واي فاي البيت يقدر يتحكم في مشتركاتك. بعد القفل، أي تليفون جديد لازم توافق عليه.', 'Without the lock anyone on the home Wi-Fi can control your strips. Once locked, every new phone needs your approval.'),
              how: [(_G.go, _tr('الإعدادات ← قفل الهاب', 'Settings → Hub lock'))],
              steps: [
                _tr('سجّل بحساب جوجل، وادخل الإعدادات ← قفل الهاب.', 'Sign in with Google and open Settings → Hub lock.'),
                _tr('اكتب باسورد تحديث الهاب (OTA) واقفله. ده مرة واحدة بس.', 'Enter the hub update (OTA) password and lock it. Only once.'),
                _tr('أي تليفون جديد يسجل بجيميل ويدوس "اطلب دخول"، فيظهر عليه رقم.', 'A new phone signs in with Google and taps "Ask for access"; it shows a number.'),
                _tr('على تليفونك هتظهر رسالة: اختار نفس الرقم وحدد الصلاحية (تحكم أو مشاهدة).', 'On your phone a sheet opens: pick the same number and choose the role (control or view).'),
                _tr('غيّرت تليفونك؟ سجّل بنفس الجيميل، واسترجع النسخة من Drive أو اختار "أنا صاحب الهاب".', 'New phone? Sign in with the same Google account and restore from Drive, or choose "I own this hub".'),
              ]),
          _Item(Icons.group_outlined, _tr('مشاركة العائلة', 'Family sharing'),
              _tr('كل فرد بيشوف اللي من صلاحيته بس، وصفحة العيلة بتعرض صورة وإيميل كل واحد.', 'Everyone sees only what their role allows; the family page shows each member\'s photo and email.'),
              how: [(_G.go, _tr('الإعدادات ← مشاركة العائلة', 'Settings → Family sharing'))],
              steps: [
                _tr('مشاهدة: يشوف كل حاجة (المشتركات والجداول والأتمتة والطاقة) من غير ما يغيّر.', 'View: sees everything (strips, schedules, automations, energy) without changing anything.'),
                _tr('تشغيل وتحكم: يشغّل ويطفي ويعمل تايمر وجدولة، من غير الحمايات والمخارج المحمية.', 'Control: switches, timers and schedules, but not protections or protected outlets.'),
                _tr('إدارة كاملة: كمان الواي فاي وتحديث الـ Hub والمشتركات والأتمتة والحمايات والمزامنة.', 'Full admin: also Wi-Fi, hub and strip updates, automations, protections and sync.'),
                _tr('من «تعديل» تقدر تدي أي فرد صلاحيات إضافية: الأتمتة، الحمايات، تحديث المشتركات أو الـ Hub، الواي فاي، تصدير التقارير.', 'From "Edit" you can give anyone extra permissions: automations, protections, strip or hub updates, Wi-Fi, report export.'),
              ]),
          _Item(Icons.cloud_sync_outlined, _tr('النسخ الاحتياطي', 'Backup'),
              _tr('نسخة من الإعدادات والأسماء على Google Drive، وترجّعها في أي وقت.', 'A copy of settings and names on Google Drive, restorable any time.'),
              how: [(_G.go, _tr('الإعدادات ← النسخ الاحتياطي والاستعادة', 'Settings → Backup & restore'))]),
          _Item(Icons.system_update_alt, _tr('تحديث فيرموير الـ Hub', 'Hub firmware update'),
              _tr('اختار ملف الـ Hub وارفعه من الموبايل، والـ Hub يعيد التشغيل لوحده. لازم تكون على واي فاي البيت.', 'Pick the hub file and upload it from the phone; the hub restarts itself. You must be on the home Wi-Fi.'),
              how: [(_G.go, _tr('الإعدادات ← تحديث فيرموير الـ Hub', 'Settings → Update hub firmware'))]),
          _Item(Icons.electrical_services, _tr('تحديث فيرموير المشتركات', 'Strip firmware update'),
              _tr('ارفع ملف المشترك (أو حط رابط مباشر والـ Hub يجيبه لوحده بدون ما يعدّي على التليفون) واختار المشتركات، والـ Hub يحدّثهم واحد واحد ويتأكد من النسخة بعد كل واحد.',
                  'Upload the strip file (or give a direct link and the hub fetches it itself, never touching the phone) and pick the strips; the hub updates them one at a time and checks each version.'),
              how: [(_G.go, _tr('الإعدادات ← تحديث فيرموير المشتركات', 'Settings → Update strip firmware'))],
              warning: _sfwWarning),
        ]),
      ];

  bool _match(_Item it) {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [it.title, it.summary, ...it.steps, ...it.how.map((h) => h.$2)].any((s) => s.toLowerCase().contains(q));
  }

  Widget _chip(_G g, String label) {
    final (Color c, String def) = switch (g) {
      _G.tap => (C.accent, _tr('ضغطة', 'Tap')),
      _G.hold => (C.warn, _tr('ضغطة مطولة', 'Hold')),
      _G.slide => (C.blue, _tr('سحب', 'Slide')),
      _G.go => (C.textSoft, ''),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: g == _G.go ? C.surface2 : c.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label.isEmpty ? def : label, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  Widget _row(_Item it, bool last) {
    final searching = _q.trim().isNotEmpty;
    final open = searching || _open.contains(it.title);
    return Container(
      decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: C.border))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: searching ? null : () => setState(() => open ? _open.remove(it.title) : _open.add(it.title)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: it.warning != null ? C.warn.withValues(alpha: .12) : C.accentBg, borderRadius: BorderRadius.circular(10)),
                child: Icon(it.icon, size: 18, color: it.warning != null ? C.warn : C.accent),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(it.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
              AnimatedRotation(
                turns: open ? .5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(Icons.expand_more, color: C.faint),
              ),
            ]),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: !open
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(58, 0, 14, 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(it.summary, style: TextStyle(color: C.textSoft, fontSize: 13, height: 1.65)),
                    if (it.how.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, runSpacing: 6, children: [for (final (g, l) in it.how) _chip(g, l)]),
                    ],
                    for (var i = 0; i < it.steps.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(
                            width: 20,
                            height: 20,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(6)),
                            child: Text('${i + 1}', style: TextStyle(color: C.accent, fontSize: 11, fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(it.steps[i], style: TextStyle(color: C.textSoft, fontSize: 12.5, height: 1.6))),
                        ]),
                      ),
                    if (it.warning != null) ...[
                      const SizedBox(height: 10),
                      _warnBox(it.warning!),
                    ],
                  ]),
                ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final secs = [
      for (final s in _secs)
        if (s.items.any(_match)) _Sec(s.title, s.items.where(_match).toList()),
    ];
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: C.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(_tr('دليل الاستخدام', 'User guide'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(18, 4, 18, 28), children: [
          TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: InputDecoration(
              hintText: _tr('ابحث: إضافة، جدولة، بصمة، 3500…', 'Search: add, schedule, fingerprint, 3500…'),
              prefixIcon: Icon(Icons.search, color: C.muted),
              filled: true,
              fillColor: C.surface2,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: C.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: C.border)),
            ),
          ),
          if (secs.isEmpty)
            Padding(
              padding: const EdgeInsets.all(28),
              child: Text(_tr('مفيش نتايج', 'No results'), textAlign: TextAlign.center, style: TextStyle(color: C.muted)),
            ),
          for (final s in secs) ...[
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(4, 18, 4, 8),
              child: Text(s.title, style: TextStyle(fontSize: 13, color: C.muted, fontWeight: FontWeight.w600)),
            ),
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: cardBox(),
              child: Column(children: [for (var i = 0; i < s.items.length; i++) _row(s.items[i], i == s.items.length - 1)]),
            ),
          ],
        ]),
      ),
    );
  }
}

/// The strip-firmware disclaimer, shared with the strip firmware screen.
Widget _warnBox(String text) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: C.warn.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: C.warn.withValues(alpha: .35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.warning_amber_rounded, color: C.warn, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: C.textSoft, fontSize: 12.5, height: 1.65))),
      ]),
    );

/// Public entry for the strip firmware screen.
Widget stripFwDisclaimer() => _warnBox(_ManualScreenState._sfwWarning);
