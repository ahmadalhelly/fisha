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
        (Icons.public, _tr('الوقت والمنطقة الزمنية', 'Time and time zone'),
            _tr('صفحة جديدة بالتوقيت الصيفي التلقائي، وساعة الموبايل والهاب وكل مشترك، وزرار مزامنة.', 'A new page with automatic summer time, the clocks of the phone, hub and each strip, and a sync button.')),
        (Icons.history, _tr('سجل تشغيل المخرج', 'Outlet history'),
            _tr('كل دورة تشغيل بوقتها واستهلاكها وتكلفتها، بجراف وتصدير PDF وCSV وصورة.', 'Every cycle with its time, energy and cost, with a chart and PDF, CSV and image export.')),
        (Icons.bolt, _tr('السيناريوهات', 'Scenarios'),
            _tr('لو / بشرط / إفعل / وإلا، منها «الكهربا رجعت بعد انقطاع» و«النت وقع».', 'If / when / do / otherwise, including "the power is back" and "the internet is down".')),
        (Icons.router_outlined, _tr('أكتر من هاب', 'More than one hub'),
            _tr('أسماء لكل هاب، وهاب أساسي، وتبديل من الرئيسية.', 'A name for each hub, a primary hub and switching from Home.')),
        (Icons.lock_outline, _tr('تشفير النسخة الاحتياطية وإيه اللي يتزامن', 'Backup encryption and what to sync'),
            _tr('AES-256 بباسورد محفوظ وبصمة، واختيار ما يتزامن مع جوجل.', 'AES-256 with a saved password and fingerprint, and a choice of what syncs with Google.')),
        (Icons.swipe, _tr('السحب بين التابات وأيقونات الشبكة', 'Tab swipe and network icons'),
            _tr('اسحب بين التابات. وأيقونات جديدة للراوتر والمودم والسويتش، ولون هادي لإشارة الواي فاي.', 'Swipe between tabs. New router, modem and switch icons and a calmer Wi-Fi signal colour.')),
        (Icons.tune, _tr('حدود الحماية وأتمتة الهاب كله', 'Protection limits and hub-wide automation'),
            _tr('أقصى وات للمشترك مع الفولت والأمبير والحرارة في الإعدادات ← حدود الحماية، وقاعدة أتمتة واحدة تتنفذ على كل المشتركات.', 'A maximum wattage per strip with voltage, amps and temperature under Settings → Protection limits, and one automation rule that covers every strip.')),
        (Icons.child_care, _tr('قفل الأطفال', 'Child lock'),
            _tr('بتقفل الأزرار على المشترك نفسه أو على مخرج معيّن، والإعداد بيتحفظ جوه المشترك فيفضل شغال حتى لو الهاب أو النت فاصل.', 'Locks the buttons of the strip or of one outlet. It is stored inside the strip, so it works even when the hub or the internet is down.')),
        (Icons.shield_outlined, _tr('الحماية', 'Protection'),
            _tr('حد الوات ومهلة الفصل محفوظين جوه المشترك وبيشتغلوا حتى من غير الهاب، ومعاهم حماية ثابتة في المشترك عند 16 أمبير و80 درجة. حدود الفولت والأمبير والحرارة اللي بتختارها بينفذها الهاب، وبيتأكد إن المخرج اتقفل، والإشعار بيوصلك دايماً.', 'The watt limit and the trip delay are stored inside the strip and work without the hub, along with the strip\'s fixed 16 A and 80 °C protection. The voltage, current and temperature limits you choose are enforced by the hub, which checks the outlet really went off; the alert always reaches you.')),
        (Icons.restart_alt, _tr('إعادة تشغيل المخرج', 'Outlet restart'),
            _tr('فصل ورجوع بعد مدة تحددها، بزرار أو بتكرار مجدول. الدورة محفوظة جوه المشترك وبتكمل من غير الهاب.', 'Off, then back on after a delay you choose, by button or on a repeating schedule. The cycle is stored in the strip and keeps running without the hub.')),
        (Icons.schedule, _tr('الجدولة', 'Scheduling'),
            _tr('الهاب بينفذ كل الجداول والمؤقتات. وميعاد واحد بيتحفظ كمان جوه المشترك وبيتنفذ على ساعته لو الهاب فاصل، كل يوم، والهاب بيظبط له الساعة والتوقيت الصيفي لوحده.', 'The hub runs every schedule and timer. One time is also stored in the strip and runs on its own clock, every day, when the hub is offline; the hub keeps that clock set, summer time included.')),
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
