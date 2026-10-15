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
             "WAKE_LOCK", "REQUEST_IGNORE_BATTERY_OPTIMIZATIONS", "USE_BIOMETRIC", "REQUEST_INSTALL_PACKAGES",
             # 2.0.24 hub setup: read the phone's Wi-Fi name, find Fisha-Hub-XXXX and join it from inside the app
             "ACCESS_FINE_LOCATION", "ACCESS_WIFI_STATE", "CHANGE_WIFI_STATE", "ACCESS_NETWORK_STATE",
             "CHANGE_NETWORK_STATE", "NEARBY_WIFI_DEVICES"):
    tag = f'<uses-permission android:name="android.permission.{perm}"/>'
    if tag not in s:
        s = s.replace("<application", tag + "\n    <application", 1)
if "flutter_foreground_task.service.ForegroundService" not in s:
    s = s.replace("</application>", '''    <service
            android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
            android:foregroundServiceType="dataSync"
            android:exported="false" />
    </application>''', 1)
if "KeepAliveService" not in s:
    s = s.replace("</application>", '''    <service
            android:name=".KeepAliveService"
            android:foregroundServiceType="dataSync"
            android:exported="false" />
    </application>''', 1)
if "FishaStripWidgetProvider" not in s:
    s = s.replace("</application>", '''    <receiver
            android:name=".FishaStripWidgetProvider"
            android:exported="true">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
            </intent-filter>
            <meta-data
                android:name="android.appwidget.provider"
                android:resource="@xml/fisha_strip_widget_info" />
        </receiver>
        <activity
            android:name=".StripWidgetConfigActivity"
            android:exported="true"
            android:theme="@android:style/Theme.Translucent.NoTitleBar">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_CONFIGURE" />
            </intent-filter>
        </activity>
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

import android.Manifest
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var hubCb: ConnectivityManager.NetworkCallback? = null
    private var permResult: MethodChannel.Result? = null

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 7301) {
            permResult?.success(grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED })
            permResult = null
        }
    }

    private fun releaseHub() {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        cm.bindProcessToNetwork(null)
        hubCb?.let { try { cm.unregisterNetworkCallback(it) } catch (e: Exception) {} }
        hubCb = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 2.0.24: hub setup without leaving the app (find Fisha-Hub-XXXX, join it, talk to 192.168.4.1, go back)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fisha/wifi").setMethodCallHandler { call, result ->
            when (call.method) {
                "permission" -> {
                    val perms = mutableListOf(Manifest.permission.ACCESS_FINE_LOCATION)
                    if (Build.VERSION.SDK_INT >= 33) perms.add("android.permission.NEARBY_WIFI_DEVICES")
                    val missing = perms.filter { ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED }
                    if (missing.isEmpty() || call.argument<Boolean>("ask") != true) {
                        result.success(missing.isEmpty())
                    } else {
                        permResult = result
                        ActivityCompat.requestPermissions(this, missing.toTypedArray(), 7301)
                    }
                }
                "currentSsid" -> {
                    val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                    @Suppress("DEPRECATION")
                    val raw = try { wm.connectionInfo?.ssid ?: "" } catch (e: Exception) { "" }
                    val ssid = raw.trim('"')
                    result.success(if (ssid == "<unknown ssid>") "" else ssid)
                }
                "scanHubs" -> {
                    val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                    val list = try {
                        @Suppress("DEPRECATION")
                        wm.startScan()
                        wm.scanResults.mapNotNull { it.SSID }.filter { it.startsWith("Fisha-Hub-") }.distinct()
                    } catch (e: Exception) { emptyList<String>() }
                    result.success(list)
                }
                "joinHub" -> {
                    val ssid = call.argument<String>("ssid") ?: ""
                    if (Build.VERSION.SDK_INT < 29 || ssid.isEmpty()) {
                        result.success("manual")
                    } else {
                        releaseHub()
                        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                        val spec = WifiNetworkSpecifier.Builder().setSsid(ssid).build()
                        val req = NetworkRequest.Builder()
                            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                            .setNetworkSpecifier(spec)
                            .build()
                        var done = false
                        val cb = object : ConnectivityManager.NetworkCallback() {
                            override fun onAvailable(network: Network) {
                                cm.bindProcessToNetwork(network)
                                runOnUiThread { if (!done) { done = true; result.success("ok") } }
                            }
                            override fun onUnavailable() {
                                runOnUiThread { if (!done) { done = true; result.success("fail") } }
                            }
                        }
                        hubCb = cb
                        try { cm.requestNetwork(req, cb, 60000) } catch (e: Exception) { if (!done) { done = true; result.success("fail") } }
                    }
                }
                "releaseHub" -> { releaseHub(); result.success(true) }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fisha/keepalive").setMethodCallHandler { call, result ->
            KeepAlive.handle(this, call, result)
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fisha/widget").setMethodCallHandler { call, result ->
            if (call.method == "update") {
                try {
                    val editor = getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE).edit()
                    val args = call.arguments as? Map<*, *>
                    if (args != null) {
                        for ((k, v) in args) editor.putString(k.toString(), v?.toString() ?: "")
                    }
                    editor.apply()
                    FishaWidgets.updateAll(this)
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

# home-screen widgets (2.0.25): drawn natively; sources live in tool/widget/
import shutil
wsrc = os.path.join(os.path.dirname(os.path.abspath(__file__)), "widget")
for kt in ("FishaWidgets.kt", "StripWidgetConfigActivity.kt", "KeepAlive.kt"):
    shutil.copy(os.path.join(wsrc, kt), os.path.join(kt_dir, kt))
old_provider = os.path.join(kt_dir, "FishaWidgetProvider.kt")
if os.path.exists(old_provider):
    os.remove(old_provider)
layout_dir = os.path.join(APP, "android", "app", "src", "main", "res", "layout")
os.makedirs(layout_dir, exist_ok=True)
xml_dir = os.path.join(APP, "android", "app", "src", "main", "res", "xml")
os.makedirs(xml_dir, exist_ok=True)
for f in ("widget_layout.xml", "widget_strip_layout.xml"):
    shutil.copy(os.path.join(wsrc, f), os.path.join(layout_dir, f))
for f in ("fisha_widget_info.xml", "fisha_strip_widget_info.xml"):
    shutil.copy(os.path.join(wsrc, f), os.path.join(xml_dir, f))

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
# a plugin (file_picker) builds Java 11 with Kotlin 1.8; Kotlin's documented switch turns that check into a warning
props_path = os.path.join(APP, "android", "gradle.properties")
pg = open(props_path).read() if os.path.exists(props_path) else ""
if "kotlin.jvm.target.validation.mode" not in pg:
    pg = pg.rstrip("\n") + "\nkotlin.jvm.target.validation.mode=warning\n"
    open(props_path, "w").write(pg)

# plugins built against an older Android SDK (file_picker: 34) fail AAR checks that need 36;
# raise them in finalizeDsl (the same hook Flutter's Gradle plugin uses), registered before ":app" evaluation
root_kts = os.path.join(APP, "android", "build.gradle.kts")
if os.path.exists(root_kts):
    rk = open(root_kts).read()
    if "LibraryAndroidComponentsExtension" not in rk:
        hook = 'subprojects {\n    project.evaluationDependsOn(":app")'
        sdk = (
            "subprojects {\n"
            "    plugins.withId(\"com.android.library\") {\n"
            "        extensions.configure<com.android.build.api.variant.LibraryAndroidComponentsExtension> {\n"
            "            finalizeDsl { if ((it.compileSdk ?: 0) < 36) it.compileSdk = 36 }\n"
            "        }\n"
            "    }\n"
            "}\n"
        )
        rk = rk.replace(hook, sdk + hook, 1) if hook in rk else rk + "\n" + sdk
        open(root_kts, "w").write(rk)
# store id tied to the app name (namespace / Kotlin package stay com.mttlhub.mttl_hub)
for gf in (kts, groovy):
    if os.path.exists(gf):
        g = open(gf).read()
        g = re.sub(r'applicationId\s*=?\s*"[^"]+"', lambda m: m.group(0).split('"')[0] + '"com.fisha.app"', g, count=1)
        open(gf, "w").write(g)
print("android configured:", NAME)
