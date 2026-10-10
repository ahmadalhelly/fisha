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
      'تنبيه: فيرموير المشترك تعديل غير رسمي على فيرموير الشركة، والتحديث على مسؤوليتك. لو الكهربا أو الواي فاي قطعت وقت التحديث، المشترك ممكن يبطّل يشتغل ويحتاج إصلاح يدوي، وممكن يلغي ضمان الشركة. استخدم الملفات اللي من إصدارات فيشة بس، وجرّب على مشترك واحد الأول، وماتفصلش المشترك ولا الـ Hub لحد ما يخلص.',
      'Warning: strip firmware is an unofficial modification of the maker\'s firmware, and you update at your own risk. If power or Wi-Fi drops during an update, the strip may stop working and need a manual repair, and it may void the maker\'s warranty. Use only files from Fisha releases, try one strip first, and keep the strip and the hub powered until it finishes.');

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
        _Sec(_tr('الاستهلاك والإشعارات', 'Energy and notifications'), [
          _Item(Icons.insights, _tr('الطاقة', 'Energy'),
              _tr('استهلاك وتكلفة كل مشترك ومخرج لحد 90 يوم، وأعلى حمل بوقته.', 'Usage and cost per strip and outlet for up to 90 days, with the peak load and its time.'),
              how: [(_G.go, _tr('تبويب الطاقة', 'Energy tab'))]),
          _Item(Icons.notifications_outlined, _tr('الإشعارات', 'Notifications'),
              _tr('«إشعاراتي» فيها الأنواع اللي مفعّلها بس، و«سجل النظام» فيه أحداث الـ Hub بفلاتر. النوع المقفول مش بيظهر في أي مكان.', '"My notifications" holds only the types you enabled; "System log" has hub events with filters. A disabled type shows nowhere.'),
              how: [(_G.tap, _tr('الجرس في الرئيسية', 'Bell on Home')), (_G.go, _tr('الإعدادات ← الإشعارات', 'Settings → Notifications'))]),
        ]),
        _Sec(_tr('الحساب والتحديثات', 'Account and updates'), [
          _Item(Icons.group_outlined, _tr('مشاركة العائلة', 'Family sharing'),
              _tr('حسابات للعائلة بصلاحية مشاهدة أو تحكم أو إدارة، لمشتركات معيّنة.', 'Family accounts with view, control or admin rights for chosen strips.'),
              how: [(_G.go, _tr('الإعدادات ← مشاركة العائلة', 'Settings → Family sharing'))]),
          _Item(Icons.cloud_sync_outlined, _tr('النسخ الاحتياطي', 'Backup'),
              _tr('نسخة من الإعدادات والأسماء على Google Drive، وترجّعها في أي وقت.', 'A copy of settings and names on Google Drive, restorable any time.'),
              how: [(_G.go, _tr('الإعدادات ← النسخ الاحتياطي والاستعادة', 'Settings → Backup & restore'))]),
          _Item(Icons.system_update_alt, _tr('تحديث فيرموير الـ Hub', 'Hub firmware update'),
              _tr('اختار ملف الـ Hub وارفعه من الموبايل، والـ Hub يعيد التشغيل لوحده. لازم تكون على واي فاي البيت.', 'Pick the hub file and upload it from the phone; the hub restarts itself. You must be on the home Wi-Fi.'),
              how: [(_G.go, _tr('الإعدادات ← تحديث فيرموير الـ Hub', 'Settings → Update hub firmware'))]),
          _Item(Icons.electrical_services, _tr('تحديث فيرموير المشتركات', 'Strip firmware update'),
              _tr('ارفع ملف المشترك واختار المشتركات، والـ Hub يحدّثهم واحد واحد ويتأكد من النسخة بعد كل واحد.', 'Upload the strip file and pick the strips; the hub updates them one at a time and checks each version.'),
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
