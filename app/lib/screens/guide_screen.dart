import 'package:flutter/material.dart';

import '../i18n.dart';
import '../theme.dart';

String _tr(String ar, String en) => Tr.isAr ? ar : en;

class _Step {
  final String title, body;
  final String? code;
  const _Step(this.title, this.body, [this.code]);
}

class _Part {
  final IconData icon;
  final String title, intro;
  final List<_Step> steps;
  const _Part(this.icon, this.title, this.intro, this.steps);
}

/// Setup guide: from an empty ESP32 to strips on the phone.
class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  List<_Part> get _parts => [
        _Part(Icons.checklist, _tr('المتطلبات', 'What you need'), _tr('قبل ما تبدأ جهّز الحاجات دي:', 'Get these ready first:'), [
          _Step(_tr('بورد ESP32', 'ESP32 board'), _tr('ESP32-WROOM-32 (ESP32 Dev Module) وكابل USB بيعدّي داتا مش شحن بس.', 'An ESP32-WROOM-32 (ESP32 Dev Module) and a USB data cable.')),
          _Step(_tr('كمبيوتر', 'A computer'), _tr('ويندوز أو ماك أو لينكس، عليه Arduino IDE 2. ده للمرة الأولى بس، بعدها التحديثات من التطبيق.', 'Windows, macOS or Linux with Arduino IDE 2 — only for the first flash; later updates come from the app.')),
          _Step(_tr('واي فاي 2.4GHz', '2.4 GHz Wi-Fi'), _tr('المشتركات والـ ESP32 مش بيشوفوا شبكات 5GHz. اسم الشبكة والباسورد مينفعش يكون فيهم علامة :', 'The strips and the ESP32 cannot see 5 GHz. The name and password must not contain ":".')),
          _Step(_tr('حساب سيرفر MQTT (للتحكم من برا البيت)', 'An MQTT server (for remote control)'),
              _tr('حساب مجاني على EMQX Cloud Serverless. هتعمل مستخدمين: واحد للـ Hub وواحد للتطبيق.', 'A free EMQX Cloud Serverless deployment with two users: one for the hub, one for the app.')),
          _Step(_tr('المشتركات', 'The strips'), _tr('LG U+ MTTL-W01. كل مشترك بيتضاف من التطبيق بعد ما الـ Hub يشتغل.', 'LG U+ MTTL-W01. Each strip is added from the app once the hub runs.')),
        ]),
        _Part(Icons.developer_board, _tr('تجهيز الـ ESP32 (Hub)', 'Prepare the ESP32 (hub)'), _tr('مرة واحدة بس من الكمبيوتر:', 'Once, from the computer:'), [
          _Step(_tr('1. نزّل Arduino IDE', '1. Install Arduino IDE'), _tr('من موقع arduino.cc ونصّبه.', 'From arduino.cc.')),
          _Step(_tr('2. ضيف بوردات ESP32', '2. Add the ESP32 boards'),
              _tr('File ← Preferences ← Additional boards manager URLs وحط اللينك ده، وبعدين Tools ← Board ← Boards Manager وابحث عن esp32 by Espressif ونصّبه (3.x).',
                  'File → Preferences → Additional boards manager URLs, paste this link, then Tools → Board → Boards Manager → install "esp32 by Espressif" (3.x).'),
              'https://espressif.github.io/arduino-esp32/package_esp32_index.json'),
          _Step(_tr('3. اختار البورد', '3. Pick the board'),
              _tr('Tools ← Board ← ESP32 Dev Module، وTools ← Partition Scheme ← Minimal SPIFFS (1.9MB APP with OTA). ده مهم عشان التحديث من التطبيق.',
                  'Tools → Board → ESP32 Dev Module, and Tools → Partition Scheme → Minimal SPIFFS (1.9MB APP with OTA). Needed for updates from the app.')),
          _Step(_tr('4. افتح ملف الفيرموير', '4. Open the firmware'), _tr('افتح mttl_hub.ino (لازم يكون جوه فولدر اسمه mttl_hub).', 'Open mttl_hub.ino (it must be inside a folder named mttl_hub).')),
          _Step(_tr('5. املا البيانات', '5. Fill in your details'),
              _tr('في أول الملف: اسم الشبكة WIFI_SSID وباسوردها WIFI_PASS، وباسورد السيرفر MQTT_PASS، وباسورد التحديث OTA_PASS. ولو شبكتك مش 192.168.1.x غيّر LOCAL_IP وGATEWAY.',
                  'At the top: WIFI_SSID / WIFI_PASS, MQTT_PASS and OTA_PASS. If your network is not 192.168.1.x, change LOCAL_IP and GATEWAY.'),
              'WIFI_SSID  WIFI_PASS  MQTT_PASS  OTA_PASS'),
          _Step(_tr('6. ارفع بالـ USB', '6. Upload over USB'),
              _tr('وصّل البورد، اختار الـ COM port من Tools ← Port، ودوس Upload. لو وقف عند Connecting… دوس زرار BOOT على البورد.', 'Plug it in, choose the COM port under Tools → Port and press Upload. If it stops at "Connecting…", hold the BOOT button.')),
          _Step(_tr('7. اتأكد إنه اشتغل', '7. Check it runs'),
              _tr('افتح Serial Monitor على 115200. هتشوف Fisha Hub وبعدها WiFi OK ومعاه الـ IP وبعدها [mqtt] connected.', 'Open Serial Monitor at 115200: you should see "Fisha Hub", then "WiFi OK" with the IP, then "[mqtt] connected".')),
          _Step(_tr('8. حطه في مكانه', '8. Place it'), _tr('أي شاحن USB عادي يكفي. خليه في مكان الواي فاي فيه كويس وقريب من المشتركات.', 'Any USB charger will do. Keep it where Wi-Fi is good and close to the strips.')),
        ]),
        _Part(Icons.phone_android, _tr('ربط التطبيق', 'Connect the app'), _tr('من الموبايل:', 'On the phone:'), [
          _Step(_tr('1. الاتصال المحلي', '1. Local connection'), _tr('الإعدادات ← الاتصال ← عنوان الـ Hub: نفس الـ IP اللي ظهر في الـ Serial (مثلاً 192.168.1.100).', 'Settings → Connection → hub address: the IP shown in Serial Monitor (e.g. 192.168.1.100).')),
          _Step(_tr('2. من برا البيت', '2. Away from home'), _tr('في نفس الصفحة: اسم مستخدم التطبيق وباسورده على السيرفر. الـ Hub ID وعنوان السيرفر تحت "إعدادات متقدمة".', 'Same page: the app user and password on the server. Hub ID and server host are under "Advanced".')),
          _Step(_tr('3. احفظ', '3. Save'), _tr('دوس "حفظ وإعادة الاتصال". فوق في الرئيسية لازم يظهر "محلي" أو "عن بُعد".', 'Tap "Save & reconnect". The home screen should show "Local" or "Remote".')),
        ]),
        _Part(Icons.power, _tr('إضافة مشترك', 'Add a strip'), _tr('لكل مشترك:', 'For each strip:'), [
          _Step(_tr('1. وضع الإعداد', '1. Setup mode'), _tr('دوس على زرار المشترك حوالي 10 ثواني لحد ما اللمبة ترمش بسرعة.', 'Hold the strip button about 10 s until the LED blinks fast.')),
          _Step(_tr('2. دوّر', '2. Search'), _tr('في التطبيق: إضافة مشترك ← دوّر على المشتركات. هيظهر برقم (آخر 7 خانات من الـ MAC اللي على الملصق).', 'In the app: Add strip → Search. It shows up by its ID (last 7 digits of the MAC on its label).')),
          _Step(_tr('3. اختار واستنى', '3. Pick it and wait'), _tr('الـ Hub بيفصل عن الواي فاي حوالي 20 ثانية وهو بيظبطه، وبعدها المشترك بيتصل لوحده وبيظهر في الرئيسية.', 'The hub leaves Wi-Fi for about 20 s while it sets the strip up; then the strip connects and appears on the home screen.')),
          _Step(_tr('4. سمّيه', '4. Name it'), _tr('من ⚙ جنب المشترك: اسم المشترك وكل مخرج، والحماية للراوتر، وقفل الأطفال.', 'From ⚙ next to the strip: names, router protection, child lock.')),
        ]),
        _Part(Icons.tune, _tr('بعد كده', 'Afterwards'), _tr('حاجات مفيدة:', 'Good to know:'), [
          _Step(_tr('الإشعارات', 'Notifications'), _tr('الإعدادات ← الإشعارات ← إشعارات لحظية. وافق على الصلاحيات، وخلي البطارية "بدون قيود" لـ Fisha.', 'Settings → Notifications → instant notifications. Allow the permissions and set battery to "unrestricted" for Fisha.')),
          _Step(_tr('تحديث الـ Hub', 'Updating the hub'), _tr('الإعدادات ← تحديث فيرموير الـ Hub ← اختار ملف .bin. لازم تكون على نفس الواي فاي.', 'Settings → Update hub firmware → pick the .bin file. You must be on the same Wi-Fi.')),
          _Step(_tr('لو غيّرت الراوتر', 'If you change the router'),
              _tr('غيّر الشبكة من الإعدادات ← شبكة الواي فاي قبلها. ولو نسيت، الـ Hub هيفتح شبكة Fisha-Hub-XXXX، ادخل عليها وافتح 192.168.4.1. وبعدها ضيف المشتركات تاني.',
                  'Change it first in Settings → Wi-Fi network. If you forget, the hub opens "Fisha-Hub-XXXX": join it and open 192.168.4.1. Then add the strips again.')),
        ]),
        _Part(Icons.build_outlined, _tr('لو حاجة مش شغالة', 'Troubleshooting'), _tr('أشهر المشاكل:', 'Common problems:'), [
          _Step(_tr('التطبيق بيقول غير متصل', 'The app says offline'), _tr('اتأكد إن الموبايل على نفس الواي فاي وإن عنوان الـ Hub صح، أو إن بيانات السيرفر صح.', 'Same Wi-Fi and the right hub address, or the right server details.')),
          _Step(_tr('المشترك مش ظاهر في البحث', 'The strip is not found'), _tr('ارجع وضع الإعداد (10 ثواني لحد الرمش السريع) وقرّبه من الـ Hub.', 'Put it back in setup mode (10 s, fast blinking) and move it closer.')),
          _Step(_tr('اتضاف بس ما ظهرش', 'Added but not showing'), _tr('افصل المشترك من الكهربا 10 ثواني ورجّعه. ولو لسه، اتأكد إن الشبكة 2.4GHz.', 'Unplug it for 10 s. If still missing, check the network is 2.4 GHz.')),
          _Step(_tr('رفع الفيرموير فشل', 'Firmware upload failed'), _tr('اتأكد إن باسورد التحديث هو نفس OTA_PASS، وإنك على نفس الواي فاي.', 'Check the update password equals OTA_PASS and that you are on the same Wi-Fi.')),
        ]),
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: C.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(_tr('طريقة التوصيل', 'Setup guide'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 28), children: [
          for (var i = 0; i < _parts.length; i++) ...[
            _partCard(context, _parts[i], i == 0),
            const SizedBox(height: 12),
          ],
        ]),
      ),
    );
  }

  Widget _partCard(BuildContext context, _Part p, bool open) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: cardBox(radius: 20),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: open,
            iconColor: C.accent,
            collapsedIconColor: C.muted,
            tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: C.accentBg, borderRadius: BorderRadius.circular(12)),
              child: Icon(p.icon, color: C.accent, size: 20),
            ),
            title: Text(p.title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: C.text)),
            subtitle: Text(p.intro, style: TextStyle(color: C.muted, fontSize: 12)),
            children: [
              for (final s in p.steps)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(s.title, style: TextStyle(fontWeight: FontWeight.w700, color: C.text)),
                    const SizedBox(height: 3),
                    Text(s.body, style: TextStyle(color: C.textSoft, height: 1.6, fontSize: 13.5)),
                    if (s.code != null) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(10)),
                        child: SelectableText(s.code!, textDirection: TextDirection.ltr, style: mono(12, color: C.accent, weight: FontWeight.w500)),
                      ),
                    ],
                  ]),
                ),
            ],
          ),
        ),
      );
}
