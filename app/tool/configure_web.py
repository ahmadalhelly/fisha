"""Run in CI for the web build, after `flutter create --platforms=web` and after web_overrides/ is copied over web/:
draws the brand assets the app bundles (pubspec lists assets/brand/icon_fg.png) and the PWA / iPhone home-screen icons."""
import os

from brand import APP, brand

brand()

from PIL import Image

src = Image.open(os.path.join(APP, "assets", "brand", "icon.png")).convert("RGBA")
web = os.path.join(APP, "web")
icons = os.path.join(web, "icons")
os.makedirs(icons, exist_ok=True)
# icon.png has an opaque dark background and the glyph well inside the safe zone, so it also serves as the maskable icon
for name, size in (("Icon-192.png", 192), ("Icon-512.png", 512), ("Icon-maskable-192.png", 192), ("Icon-maskable-512.png", 512)):
    src.resize((size, size), Image.LANCZOS).convert("RGB").save(os.path.join(icons, name))
src.resize((32, 32), Image.LANCZOS).save(os.path.join(web, "favicon.png"))
print("web configured")
