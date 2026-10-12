"""Run in CI after `flutter create`: permissions, app name, release signing, brand assets."""
import base64, os, re

APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAME = "Fisha"

# brand images are drawn in tool/brand.py so the repo only holds code
from brand import brand

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
             "WAKE_LOCK", "REQUEST_IGNORE_BATTERY_OPTIMIZATIONS", "USE_BIOMETRIC", "REQUEST_INSTALL_PACKAGES"):
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

# MainActivity: FlutterFragmentActivity (needed by local_auth) + the "fisha/widget" channel that
# stores the widget values and asks the home-screen widget to redraw
kt_dir = os.path.join(APP, "android", "app", "src", "main", "kotlin", "com", "mttlhub", "mttl_hub")
os.makedirs(kt_dir, exist_ok=True)
for ma in __import__("glob").glob(os.path.join(APP, "android", "app", "src", "main", "kotlin", "**", "MainActivity.kt"), recursive=True):
    os.remove(ma)
open(os.path.join(kt_dir, "MainActivity.kt"), "w").write('''package com.mttlhub.mttl_hub

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fisha/widget").setMethodCallHandler { call, result ->
            if (call.method == "update") {
                try {
                    val editor = getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE).edit()
                    val args = call.arguments as? Map<*, *>
                    if (args != null) {
                        for ((k, v) in args) editor.putString(k.toString(), v?.toString() ?: "")
                    }
                    editor.apply()
                    val manager = AppWidgetManager.getInstance(this)
                    val ids = manager.getAppWidgetIds(ComponentName(this, FishaWidgetProvider::class.java))
                    if (ids.isNotEmpty()) {
                        val intent = Intent(this, FishaWidgetProvider::class.java)
                        intent.action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                        intent.putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                        sendBroadcast(intent)
                    }
                    result.success(true)
                } catch (e: Exception) {
                    result.success(false)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
''')

# home-screen widget. A plain AppWidgetProvider that reads the values saved in the
# "HomeWidgetPreferences" SharedPreferences.
open(os.path.join(kt_dir, "FishaWidgetProvider.kt"), "w").write('''package com.mttlhub.mttl_hub

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class FishaWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        val widgetData = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
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

# gradle signing and desugaring (needed by flutter_local_notifications)
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
    if "desugar_jdk_libs" not in g:
        dep = '    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")'
        if re.search(r"(?m)^dependencies\s*\{", g):
            g = re.sub(r"(?m)^dependencies\s*\{", "dependencies {\n" + dep, g, count=1)
        else:
            g += "\ndependencies {\n" + dep + "\n}\n"
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
    if "desugar_jdk_libs" not in g:
        dep = "    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'"
        if re.search(r"(?m)^dependencies\s*\{", g):
            g = re.sub(r"(?m)^dependencies\s*\{", "dependencies {\n" + dep, g, count=1)
        else:
            g += "\ndependencies {\n" + dep + "\n}\n"
    open(groovy, "w").write(g)
else:
    raise SystemExit("no app build.gradle found")
# all modules (Java and Kotlin) on JVM 17, so a plugin cannot mix 11 and 1.8 (breaks assembleRelease)
root_kts = os.path.join(APP, "android", "build.gradle.kts")
root_groovy = os.path.join(APP, "android", "build.gradle")
if os.path.exists(root_kts):
    g = open(root_kts).read()
    if "JVM_17" not in g:
        g += (
            "\nsubprojects {\n"
            "    afterEvaluate {\n"
            "        if (hasProperty(\"android\")) {\n"
            "            extensions.configure<com.android.build.gradle.BaseExtension> {\n"
            "                compileOptions {\n"
            "                    sourceCompatibility = JavaVersion.VERSION_17\n"
            "                    targetCompatibility = JavaVersion.VERSION_17\n"
            "                }\n"
            "            }\n"
            "        }\n"
            "    }\n"
            "    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {\n"
            "        compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) }\n"
            "    }\n"
            "}\n"
        )
        open(root_kts, "w").write(g)
elif os.path.exists(root_groovy):
    g = open(root_groovy).read()
    if "JavaVersion.VERSION_17" not in g:
        g += (
            "\nsubprojects {\n"
            "    afterEvaluate { project ->\n"
            "        if (project.hasProperty('android')) {\n"
            "            project.android {\n"
            "                compileOptions {\n"
            "                    sourceCompatibility JavaVersion.VERSION_17\n"
            "                    targetCompatibility JavaVersion.VERSION_17\n"
            "                }\n"
            "            }\n"
            "        }\n"
            "    }\n"
            "    tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile).configureEach {\n"
            "        kotlinOptions { jvmTarget = '17' }\n"
            "    }\n"
            "}\n"
        )
        open(root_groovy, "w").write(g)

# store id tied to the app name (namespace / Kotlin package stay com.mttlhub.mttl_hub)
for gf in (kts, groovy):
    if os.path.exists(gf):
        g = open(gf).read()
        g = re.sub(r'applicationId\s*=?\s*"[^"]+"', lambda m: m.group(0).split('"')[0] + '"com.fisha.app"', g, count=1)
        open(gf, "w").write(g)
print("android configured:", NAME)
