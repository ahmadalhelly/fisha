import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'settings_screen.dart' show appVersion;

String _tr(String ar, String en) => Tr.isAr ? ar : en;

/// About Fisha: versions, what the latest update brought, and what the app can do.
class AboutScreen extends StatelessWidget {
  final AppState state;
  const AboutScreen({super.key, required this.state});

  static List<(IconData, String, String)> get _latest => [
        (Icons.admin_panel_settings_outlined, _tr('صلاحيات العيلة', 'Family permissions'),
            _tr('كل فرد بيشوف اللي من صلاحيته بس: مشاهدة، تشغيل وتحكم، أو إدارة كاملة، والمالك يقدر يدي صلاحيات زيادة لأي حد.', 'Everyone sees only what their role allows: view, control or full admin, and the owner can grant extra permissions.')),
        (Icons.account_circle_outlined, _tr('صورة حساب جوجل', 'Google account photo'),
            _tr('صورتك واسمك وإيميلك فوق الإعدادات، وصفحة العيلة بتعرض صورة وإيميل كل فرد.', 'Your photo, name and email at the top of Settings; the family page shows each member\'s photo and email.')),
        (Icons.wifi_tethering, _tr('نقل الشبكة أوتوماتيك', 'Automatic network move'),
            _tr('لما تغيّر الواي فاي من التطبيق، الـ Hub بيبعت الشبكة الجديدة للمشتركات وينقلوا معاه.', 'When you change the Wi-Fi in the app, the hub hands the new network to the strips and they move with it.')),
        (Icons.cloud_download_outlined, _tr('تحديث المشتركات من مركز التحديثات', 'Strip updates in the update center'),
            _tr('الـ Hub بيجيب آخر فيرموير للمشتركات بنفسه من غير ما الملف يعدّي على موبايلك.', 'The hub fetches the latest strip firmware itself; the file never passes through your phone.')),
        (Icons.file_download_outlined, _tr('تصدير تقارير الاستهلاك', 'Export energy reports'),
            _tr('من صفحة الطاقة: ملف بالاستهلاك والتكلفة لكل يوم ومشترك ومخرج.', 'From the energy page: a file with use and cost per day, strip and outlet.')),
        (Icons.lock_outline, _tr('قفل الأطفال مع زرار المشترك', 'Child lock with the strip button'),
            _tr('زرار المشترك الرئيسي بيشغّل المخارج الحرة حتى لو فيه مخرج مقفول.', 'The strip\'s master button switches the free outlets even with one outlet locked.')),
        (Icons.phonelink_lock_outlined, _tr('قفل الهاب', 'Hub lock'),
            _tr('الهاب يتقفل على تليفونك بحساب جوجل، وأي تليفون جديد يطلب دخول وإنت توافق باختيار الرقم اللي ظاهر عنده (Hub 2.15.13).', 'The hub locks to your phone with your Google account; a new phone asks in and you approve by picking the number it shows (Hub 2.15.13).')),
        (Icons.cloud_download_outlined, _tr('مركز التحديثات', 'Update center'),
            _tr('في الإعدادات: آخر نسخة من الهاب والتطبيق، وتحديث كل واحد بزرار، وسجل الإصدارات بملاحظاتها.', 'In Settings: the latest hub and app builds, one-tap updates, and every release with its notes.')),
        (Icons.stacked_bar_chart, _tr('جراف طاقة جديد', 'New energy chart'),
            _tr('عمود لكل يوم متقسّم بلون كل مشترك أو مخرج، وخط للمتوسط، والتكلفة الإجمالية فوق، وتكلفة كل مشترك ومخرج.', 'One bar per day split by strip or outlet colour, an average line, the total cost on top, and the cost of each strip and outlet.')),
        (Icons.help_outline, _tr('دليل الاستخدام', 'User guide'),
            _tr('في الإعدادات ← مساعدة: كل ميزة وطريقة تشغيلها باختصار، مع بحث.', 'In Settings → Help: every feature and how to use it, briefly, with search.')),
        (Icons.swipe, _tr('سحب مفتاح الباور', 'Slide the master switch'),
            _tr('اضغط مطوّل على المفتاح الرئيسي واسحب يمين لتشغيل الكل أو شمال لإيقاف الكل، وارفع صباعك في النص تلغي.', 'Hold the master switch, slide right for all on or left for all off; lift in the middle to cancel.')),
        (Icons.wifi, _tr('كارت الشبكة والاتصال', 'Network & connection card'),
            _tr('في إعدادات كل مشترك: نسبة الاتصال والانقطاعات والإشارة لآخر 7 أيام، يوم بيوم (Hub 2.15.10).', 'In each strip\'s settings: uptime, drops and signal for the last 7 days, day by day (hub 2.15.10).')),
        (Icons.gpp_good_outlined, _tr('حماية أقوى من الـ Hub', 'Stronger hub protection'),
            _tr('فصل عند 3500 وات لكل مشترك، فصل فوري لما القراية تبعد جداً عن الحد، والـ Hub بيتأكد إن المخرج اتقفل ويعيد الأمر (Hub 2.15.9).', 'A 3500 W cut per strip, instant cuts far past a limit, and the hub checks the outlet really went off and resends (hub 2.15.9).')),
        (Icons.notifications_active_outlined, _tr('إشعارات الحماية دايماً', 'Safety alerts always on'),
            _tr('فصل الفولت والتيار والحمل بيوصلك حتى لو المشترك مكتوم.', 'Voltage, current and load cuts reach you even when the strip is muted.')),
        (Icons.notifications_outlined, _tr('إشعاراتي وسجل النظام', 'My notifications and system log'),
            _tr('إشعاراتي فيها اللي مفعّله بس ومتقسّمة بالأيام، وسجل الـ Hub لوحده بفلاتر. المقفول مش بيظهر في أي مكان.', 'My notifications shows only what you enabled, grouped by day; the hub log is separate with filters. Disabled types show nowhere.')),
        (Icons.insights, _tr('صفحة طاقة جديدة', 'New energy page'),
            _tr('ترتيب أوضح، النسبة ودلوقتي وأعلى حمل لكل مخرج، واليوم اللي ملوش بيانات بيفضل ظاهر.', 'Clearer layout; share, now and peak per outlet; days with no data stay visible.')),
        (Icons.system_update_alt, _tr('تحديث فيرموير المشتركات', 'Strip firmware updates'),
            _tr('الـ Hub بيحدّث المشتركات واحد واحد من غير زرار، وبيتأكد من النسخة بعد كل واحد (Hub 2.15.8).', 'The hub updates strips one at a time without a button press and checks each version (hub 2.15.8).')),
        (Icons.lan_outlined, _tr('عنوان IP لكل مشترك', 'IP of each strip'), _tr('في قسم الجهاز في إعدادات المشترك.', 'In the device section of the strip settings.')),
        (Icons.electric_bolt, _tr('الأمبير برقمين عشريين', 'Amps with 2 decimals'), _tr('عشان الأحمال الصغيرة تبان.', 'So small loads show.')),
        (Icons.auto_awesome, _tr('شاشة بداية جديدة', 'New splash screen'), _tr('حركة خفيفة للشعار.', 'A light logo animation.')),
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
            kv(_tr('فيرموير الـ Hub', 'Hub firmware'), state.hubFw == null ? '—' : 'v${state.hubFw}'),
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
