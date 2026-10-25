"""App icon: a Chennai auto, seen head-on, against a Marina sunset.

Writes (all drawn at 4x and downsampled for clean edges):
  icon.png                              512 px, project icon (config/icon) and Play listing source
  assets/icon/icon_192.png              legacy Android launcher icon
  assets/icon/adaptive_fg_432.png       adaptive foreground (auto inside the 66 % safe zone)
  assets/icon/adaptive_bg_432.png       adaptive background (sunset)
  assets/icon/adaptive_mono_432.png     themed / monochrome icon (Android 13+)
  assets/icon/boot_splash.png           1280x720 boot splash (application/boot_splash/image)

Run: python3 tools/art/make_app_icon.py   (Pillow only)
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "icon"
SS = 4  # supersampling

YELLOW = (250, 196, 10)
YELLOW_DARK = (206, 150, 0)
BLACK = (24, 22, 24)
GLASS = (150, 190, 210)
GLASS_HI = (205, 228, 238)
CHROME = (215, 215, 220)
LAMP = (255, 248, 210)
TYRE = (32, 30, 32)


def sunset(size: int) -> Image.Image:
    img = Image.new("RGB", (size, size))
    top, mid, low = (60, 24, 76), (226, 92, 70), (255, 186, 92)
    px = img.load()
    for y in range(size):
        t = y / (size - 1)
        if t < 0.55:
            k = t / 0.55
            c = tuple(int(top[i] + (mid[i] - top[i]) * k) for i in range(3))
        else:
            k = (t - 0.55) / 0.45
            c = tuple(int(mid[i] + (low[i] - mid[i]) * k) for i in range(3))
        for x in range(size):
            px[x, y] = c
    d = ImageDraw.Draw(img)
    # Sun glow behind the auto.
    glow = Image.new("L", (size, size), 0)
    ImageDraw.Draw(glow).ellipse([size * 0.18, size * 0.2, size * 0.82, size * 0.84], fill=150)
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.06))
    img.paste((255, 214, 140), mask=glow)
    # Road at the bottom.
    d.rectangle([0, size * 0.8, size, size], fill=(30, 24, 34))
    d.rectangle([0, size * 0.8, size, size * 0.808], fill=(255, 200, 90))
    return img


def auto(d: ImageDraw.ImageDraw, cx: float, cy: float, s: float, mono: bool = False) -> None:
    """Front view of a Bajaj RE: s = overall height. (cx, cy) = centre of the body."""
    y_c = YELLOW if not mono else (255, 255, 255)
    y_d = YELLOW_DARK if not mono else (255, 255, 255)
    k = BLACK if not mono else (255, 255, 255)
    glass = GLASS if not mono else (0, 0, 0, 0)
    w = s * 0.86
    top = cy - s * 0.5
    bot = cy + s * 0.5
    # Rear wheels peeking out at the sides.
    for side in (-1, 1):
        x = cx + side * w * 0.47
        d.rounded_rectangle([x - s * 0.07, bot - s * 0.2, x + s * 0.07, bot], radius=s * 0.04, fill=TYRE if not mono else k)
    # Canopy: wide rounded black roof.
    d.rounded_rectangle([cx - w * 0.5, top, cx + w * 0.5, top + s * 0.2], radius=s * 0.09, fill=k)
    d.rectangle([cx - w * 0.47, top + s * 0.14, cx + w * 0.47, top + s * 0.24], fill=k)
    # Body below the roof: tapers toward the nose.
    body = [(cx - w * 0.47, top + s * 0.22), (cx + w * 0.47, top + s * 0.22),
            (cx + w * 0.42, bot - s * 0.2), (cx - w * 0.42, bot - s * 0.2)]
    d.polygon(body, fill=y_c)
    # Windscreen.
    if not mono:
        ws = [(cx - w * 0.38, top + s * 0.26), (cx + w * 0.38, top + s * 0.26),
              (cx + w * 0.33, top + s * 0.52), (cx - w * 0.33, top + s * 0.52)]
        d.polygon(ws, fill=glass)
        d.polygon([(cx - w * 0.3, top + s * 0.28), (cx - w * 0.16, top + s * 0.28), (cx - w * 0.26, top + s * 0.5),
                   (cx - w * 0.33, top + s * 0.5)], fill=GLASS_HI)
        d.line([(cx - w * 0.38, top + s * 0.26), (cx + w * 0.38, top + s * 0.26)], fill=k, width=int(s * 0.02))
    else:
        d.polygon([(cx - w * 0.38, top + s * 0.26), (cx + w * 0.38, top + s * 0.26),
                   (cx + w * 0.33, top + s * 0.52), (cx - w * 0.33, top + s * 0.52)], fill=(0, 0, 0, 0))
    # Nose panel and black stripe.
    d.rectangle([cx - w * 0.36, top + s * 0.55, cx + w * 0.36, top + s * 0.58], fill=k)
    nose = [(cx - w * 0.2, top + s * 0.58), (cx + w * 0.2, top + s * 0.58),
            (cx + w * 0.13, bot - s * 0.16), (cx - w * 0.13, bot - s * 0.16)]
    d.polygon(nose, fill=y_d)
    # Single headlamp with chrome ring.
    lr = s * 0.075
    ly = top + s * 0.67
    d.ellipse([cx - lr * 1.3, ly - lr * 1.3, cx + lr * 1.3, ly + lr * 1.3], fill=CHROME if not mono else k)
    d.ellipse([cx - lr, ly - lr, cx + lr, ly + lr], fill=LAMP if not mono else (0, 0, 0, 0))
    # Indicators.
    for side in (-1, 1):
        x = cx + side * w * 0.34
        d.ellipse([x - s * 0.03, top + s * 0.6, x + s * 0.03, top + s * 0.66], fill=(255, 140, 20) if not mono else k)
    # Front mudguard and the single front wheel.
    d.rounded_rectangle([cx - s * 0.1, bot - s * 0.2, cx + s * 0.1, bot - s * 0.12], radius=s * 0.03, fill=k)
    d.rounded_rectangle([cx - s * 0.055, bot - s * 0.14, cx + s * 0.055, bot + s * 0.02], radius=s * 0.03, fill=TYRE if not mono else k)


def render(size: int, with_bg: bool, scale: float, mono: bool = False) -> Image.Image:
    big = size * SS
    if with_bg:
        img = sunset(big).convert("RGBA")
    else:
        img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if with_bg:
        # Soft contact shadow on the road.
        sh = Image.new("L", (big, big), 0)
        ImageDraw.Draw(sh).ellipse([big * 0.24, big * 0.8, big * 0.76, big * 0.88], fill=140)
        img.paste((0, 0, 0), mask=sh.filter(ImageFilter.GaussianBlur(big * 0.015)))
    auto(d, big * 0.5, big * (0.5 + 0.03 * scale), big * 0.62 * scale, mono)
    return img.resize((size, size), Image.LANCZOS)


def rounded(img: Image.Image, radius_frac: float) -> Image.Image:
    size = img.size[0]
    mask = Image.new("L", (size * SS, size * SS), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size * SS - 1, size * SS - 1], radius=size * SS * radius_frac, fill=255)
    out = img.copy()
    out.putalpha(mask.resize((size, size), Image.LANCZOS))
    return out


def splash() -> Image.Image:
    w, h = 1280, 720
    img = sunset(h).resize((w, h), Image.LANCZOS).convert("RGBA")
    ic = rounded(render(300, True, 1.0), 0.2)
    img.alpha_composite(ic, ((w - 300) // 2, 120))
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype(str(ROOT / "assets/fonts/baloo_thambi_2/BalooThambi2-Variable.ttf"), 84)
    try:
        font.set_variation_by_name("ExtraBold")
    except (OSError, ValueError):
        pass
    text = "NAMMA AUTO"
    tw = d.textlength(text, font=font)
    d.text(((w - tw) / 2, 452), text, font=font, fill=(255, 190, 30), stroke_width=6, stroke_fill=(30, 10, 25))
    return img.convert("RGB")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    rounded(render(512, True, 1.0), 0.2).save(ROOT / "icon.png")
    rounded(render(192, True, 1.0), 0.2).save(OUT / "icon_192.png")
    # Adaptive layers: the launcher masks to a circle/squircle and may crop to the inner 66 %.
    render(432, False, 0.78).save(OUT / "adaptive_fg_432.png")
    sunset(432).save(OUT / "adaptive_bg_432.png")
    render(432, False, 0.78, mono=True).save(OUT / "adaptive_mono_432.png")
    splash().save(OUT / "boot_splash.png")
    print("icons written")


if __name__ == "__main__":
    main()
