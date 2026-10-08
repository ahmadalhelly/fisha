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
        (Icons.exposure, _tr('شريط − و + للقيم', 'A − / + bar for values'),
            _tr('الأمبير والفولت والحرارة بشريط − و +، ودوس على الرقم تكتبه. واقتراح ذكي لحد الأمبير.', 'Amps, volts and temperature use a − / + bar; tap the number to type it. Plus a smart amp-limit suggestion.')),
        (Icons.bolt, _tr('حماية الفولت العالي إجبارية', 'Over-voltage cut always on'),
            _tr('لو الفولت عدّى الحد المشترك كله بيقفل حتى المخارج المحمية (Hub 2.14).', 'Above the limit the whole strip shuts off, protected outlets too (hub 2.14).')),
        (Icons.touch_app_outlined, _tr('ضغط مطول على الأتمتة', 'Long-press automations'), _tr('تعديل ونسخة وحذف، والقاعدة من غير اسم بتظهر باسم المشترك.', 'Edit, duplicate or delete; unnamed rules show the strip name.')),
        (Icons.gradient, _tr('ألوان متحركة', 'Moving colours'), _tr('الوات والحرارة في الهيدر والبار العائم بيتلونوا حسب الحمل والحرارة.', 'Watts and temperature in the header and floating bar take colour from load and heat.')),
        (Icons.insights, _tr('استهلاك كل مخرج والـ Peak', 'Per-outlet use and peak'),
            _tr('صفحة الطاقة بفلتر للمشترك والمخرج، ونسبة كل مخرج، وأعلى حمل بوقته.', 'Energy page with strip and outlet filters, each outlet\'s share and peak with its time.')),
        (Icons.meeting_room_outlined, _tr('الغرف زي المشترك', 'Rooms act like strips'),
            _tr('تشغيل وإيقاف، جدولة، أتمتة، إعادة تشغيل، تكرار، بصمة وإشعارات للغرفة كلها.', 'On/off, schedules, automations, power-cycle, loop, fingerprint and notifications per room.')),
        (Icons.blur_on, _tr('ثيمات زجاجية', 'Glass themes'), _tr('Midnight وPearl بقوا الأساسيين حسب وضع الموبايل.', 'Midnight and Pearl are now the defaults, following the phone.')),
        (Icons.donut_large, _tr('هالة الاستهلاك', 'Load halo'),
            _tr('المخرج والمشترك بيقلبوا برتقالي من 70% وأحمر من 90% من 3500 وات.', 'Outlets and strips turn orange from 70% and red from 90% of 3500 W.')),
        (Icons.family_restroom, _tr('مشاركة العائلة', 'Family sharing'), _tr('أفراد العائلة بيتحكموا محلي وكلاود.', 'Family members control locally and through the cloud.')),
        (Icons.pin, _tr('أرقام إنجليزي', 'Western digits'), _tr('كل الأرقام في التطبيق 0-9.', 'Every number in the app uses 0-9.')),
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
        (Icons.system_update_alt, _tr('تحديث فيرموير الـ Hub من الموبايل', 'Hub firmware updates from the phone')),
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
