import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'settings_screen.dart' show appVersion, appBuild;

String _tr(String ar, String en) => Tr.isAr ? ar : en;

/// About Fisha: versions, what the latest update brought, and what the app can do.
class AboutScreen extends StatelessWidget {
  final AppState state;
  const AboutScreen({super.key, required this.state});

  /// the titles of the latest update, for the one-time "what's new" box
  static List<String> get latestTitles => [for (final (_, title, _) in _latest) title];

  static List<(IconData, String, String)> get _latest => [
        (Icons.swipe, _tr('السحب يمين وشمال', 'Swipe left and right'),
            _tr('اسحب على أي صفحة رئيسية عشان تنتقل للتاب اللي جنبها، وفي الإشعارات بين «إشعاراتي» و«سجل النظام».', 'Swipe on any main page to move to the next tab, and in notifications between "My notifications" and "System log".')),
        (Icons.shield_outlined, _tr('حدود الحماية جوه المشترك', 'Protection limits inside the strip'),
            _tr('الوات والأمبير والفولت الأقل والأعلى والحرارة ومهلة الفصل من الإعدادات ← حدود الحماية. بتتحفظ في المشترك وبتفصل حتى لو الهاب مطفي.', 'Watts, amps, low and high voltage, temperature and the trip delay under Settings → Protection limits. They are saved in the strip and cut even when the hub is off.')),
        (Icons.event_repeat, _tr('الجدولة من غير الهاب', 'Schedules without the hub'),
            _tr('المشترك بينفذ أقرب ميعاد جاي بأيام الأسبوع وهو فاصل عن الهاب. الهاب بيبعتله الميعاد والساعة أول ما تحفظ.', 'The strip runs the next weekday schedule by itself while away from the hub. The hub sends it and the clock as soon as you save.')),
        (Icons.history, _tr('سجل تشغيل المخرج بشكل جديد', 'A new outlet history'),
            _tr('أسماء المخارج، والوقت بالعربي، ومواعيد التشغيل والاستهلاك اليومي في كروت واضحة، وتصدير PDF وصورة بالألوان.', 'Outlet names, clear times, on times and daily energy in their own cards, and colour PDF and image export.')),
        (Icons.bolt, _tr('السيناريوهات', 'Scenarios'),
            _tr('من الرئيسية: لو حصل كذا وبشرط كذا اعمل كذا، وإلا اعمل حاجة تانية. بأسماء مخارجك وقوالب جاهزة.', 'From Home: when something happens and a condition holds, do actions, otherwise do others. With your outlet names and ready templates.')),
        (Icons.public, _tr('الوقت والمنطقة الزمنية', 'Time and time zone'),
            _tr('التوقيت الصيفي تلقائي، وساعة الموبايل والهاب وكل مشترك، وزرار «زامن دلوقتي». وكل الأوقات بقت 12 ساعة.', 'Automatic summer time, the clocks of the phone, hub and each strip, and a "Sync now" button. All times are 12-hour.')),
        (Icons.router_outlined, _tr('أكتر من هاب', 'More than one hub'),
            _tr('اسم لكل هاب، وهاب أساسي، وتبديل من الرئيسية، وإضافة هاب جديد بالبحث عنه.', 'A name for each hub, a primary hub, switching from Home, and adding a new hub by searching for it.')),
        (Icons.system_update_alt, _tr('مركز التحديثات', 'Update center'),
            _tr('رقم البيلد جنب كل نسخة، ونسخة كل هاب عندك وزرار «بدّل وحدّث»، ورسالة بأهم الجديد بعد كل تحديث.', 'The build number next to every version, the version of each of your hubs with "Switch and update", and a note with the main news after each update.')),
        (Icons.lock_outline, _tr('تشفير النسخة الاحتياطية', 'Encrypted backups'),
            _tr('باسورد محفوظ في الموبايل وبصمة، واختيار إيه اللي يتزامن مع جوجل.', 'A password kept on the phone and your fingerprint, and a choice of what syncs with Google.')),
        (Icons.child_care, _tr('قفل الأطفال وإعادة التشغيل', 'Child lock and outlet restart'),
            _tr('قفل أزرار المشترك وإعادة تشغيل المخرج بعد مدة، والاتنين بيشتغلوا حتى من غير الهاب.', 'Locking the strip buttons and restarting an outlet after a delay, both working even without the hub.')),
        (Icons.devices_other, _tr('أتمتة لكل المشتركات وأيقونات جديدة', 'Automation for every strip and new icons'),
            _tr('قاعدة واحدة تشتغل على كل المشتركات، وأيقونات راوتر ومودم وسويتش.', 'One rule that covers every strip, and router, modem and switch icons.')),
      ];

