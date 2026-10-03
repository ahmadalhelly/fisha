"""Run in CI after `flutter create`: permissions, app name, release signing, brand assets."""
import base64, os, re

APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAME = "Fisha"

# brand images are drawn here so the repo only holds code
def brand():
    from PIL import Image, ImageDraw
    S = 1024
    AMBER, BG, RING, CLEAR = (46, 230, 176, 255), (7, 13, 25, 255), (20, 60, 58, 255), (0, 0, 0, 0)

    def glyph(d, cx, cy, sc, cut):
        w, h, r = int(300 * sc), int(250 * sc), int(70 * sc)
        x0, y0 = cx - w // 2, cy - int(60 * sc)
        pw, ph, gap = int(46 * sc), int(150 * sc), int(70 * sc)
        for px in (cx - gap - pw // 2, cx + gap - pw // 2):
            d.rounded_rectangle([px, y0 - ph + int(20 * sc), px + pw, y0 + int(30 * sc)], radius=int(20 * sc), fill=AMBER)
        d.rounded_rectangle([x0, y0, x0 + w, y0 + h], radius=r, fill=AMBER)
        cw = int(56 * sc)
        d.rounded_rectangle([cx - cw // 2, y0 + h - int(20 * sc), cx + cw // 2, y0 + h + int(140 * sc)], radius=int(28 * sc), fill=AMBER)
        bolt = [(cx + int(18 * sc), y0 + int(38 * sc)), (cx - int(52 * sc), y0 + int(140 * sc)), (cx - int(6 * sc), y0 + int(140 * sc)),
                (cx - int(24 * sc), y0 + int(214 * sc)), (cx + int(54 * sc), y0 + int(104 * sc)), (cx + int(8 * sc), y0 + int(104 * sc))]
        d.polygon(bolt, fill=cut)

    out = os.path.join(APP, "assets", "brand")
    os.makedirs(out, exist_ok=True)
    im = Image.new("RGBA", (S, S), BG)
    d = ImageDraw.Draw(im)
    d.ellipse([162, 162, 862, 862], outline=RING, width=14)
    glyph(d, S // 2, S // 2 - 40, 1.25, BG)
    im.save(os.path.join(out, "icon.png"))
    for name, sc in (("icon_fg.png", 0.95), ("splash.png", 0.9)):
        im = Image.new("RGBA", (S, S), CLEAR)
        glyph(ImageDraw.Draw(im), S // 2, S // 2 - 30, sc, CLEAR)
        im.save(os.path.join(out, name))

    # signature at the bottom of the launch screen
    from PIL import ImageFont
    font = None
    for path in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"):
        if os.path.exists(path):
            font = ImageFont.truetype(path, 64)
            break
    if font is None:
        try:
            font = ImageFont.load_default(size=64)
        except TypeError:
            font = ImageFont.load_default()
    text = "@ahmadalhelly"
    W, H = 800, 160
    im = Image.new("RGBA", (W, H), CLEAR)
    d = ImageDraw.Draw(im)
    box = d.textbbox((0, 0), text, font=font)
    d.text(((W - (box[2] - box[0])) // 2 - box[0], (H - (box[3] - box[1])) // 2 - box[1]), text, font=font, fill=(154, 167, 184, 255))
    im.save(os.path.join(out, "branding.png"))


brand()

# signing key
with open(os.path.join(APP, "signing", "release.jks.b64")) as f, open(os.path.join(APP, "signing", "release.jks"), "wb") as out:
    out.write(base64.b64decode(f.read()))
props = dict(l.strip().split("=", 1) for l in open(os.path.join(APP, "signing", "key.properties")) if "=" in l)
store = os.path.join(APP, "signing", "release.jks").replace("\\", "/")

# manifest
man = os.path.join(APP, "android", "app", "src", "main", "AndroidManifest.xml")
s = open(man).read()
if "android.permission.INTERNET" not in s:
    s = s.replace("<application", '<uses-permission android:name="android.permission.INTERNET"/>\n    <application', 1)
if "usesCleartextTraffic" not in s:
    s = re.sub(r"<application\b", '<application android:usesCleartextTraffic="true"', s, count=1)
s = re.sub(r'android:label="[^"]*"', f'android:label="{NAME}"', s, count=1)
# native notifications: foreground service + notification + biometric permissions
for perm in ("FOREGROUND_SERVICE", "FOREGROUND_SERVICE_DATA_SYNC", "POST_NOTIFICATIONS", "RECEIVE_BOOT_COMPLETED",
             "WAKE_LOCK", "REQUEST_IGNORE_BATTERY_OPTIMIZATIONS", "USE_BIOMETRIC"):
    tag = f'<uses-permission android:name="android.permission.{perm}"/>'
    if tag not in s:
        s = s.replace("<application", tag + "\n    <application", 1)
if "flutter_foreground_task.service.ForegroundService" not in s:
    s = s.replace("</application>", '''    <service
            android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
            android:foregroundServiceType="dataSync"
            android:exported="false" />
    </application>''', 1)
if "FishaWidgetProvider" not in s:
    s = s.replace("</application>", '''    <receiver
            android:name=".FishaWidgetProvider"
            android:exported="true">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
            </intent-filter>
            <meta-data
                android:name="android.appwidget.provider"
                android:resource="@xml/fisha_widget_info" />
        </receiver>
    </application>''', 1)
open(man, "w").write(s)

# patch MainActivity to FlutterFragmentActivity for local_auth
import glob
for ma in glob.glob(os.path.join(APP, "android", "app", "src", "main", "kotlin", "**", "MainActivity.kt"), recursive=True):
    content = open(ma).read()
    if "FlutterFragmentActivity" not in content:
        content = content.replace("import io.flutter.embedding.android.FlutterActivity", "import io.flutter.embedding.android.FlutterFragmentActivity")
        content = content.replace("FlutterActivity()", "FlutterFragmentActivity()")
        if "FlutterFragmentActivity" not in content:
            content = re.sub(r'class\s+MainActivity\s*:\s*[^\n{]+', 'class MainActivity: io.flutter.embedding.android.FlutterFragmentActivity()', content)
        open(ma, "w").write(content)

# generate home_widget Android files
widget_kt_dir = os.path.join(APP, "android", "app", "src", "main", "kotlin", "com", "mttlhub", "mttl_hub")
os.makedirs(widget_kt_dir, exist_ok=True)
open(os.path.join(widget_kt_dir, "FishaWidgetProvider.kt"), "w").write('''package com.mttlhub.mttl_hub

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborras.home_widget.HomeWidgetProvider

class FishaWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_layout)
            views.setTextViewText(R.id.widget_total_w, widgetData.getString("total_w", "0 W"))
            views.setTextViewText(R.id.widget_outlets_on, widgetData.getString("outlets_on", "0/0"))
            views.setTextViewText(R.id.widget_hottest_temp, widgetData.getString("hottest_temp", "—"))
            views.setTextViewText(R.id.widget_conn_mode, widgetData.getString("conn_mode", "—"))

            val intent = Intent(context, MainActivity::class.java)
            val pendingIntent = PendingIntent.getActivity(
                context, 0, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_container, pendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
''')

layout_dir = os.path.join(APP, "android", "app", "src", "main", "res", "layout")
os.makedirs(layout_dir, exist_ok=True)
open(os.path.join(layout_dir, "widget_layout.xml"), "w").write('''<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/widget_container"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:padding="12dp"
    android:background="@drawable/widget_bg">

    <TextView
        android:id="@+id/widget_total_w"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="0 W"
        android:textColor="#2EE6B0"
        android:textSize="20sp"
        android:textStyle="bold" />

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal"
        android:layout_marginTop="4dp">

        <TextView
            android:id="@+id/widget_outlets_on"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="0/0"
            android:textColor="#C2D1E8"
            android:textSize="12sp" />

        <TextView
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text=" · "
            android:textColor="#4D5C77"
            android:textSize="12sp" />

        <TextView
            android:id="@+id/widget_hottest_temp"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="—"
            android:textColor="#C2D1E8"
            android:textSize="12sp" />
    </LinearLayout>

    <TextView
        android:id="@+id/widget_conn_mode"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginTop="2dp"
        android:text="—"
        android:textColor="#8798B3"
        android:textSize="11sp" />

</LinearLayout>
''')

drawable_dir = os.path.join(APP, "android", "app", "src", "main", "res", "drawable")
os.makedirs(drawable_dir, exist_ok=True)
open(os.path.join(drawable_dir, "widget_bg.xml"), "w").write('''<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android">
    <solid android:color="#0E1628"/>
    <corners android:radius="18dp"/>
    <stroke android:width="1dp" android:color="#1F2D48"/>
</shape>
''')

xml_dir = os.path.join(APP, "android", "app", "src", "main", "res", "xml")
os.makedirs(xml_dir, exist_ok=True)
open(os.path.join(xml_dir, "fisha_widget_info.xml"), "w").write('''<?xml version="1.0" encoding="utf-8"?>
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:minWidth="140dp"
    android:minHeight="70dp"
    android:targetCellWidth="2"
    android:targetCellHeight="1"
    android:updatePeriodMillis="0"
    android:initialLayout="@layout/widget_layout"
    android:resizeMode="horizontal|vertical"
    android:widgetCategory="home_screen">
</appwidget-provider>
''')

# gradle signing and dependencies
kts = os.path.join(APP, "android", "app", "build.gradle.kts")
groovy = os.path.join(APP, "android", "app", "build.gradle")
if os.path.exists(kts):
    g = open(kts).read()
    if 'create("release")' not in g:
        block = (
            "    signingConfigs {\n"
            '        create("release") {\n'
            f'            storeFile = file("{store}")\n'
            f'            storePassword = "{props["storePassword"]}"\n'
            f'            keyAlias = "{props["keyAlias"]}"\n'
            f'            keyPassword = "{props["keyPassword"]}"\n'
            "        }\n"
            "    }\n\n"
        )
        g = g.replace("    buildTypes {", block + "    buildTypes {", 1)
    g = g.replace('signingConfigs.getByName("debug")', 'signingConfigs.getByName("release")')
    if "isCoreLibraryDesugaringEnabled" not in g:
        g = re.sub(r"compileOptions\s*\{", "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", g, count=1)
    
    # ensure home_widget project and desugar dependencies are linked
    dep_entries = '    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n    implementation(project(":home_widget"))'
    if "dependencies {" in g:
        if 'project(":home_widget")' not in g:
            g = re.sub(r"dependencies\s*\{", f"dependencies {{\n{dep_entries}", g, count=1)
    else:
        g += f'\ndependencies {{\n{dep_entries}\n}}\n'
    open(kts, "w").write(g)

elif os.path.exists(groovy):
    g = open(groovy).read()
    if "signingConfigs {" not in g:
        block = (
            "    signingConfigs {\n"
            "        release {\n"
            f"            storeFile file('{store}')\n"
            f"            storePassword '{props['storePassword']}'\n"
            f"            keyAlias '{props['keyAlias']}'\n"
            f"            keyPassword '{props['keyPassword']}'\n"
            "        }\n"
            "    }\n\n"
        )
        g = g.replace("    buildTypes {", block + "    buildTypes {", 1)
    g = g.replace("signingConfig signingConfigs.debug", "signingConfig signingConfigs.release")
    g = g.replace('signingConfig = signingConfigs.debug', 'signingConfig = signingConfigs.release')
    if "coreLibraryDesugaringEnabled" not in g:
        g = re.sub(r"compileOptions\s*\{", "compileOptions {\n        coreLibraryDesugaringEnabled true", g, count=1)
    
    dep_entries = "    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n    implementation project(':home_widget')"
    if "dependencies {" in g:
        if "project(':home_widget')" not in g:
            g = re.sub(r"dependencies\s*\{", f"dependencies {{\n{dep_entries}", g, count=1)
    else:
        g += f"\ndependencies {{\n{dep_entries}\n}}\n"
    open(groovy, "w").write(g)
else:
    raise SystemExit("no app build.gradle found")
print("android configured:", NAME)
