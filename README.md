# Fisha · فيشة

نظام تحكم محلي وعن بُعد في المشتركات الذكية **LG U+ MTTL-W01** (4 مخارج لكل مشترك، مع قراءة القدرة بالواط والطاقة بالواط·ساعة والحرارة والفولت لكل مخرج).
وحدة **ESP32 Hub** بتحل محل سحابة LG: المشتركات بتتصل بالـ Hub على شبكة البيت، وتطبيق أندرويد (Flutter) بيكلم الـ Hub مباشرة على الواي فاي (REST + Server-Sent Events) أو من بره البيت عن طريق سيرفر MQTT (EMQX Cloud على TLS 8883) والـ Hub بيمرر الأوامر.

المستودع خاص · By [@ahmadalhelly](https://github.com/ahmadalhelly) · [English below](#english)

| المكوّن | الإصدار |
|---|---|
| تطبيق Android | 1.2.1 |
| فيرموير الـ Hub | 1.2.1 |

---

## البنية

```text
                 TCP 10086 / 21197                       HTTP 8080 · SSE 8081
 MTTL-W01 strips ──────────────────▶ ESP32 Hub ◀──────────────────────────────▶ التطبيق على واي فاي البيت
                                   192.168.1.100
                                        ▲
                                        │ MQTTS 8883
                                        ▼
                                   EMQX broker ◀──────────────────────────────▶ التطبيق من بره البيت
```

مواضيع MQTT: `mttl/<HUB_ID>/{status,info,state,event,cmd,cmd/ack}`

> **مهم:** المشتركات اللي اتحدّثت بآخر تحديث OTA (أكتوبر 2026) بقت بتتصل على البورت `21197` بدل `10086`. الـ Hub بيسمع على الاتنين.
> **اقفل النت عن المشتركات من الراوتر** (عناوين MAC بتبدأ بـ `88:D0:39`) عشان سحابة الشركة ما تحدّثهاش تاني.

---

## محتويات المستودع

| المسار | الوصف |
|---|---|
| `app/` | تطبيق Android بـ Flutter |
| `firmware/mttl_hub/mttl_hub.ino` | فيرموير الـ Hub (ESP32) |
| `docs/protocol.md` | بروتوكول المشترك ⇄ الـ Hub وواجهة الـ API |
| `docs/accounts_and_sharing.md` | الحسابات ومشاركة التحكم مع العيلة |
| `.github/workflows/build-app.yml` | بناء الـ APK تلقائياً مع كل push |

---

## مميزات التطبيق

- **مراقبة لحظية:** واط، أمبير، فولت، وحرارة لكل مخرج، عرض قائمة أو شبكة، ترتيب، بحث، غرف، وأيقونة لكل مشترك.
- **تحكم:** زر رئيسي لكل مشترك، قفل أطفال، مخارج محمية (ما بتطفيش مع "اقفل الكل")، تشغيل دائم، إطفاء تلقائي، عدّاد تنازلي، وتشغيل وإطفاء متكرر.
- **جداول وأتمتة:** جداول أسبوعية، أتمتة على حدود القدرة أو الحرارة أو التيار، وسيناريوهات.
- **الطاقة:** سجل استهلاك 90 يوم وحساب التكلفة بالتعريفة.
- **حماية:** حد أدنى وأقصى للفولت وحد تيار للمشترك كله، حد تيار لكل مخرج، وفصل عند الحرارة العالية.
- **تنبيهات:** إشعارات عن طريق ntfy لكل نوع حدث، وسجل أحداث.
- **مشاركة:** دعوة أفراد العيلة بكود (مشاهدة / تحكم / مدير) مع تحديد المشتركات المسموحة. الـ Hub نفسه هو اللي بيدير المستخدمين، من غير Firebase.
- **الحساب:** دخول اختياري بجوجل مع مزامنة الإعدادات في فولدر خاص بالتطبيق على Google Drive، أو حساب محلي من غير تسجيل، ونسخة احتياطية في ملف.
- **أمان:** بصمة لكل مخرج حساس.
- **أدوات:** ويدجت للشاشة الرئيسية، تغيير واي فاي الـ Hub من التطبيق، تحديث فيرموير الـ Hub من التطبيق (OTA)، عربي وإنجليزي، وأكتر من ثيم.

---

## فيرموير الـ Hub

### إعدادات Arduino IDE

| البند | القيمة |
|---|---|
| Board | ESP32 Dev Module (ESP32-WROOM-32) |
| Core | esp32 by Espressif · 3.x |
| Partition Scheme | Minimal SPIFFS (1.9MB APP with OTA) |
| مكتبات إضافية | لا يوجد |

> الملف لازم يكون جوه فولدر بنفس اسمه: `mttl_hub/mttl_hub.ino`.

### الإعدادات في أول الملف

| الثابت | القيمة في المستودع | ملاحظة |
|---|---|---|
| `WIFI_SSID` / `WIFI_PASS` | `YOUR_WIFI_NAME` / `YOUR_WIFI_PASSWORD` | 2.4 GHz بس، والباسورد ما يكونش فيه `:` |
| `LOCAL_IP` · `GATEWAY` · `SUBNET` · `DNS1` | `192.168.1.100` · `.1` · `255.255.255.0` · `.1` | غيّرها لو شبكتك مش `192.168.1.x` |
| `API_TOKEN` | فاضي | فاضي = أي جهاز على شبكة البيت يقدر يتحكم |
| `MQTT_URI` / `MQTT_USER` | سيرفر EMQX / `ESP32_hub` | |
| `MQTT_PASS` | `YOUR_MQTT_PASSWORD` | مش لازم: التطبيق بيبعته للـ Hub |
| `OTA_PASS` | `change-me` | باسورد صفحة التحديث |

**الباسوردات مش محفوظة في الكود.** الـ Hub بيحفظها في ذاكرته (NVS). لو رفعت نسخة فيها القيم الافتراضية، هيفضل شغال بالباسوردات المحفوظة، فتقدر تحدّث من غير ما تعدّل الكود. أول تثبيت على Hub جديد: يا تكتب القيم الحقيقية في نسختك المحلية بس (ما ترفعهاش)، يا تسيبها افتراضية وتظبط الواي فاي من شبكة الإعداد تحت.

- **شبكة الإعداد:** لو الـ Hub ما قدرش يدخل الواي فاي، بيفتح شبكة `Fisha-Hub-XXXX` (الباسورد هو باسورد التحديث، أو `fisha1234` لو لسه ما اتحددش). ادخل عليها وافتح `http://192.168.4.1` واختار الشبكة.
- **باسورد السيرفر:** من التطبيق: الإعدادات ← الاتصال ← باسورد الـ Hub على السيرفر، وإنت على واي فاي البيت.
- **التحديث:** أول مرة بكابل USB. بعد كده من التطبيق (الإعدادات ← تحديث فيرموير الـ Hub) بملف `.bin` (صورة التحديث، من غير بارتشن)، أو من المتصفح على `http://192.168.1.100:8080/update`. الصورة الكاملة `...-FULL-flash-0x0.bin` للتفليش الأول على الهاب الجديد أو الممسوح فقط، وبتمسح الإعدادات.

---

## التثبيت خطوة بخطوة

1. **احجز `192.168.1.100` للـ Hub** في الراوتر (أو غيّر `LOCAL_IP`).
2. **ارفع الفيرموير بالـ USB**، وافتح Serial Monitor على 115200. لازم يظهر الـ IP ورسالة إنه بيسمع على `10086` و `21197`.
3. **نزّل التطبيق** من [Releases](../../releases). الـ CI بيبني APK مع كل push: فرع `main` هو الإصدار الرسمي، وباقي الفروع تجريبية.
4. **الاتصال المحلي:** الإعدادات ← الاتصال ← عنوان الـ Hub `192.168.1.100`، البورت `8080`.
5. **التحكم من بره البيت:**
   1. اعمل deployment على EMQX Cloud، وفيه مستخدمين: `ESP32_hub` للـ Hub و `stripe_app` للتطبيق.
   2. في التطبيق اكتب عنوان السيرفر والبورت `8883` وبيانات `stripe_app`.
   3. اكتب باسورد `ESP32_hub` في خانة "باسورد الـ Hub على السيرفر"، والتطبيق هيبعته للـ Hub.
6. **إضافة مشترك:** إضافة مشترك ← الـ Hub بيدخل على شبكة إعداد المشترك (`TONLY_TAP_xxxx`) ويديله واي فاي البيت وعنوان الـ Hub، وبعدها المشترك بيتصل بالـ Hub لوحده.
7. **اقفل النت عن المشتركات** من الراوتر (`88:D0:39:*`).

---

## واجهة الـ Hub (API)

| الطريقة | المسار | الوصف |
|---|---|---|
| `GET` | `/api/state` | الحالة الكاملة |
| `GET` | `/api/health` | صحة الـ Hub والاتصال |
| `POST` | `/api/<action>` | أمر بجسم JSON: `onoff`, `label`, `lock`, `protect`, `keepon`, `autooff`, `timer`, `schedule_save`, `automation_save`, `config`, `notify`, `provision`, `wifi`, `cloud`, `users`, `user_invite`… |
| `GET` | `:8081/events` | بث لحظي (SSE): `state` و `event` |

نفس الأوامر عن طريق MQTT على `mttl/<HUB_ID>/cmd`، والحقول في نفس المستوى (مش جوه `body`):

```json
{ "id": "a1", "path": "/api/onoff", "mac": "88D0390A4ABF", "outlet": 1, "on": true }
```

والرد بيرجع على `mttl/<HUB_ID>/cmd/ack` بنفس الـ `id`. التفاصيل في [`docs/protocol.md`](docs/protocol.md).

---

## بناء التطبيق محلياً

المتطلبات: Flutter (stable) و Java 17. من جوه فولدر `app/`:

```bash
flutter create --platforms=android --org com.mttlhub --project-name mttl_hub .
python3 tool/configure_android.py
flutter pub get
dart run flutter_launcher_icons
dart run flutter_native_splash:create
flutter build apk --release
```

- رقم التطبيق على Android: `com.fisha.app`.
- **دخول جوجل:** محتاج Android OAuth client في Google Cloud على `com.fisha.app` ومعاه SHA-1 بتاع مفتاح التوقيع، ولازم Google Drive API تكون مفعّلة في نفس المشروع. من غير ده التطبيق هيقول إن دخول جوجل مش متظبط.

---

## الأمان

- خلي المستودع خاص، وما ترفعش أي باسورد حقيقي. الباسوردات اللي كانت في نسخ قديمة من الكود اعتبرها مكشوفة وغيّرها.
- `API_TOKEN` الفاضي معناه إن أي جهاز على شبكة البيت يقدر يتحكم في الـ Hub.
- النسخة الاحتياطية في ملف ما فيهاش باسوردات. نسخة جوجل فيها الإعدادات كاملة، لكنها في فولدر خاص بالتطبيق على Drive محدش يقدر يفتحه غير التطبيق.
- مفتاح التوقيع في `app/signing` الأحسن ينتقل لـ GitHub Actions Secrets.

---

## حل المشاكل

| المشكلة | السبب | الحل |
|---|---|---|
| المشتركات فاصلة بعد تحديث | المشترك بقى بيتصل على `21197` | حدّث الـ Hub لآخر نسخة، واقفل النت عن المشتركات |
| التطبيق "غير متصل" في البيت | عنوان الـ Hub غلط | الإعدادات ← الاتصال: `192.168.1.100` |
| التحكم من بره مش شغال | الـ Hub مش متصل بالسيرفر | الإعدادات ← الاتصال: شوف حالة السيرفر واكتب باسورد الـ Hub تاني |
| "دخول جوجل مش متظبط" | OAuth client أو SHA-1 ناقص | راجع Google Cloud Console |
| "Google Drive API مقفولة" | الـ API مش مفعّلة | فعّل Google Drive API في المشروع |

---

## سجل الإصدارات

| الإصدار | التغييرات |
|---|---|
| Hub 1.2.1 | حد أقصى للوات قابل للتعديل للمشترك |
| App 1.2.1 | زرار الهابات في الرئيسية دايماً، صفحة هابات واحدة وبحث عند الإضافة، توقيت 12 ساعة، السيناريوهات في الرئيسية، PDF بالألوان، بصمة وإظهار الباسورد، حدود الحماية بالوات، قاعدة أتمتة لكل المشتركات |
| Hub 1.2.0 | منطقة زمنية بتوقيت صيفي تلقائي، سجل تشغيل المخارج، سيناريوهات (لو/بشرط/إفعل/وإلا)، إصلاح فصل المشتركات لما الذاكرة تتقطّع |
| App 1.2.0 | صفحة المنطقة الزمنية، سجل المخرج بجراف وتصدير، السيناريوهات، أكتر من هاب، تشفير النسخة الاحتياطية، إيه اللي يتزامن، السحب بين التابات، أيقونات الشبكة |
| Hub 1.1.9 | إصلاحات أمان وثبات في رفع فيرموير المشترك ووضع التحديث، والهاب بيبلّغ رقم بنائه عشان التطبيق يعرف التحديث الأحدث من نفس النسخة |
| Hub 1.1.8 | رفع فيرموير المشترك على قطع 4KB مع إعادة محاولة، وضع تحديث بيقفل MQTT والبث اللحظي مؤقتاً أثناء التحديث، وبوابة قبل اتصال TLS بتمنع تكرار فشل الذاكرة، توقيت مصر +3 افتراضياً، ومزامنة حدود الحماية والجدولة مع المشترك F1.0.92 |
| App 1.1.4 | مركز التحديثات بيعرض ملاحظات التحديث كاملة (للتطبيق والهاب والمشترك)، ورفع فيرموير المشترك بيكمل من آخر قطعة وصلت للهاب لو الاتصال انقطع |

---

<a id="english"></a>

# Fisha (English)

Local and remote control for **LG U+ MTTL-W01** smart power strips (4 outlets each, with per-outlet power, energy, temperature and voltage readings).
An **ESP32 Hub** replaces the LG cloud: strips dial the hub over TCP on the home LAN, and the Flutter Android app talks to the hub directly on Wi-Fi (REST + Server-Sent Events) or, away from home, through an MQTT broker (EMQX Cloud, TLS 8883) that the hub relays.

| Component | Version |
|---|---|
| Android app | 1.2.1 |
| Hub firmware | 1.2.1 |

## Architecture

```text
                 TCP 10086 / 21197                       HTTP 8080 · SSE 8081
 MTTL-W01 strips ──────────────────▶ ESP32 Hub ◀──────────────────────────────▶ App on home Wi-Fi
                                   192.168.1.100
                                        ▲
                                        │ MQTTS 8883
                                        ▼
                                   EMQX broker ◀──────────────────────────────▶ App away from home
```

MQTT topics: `mttl/<HUB_ID>/{status,info,state,event,cmd,cmd/ack}`

> Strips updated by the latest OTA (Oct 2026) dial port `21197` instead of `10086`; the hub listens on both. Block the strips (`88:D0:39:*`) from the internet on the router so the vendor cloud cannot update them again.

## Repository layout

| Path | Contents |
|---|---|
| `app/` | Flutter Android app |
| `firmware/mttl_hub/mttl_hub.ino` | ESP32 hub firmware |
| `docs/protocol.md` | Strip ⇄ hub protocol and hub API |
| `docs/accounts_and_sharing.md` | Accounts and family sharing |
| `.github/workflows/build-app.yml` | Builds the APK on every push |

## Features

Live W/A/V/°C per outlet · list/grid, sort, search, rooms, strip icons · master switch per strip, child lock, protected outlets, keep-on, auto-off, countdown and power-cycle timers · weekly schedules, power/temperature/current automations, scenarios · 90-day energy history with tariff · strip voltage min/max and current limit, per-outlet current limit, over-temperature cut · ntfy notifications per event type and an event log · family sharing by invite code (view / control / admin, per-strip access, managed by the hub, no Firebase) · optional Google sign-in with settings sync to the app's private Google Drive folder, or a local account, plus a backup file · fingerprint lock per outlet · home-screen widget, hub Wi-Fi change and hub OTA from the app · Arabic and English, several themes.

## Hub firmware

| Setting | Value |
|---|---|
| Board | ESP32 Dev Module (ESP32-WROOM-32) |
| Core | esp32 by Espressif 3.x |
| Partition scheme | Minimal SPIFFS (1.9MB APP with OTA) |
| Extra libraries | None |

The sketch must sit in a folder with the same name (`mttl_hub/mttl_hub.ino`).

| Constant | Repo value | Note |
|---|---|---|
| `WIFI_SSID` / `WIFI_PASS` | `YOUR_WIFI_NAME` / `YOUR_WIFI_PASSWORD` | 2.4 GHz only, no `:` in the password |
| `LOCAL_IP`, `GATEWAY`, `SUBNET`, `DNS1` | `192.168.1.100`, `.1`, `255.255.255.0`, `.1` | Change if your LAN is not `192.168.1.x` |
| `API_TOKEN` | empty | Empty = any device on the LAN can control the hub |
| `MQTT_URI` / `MQTT_USER` | EMQX host / `ESP32_hub` | |
| `MQTT_PASS` | `YOUR_MQTT_PASSWORD` | Optional: the app sends it to the hub |
| `OTA_PASS` | `change-me` | Password of the update page |

**No passwords live in the source.** The hub keeps them in NVS; a build with placeholders keeps using the stored ones, so updates need no code edits. On a brand-new hub either put real values in your local copy only (never commit them) or leave the placeholders and use the setup network:

- **Setup network:** if the hub cannot join Wi-Fi it opens `Fisha-Hub-XXXX` (password = update password, or `fisha1234` if none is set). Join it, open `http://192.168.4.1` and pick your network.
- **Server password:** in the app, Settings → Connection → hub server password, while on the home Wi-Fi.
- **Updates:** first flash over USB; later from the app (Settings → Update hub firmware) with the update `.bin` (no partition table), or at `http://192.168.1.100:8080/update`. The `...-FULL-flash-0x0.bin` image is for the first flash of a new or erased hub only and wipes the settings.

## Setup

1. Reserve `192.168.1.100` for the hub on the router (or change `LOCAL_IP`).
2. Flash over USB and open Serial Monitor at 115200: you should see the IP and the hub listening on `10086` and `21197`.
3. Install the APK from [Releases](../../releases). CI builds one on every push: `main` is the release, other branches are pre-releases.
4. Local connection: Settings → Connection → hub address `192.168.1.100`, port `8080`.
5. Remote access: create an EMQX Cloud deployment with users `ESP32_hub` (hub) and `stripe_app` (app); enter the broker host, port `8883` and the `stripe_app` login in the app, then the `ESP32_hub` password as the hub server password. The app pushes it to the hub.
6. Add a strip: the hub joins the strip's setup AP (`TONLY_TAP_xxxx`), hands it the home Wi-Fi and the hub IP, and the strip dials the hub.
7. Block the strips (`88:D0:39:*`) from the internet on the router.

## Hub API

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/api/state` | Full state |
| `GET` | `/api/health` | Hub health |
| `POST` | `/api/<action>` | JSON command: `onoff`, `label`, `lock`, `protect`, `keepon`, `autooff`, `timer`, `schedule_save`, `automation_save`, `config`, `notify`, `provision`, `wifi`, `cloud`, `users`, `user_invite`… |
| `GET` | `:8081/events` | Live stream (SSE): `state` and `event` |

Over MQTT, publish to `mttl/<HUB_ID>/cmd` with the fields at the top level:

```json
{ "id": "a1", "path": "/api/onoff", "mac": "88D0390A4ABF", "outlet": 1, "on": true }
```

The reply arrives on `mttl/<HUB_ID>/cmd/ack` with the same `id`. See [`docs/protocol.md`](docs/protocol.md).

## Building the app

Flutter stable and Java 17. Inside `app/`:

```bash
flutter create --platforms=android --org com.mttlhub --project-name mttl_hub .
python3 tool/configure_android.py
flutter pub get
dart run flutter_launcher_icons
dart run flutter_native_splash:create
flutter build apk --release
```

- Android application id: `com.fisha.app`.
- Google sign-in needs an Android OAuth client in Google Cloud for `com.fisha.app` with the signing key's SHA-1, and the Google Drive API enabled in the same project.

## Security

- Keep the repository private and never commit real passwords. Treat passwords that were in older versions of the source as exposed and rotate them.
- An empty `API_TOKEN` lets any device on the home LAN control the hub.
- Backup files carry no passwords. The Google copy holds full settings, in the app's private Drive folder that only the app can read.
- Move the signing key in `app/signing` to GitHub Actions secrets.

## Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| Strips offline after an update | Strip now dials `21197` | Update the hub to the latest version, block the strips from the internet |
| App shows offline at home | Wrong hub address | Settings → Connection: `192.168.1.100` |
| Remote control not working | Hub not connected to the broker | Settings → Connection: check the server status, re-enter the hub password |
| "Google sign-in is not set up" | Missing OAuth client / SHA-1 | Google Cloud Console |
| "Google Drive API is disabled" | API not enabled | Enable the Google Drive API |

---

By **[@ahmadalhelly](https://github.com/ahmadalhelly)**
