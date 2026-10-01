"""Run in CI after `flutter create`: permissions, app name, release signing, brand assets."""
import base64, os, re

APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAME = "Fisha"

# brand images are drawn here so the repo only holds code
def brand():
    from PIL import Image, ImageDraw
    S = 1024
    AMBER, BG, RING, CLEAR = (242, 181, 68, 255), (13, 17, 23, 255), (58, 48, 26, 255), (0, 0, 0, 0)

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
open(man, "w").write(s)

# gradle signing
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
    open(groovy, "w").write(g)
else:
    raise SystemExit("no app build.gradle found")
print("android configured:", NAME)
