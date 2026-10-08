"""Brand images (app icon, splash, signature), drawn here so the repo only holds code.
Used by configure_android.py and configure_web.py."""
import os

APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


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



if __name__ == "__main__":
    brand()