  static List<(IconData, String)> get _features => [
        (Icons.power_settings_new, _tr('تحكم في كل مخرج والمشترك كله، محلي أو من برا البيت', 'Control each outlet or the whole strip, locally or remotely')),
        (Icons.bolt, _tr('قياس الوات والأمبير والفولت والحرارة لحظة بلحظة', 'Live watts, amps, volts and temperature')),
        (Icons.schedule, _tr('جداول ومؤقتات وتكرار وإعادة تشغيل', 'Schedules, timers, loops and power-cycles')),
        (Icons.shield_outlined, _tr('حماية من الفولت والأمبير والحرارة، وحد أمبير لكل مخرج', 'Voltage, current and temperature protection, plus a per-outlet amp limit')),
        (Icons.lock_outline, _tr('حماية الراوتر وقفل الأطفال والبصمة', 'Router protection, child lock and fingerprint')),
        (Icons.bar_chart, _tr('استهلاك وتكلفة لـ 90 يوم', '90 days of energy and cost')),
        (Icons.notifications_outlined, _tr('إشعارات لحظية', 'Instant notifications')),
        (Icons.cloud_sync_outlined, _tr('نسخ احتياطي ومزامنة مع Google', 'Backup and Google sync')),
        (Icons.system_update_alt, _tr('تحديث فيرموير الـ Hub والمشتركات من الموبايل', 'Hub and strip firmware updates from the phone')),
        (Icons.wifi, _tr('سجل اتصال كل مشترك لآخر 7 أيام', '7-day link history for each strip')),
        (Icons.meeting_room_outlined, _tr('غرف وأتمتة ومشاركة مع العائلة', 'Rooms, automations and family sharing')),
      ];

  @override
  Widget build(BuildContext context) {
    Widget card(List<Widget> children) => Container(
          padding: const EdgeInsets.all(16),
          decoration: cardBox(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        );
    Widget head(String s) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(s, style: TextStyle(fontSize: 13, color: C.muted, fontWeight: FontWeight.w600)),
        );
    Widget kv(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text(k, style: TextStyle(color: C.textSoft))),
            Text(v, textDirection: TextDirection.ltr, style: mono(13)),
          ]),
        );
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: C.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(_tr('عن التطبيق', 'About'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 28), children: [
          Column(children: [
            const BrandMark(size: 64),
            const SizedBox(height: 8),
            Text('${t('app_name')} · Fisha', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            Text(t('by'), textDirection: TextDirection.ltr, style: TextStyle(color: C.warn, fontSize: 13, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 18),
          card([
            kv(_tr('إصدار التطبيق', 'App version'), appVersion),
            kv(_tr('رقم البناء', 'Build number'), appBuild > 0 ? '$appBuild' : '—'),
            kv(_tr('فيرموير الـ Hub', 'Hub firmware'), state.hubFw == null ? '—' : 'v${state.hubFw}${state.hubBuild > 0 ? ' (${_tr('بناء', 'build')} ${state.hubBuild})' : ''}'),
            kv(_tr('المشتركات', 'Strips'), '${state.strips.length}'),
          ]),
          const SizedBox(height: 14),
          card([
            head(_tr('الجديد في آخر تحديث', 'New in this update')),
            for (final (icon, title, sub) in _latest)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(color: C.accentBg, borderRadius: BorderRadius.circular(10)),
                    child: Icon(icon, size: 18, color: C.accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(sub, style: TextStyle(color: C.muted, fontSize: 12.5, height: 1.5)),
                    ]),
                  ),
                ]),
              ),
          ]),
          const SizedBox(height: 14),
          card([
            head(_tr('المميزات', 'Features')),
            for (final (icon, text) in _features)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  Icon(icon, size: 18, color: C.accent),
                  const SizedBox(width: 12),
                  Expanded(child: Text(text, style: TextStyle(color: C.textSoft, height: 1.4))),
                ]),
              ),
          ]),
        ]),
      ),
    );
  }
}
