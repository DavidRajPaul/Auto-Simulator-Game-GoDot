#!/usr/bin/env python3
"""Art for the game-style daily reminder notification (android_plugins/namma_reminder).

Builds, from the game's own art (assets/ui/rewards.png, assets/ui/loading_bg.jpg, assets/icon/icon.png):
  res/drawable-nodpi/namma_notif_art_<look>.webp   right-hand hero art of the expanded card
                                                    (transparent left edge, so it melts into the gradient)
  res/drawable-nodpi/namma_notif_icon_<look>.webp  round badge for the collapsed row
Looks: bonus (coin pile on a sunburst), streak (coin stack + flame-orange burst),
jackpot (gift + gold badge on a gold burst), street (the night-street auto from the loading screen).
The gradients, pills and text live in res/drawable + res/layout, so the card stretches to any width
(phones and the OnePlus Pad) without cropping the art.

Also writes docs/images/notification_preview.png: a mock of the collapsed and expanded cards.
Usage: python3 tools/art/make_notification_art.py
"""
from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
RES = ROOT / "android_plugins" / "namma_reminder" / "src" / "main" / "res" / "drawable-nodpi"
PREVIEW = ROOT / "docs" / "images" / "notification_preview.png"
REWARDS = Image.open(ROOT / "assets" / "ui" / "rewards.png").convert("RGBA")
STREET = Image.open(ROOT / "assets" / "ui" / "loading_bg.jpg").convert("RGBA")
ICON = Image.open(ROOT / "assets" / "icon" / "icon.png").convert("RGBA")
CELL = 256
CELLS = ["coin", "coins", "coin_pile", "star", "star_half", "star_empty", "xp", "lpg",
         "tick", "gift", "lock", "badge_bronze", "badge_silver", "badge_gold", "badge_ruby", "badge_diamond"]

ART_H = 480  # expanded card is 168 dp: 480 px is ~xxhdpi
ART_W = 600


def cell(name: str, size: int) -> Image.Image:
    i = CELLS.index(name)
    x, y = (i % 4) * CELL, (i // 4) * CELL
    return REWARDS.crop((x, y, x + CELL, y + CELL)).resize((size, size), Image.LANCZOS)


def sunburst(w: int, h: int, cx: float, cy: float, rgb: tuple[int, int, int], rays: int = 18) -> Image.Image:
    """Alternating rays with a soft radial glow, fading out towards the edges."""
    s = 2
    img = Image.new("RGBA", (w * s, h * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    r = max(w, h) * s * 1.2
    for k in range(rays):
        a0 = (k / rays) * math.tau
        a1 = a0 + math.tau / rays * 0.5
        d.polygon([(cx * s, cy * s), (cx * s + r * math.cos(a0), cy * s + r * math.sin(a0)),
                   (cx * s + r * math.cos(a1), cy * s + r * math.sin(a1))], fill=rgb + (95,))
    img = img.resize((w, h), Image.LANCZOS)
    glow = Image.new("L", (w, h), 0)
    gd = ImageDraw.Draw(glow)
    for i in range(60, 0, -1):
        rr = i / 60 * min(w, h) * 0.62
        gd.ellipse((cx - rr, cy - rr, cx + rr, cy + rr), fill=int(255 * (1 - i / 60) ** 1.4))
    core = Image.new("RGBA", (w, h), rgb + (0,))
    core.putalpha(glow.point(lambda v: int(v * 0.85)))
    # rays fade with distance from the centre
    fade = Image.new("L", (w, h), 0)
    fd = ImageDraw.Draw(fade)
    for i in range(80, 0, -1):
        rr = i / 80 * max(w, h) * 0.75
        fd.ellipse((cx - rr, cy - rr, cx + rr, cy + rr), fill=int(255 * (1 - i / 80)))
    img.putalpha(Image.composite(img.getchannel("A"), Image.new("L", (w, h), 0), fade))
    return Image.alpha_composite(img, core)


def sparkles(img: Image.Image, spots: list[tuple[float, float, float]]) -> None:
    d = ImageDraw.Draw(img)
    for x, y, r in spots:
        d.polygon([(x, y - r), (x + r * 0.22, y - r * 0.22), (x + r, y), (x + r * 0.22, y + r * 0.22),
                   (x, y + r), (x - r * 0.22, y + r * 0.22), (x - r, y), (x - r * 0.22, y - r * 0.22)],
                  fill=(255, 250, 220, 235))


def shadowed(img: Image.Image, blur: int = 10) -> Image.Image:
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    sh.putalpha(img.getchannel("A").point(lambda v: int(v * 0.55)))
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.alpha_composite(sh, (0, 8))
    out.alpha_composite(img)
    return out


def left_fade(img: Image.Image, frac: float) -> Image.Image:
    """Fades the left `frac` of the image to transparent so it melts into the card gradient."""
    w, h = img.size
    mask = Image.new("L", (w, h), 255)
    md = ImageDraw.Draw(mask)
    edge = int(w * frac)
    for x in range(edge):
        md.line([(x, 0), (x, h)], fill=int(255 * (x / edge) ** 1.6))
    a = Image.composite(img.getchannel("A"), Image.new("L", (w, h), 0), mask)
    out = img.copy()
    out.putalpha(a)
    return out


def art_bonus() -> Image.Image:
    img = sunburst(ART_W, ART_H, ART_W * 0.62, ART_H * 0.5, (255, 200, 60))
    img.alpha_composite(shadowed(cell("coin_pile", 330)), (int(ART_W * 0.62 - 165), int(ART_H * 0.5 - 150)))
    img.alpha_composite(shadowed(cell("coin", 140)), (int(ART_W * 0.62 + 95), int(ART_H * 0.5 + 45)))
    sparkles(img, [(ART_W * 0.42, ART_H * 0.22, 22), (ART_W * 0.9, ART_H * 0.7, 18), (ART_W * 0.5, ART_H * 0.82, 14)])
    return left_fade(img, 0.28)


def art_streak() -> Image.Image:
    img = sunburst(ART_W, ART_H, ART_W * 0.62, ART_H * 0.5, (255, 120, 40), rays=22)
    img.alpha_composite(shadowed(cell("coins", 300)), (int(ART_W * 0.62 - 150), int(ART_H * 0.5 - 130)))
    img.alpha_composite(shadowed(cell("star", 120)), (int(ART_W * 0.62 + 100), int(ART_H * 0.5 + 60)))
    sparkles(img, [(ART_W * 0.44, ART_H * 0.25, 20), (ART_W * 0.88, ART_H * 0.78, 16)])
    return left_fade(img, 0.28)


def art_jackpot() -> Image.Image:
    img = sunburst(ART_W, ART_H, ART_W * 0.6, ART_H * 0.5, (255, 215, 80), rays=24)
    img.alpha_composite(shadowed(cell("badge_gold", 190)), (int(ART_W * 0.6 + 20), int(ART_H * 0.5 - 130)))
    img.alpha_composite(shadowed(cell("gift", 300)), (int(ART_W * 0.6 - 190), int(ART_H * 0.5 - 120)))
    img.alpha_composite(shadowed(cell("coin", 110)), (int(ART_W * 0.6 + 150), int(ART_H * 0.5 + 90)))
    sparkles(img, [(ART_W * 0.4, ART_H * 0.2, 24), (ART_W * 0.92, ART_H * 0.3, 18), (ART_W * 0.55, ART_H * 0.86, 16)])
    return left_fade(img, 0.25)


def art_street() -> Image.Image:
    # Loading-screen night street around the auto (1280×720 source), headlight glow included.
    crop = STREET.crop((420, 390, 900, 720)).resize((int(480 * ART_H / 330), ART_H), Image.LANCZOS)
    w = crop.width
    out = left_fade(crop, 0.38)
    # soft top fade so the strip of shop signs does not fight the title
    top = Image.new("L", out.size, 255)
    td = ImageDraw.Draw(top)
    for y in range(110):
        td.line([(0, y), (w, y)], fill=int(255 * (y / 110) ** 1.5))
    out.putalpha(Image.composite(out.getchannel("A"), Image.new("L", out.size, 0), top))
    return out


def round_badge(src: Image.Image, size: int, ring: tuple[int, int, int], bg: tuple[int, int, int] | None) -> Image.Image:
    s = 4
    big = size * s
    out = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(out)
    d.ellipse((0, 0, big - 1, big - 1), fill=ring + (255,))
    inner = int(big * 0.08)
    if bg is not None:
        d.ellipse((inner, inner, big - inner, big - inner), fill=bg + (255,))
    pic = src.resize((big - inner * 2, big - inner * 2), Image.LANCZOS)
    m = Image.new("L", pic.size, 0)
    ImageDraw.Draw(m).ellipse((0, 0, pic.width - 1, pic.height - 1), fill=255)
    pa = Image.composite(pic.getchannel("A"), Image.new("L", pic.size, 0), m)
    pic.putalpha(pa)
    out.alpha_composite(pic, (inner, inner))
    return out.resize((size, size), Image.LANCZOS)


def icon_on(name: str, bg: tuple[int, int, int]) -> Image.Image:
    base = Image.new("RGBA", (256, 256), bg + (255,))
    base.alpha_composite(cell(name, 210), (23, 23))
    return base


def save(img: Image.Image, name: str) -> Path:
    RES.mkdir(parents=True, exist_ok=True)
    p = RES / name
    img.save(p, "WEBP", quality=86, method=6)
    return p


LOOKS = {
    "bonus": (art_bonus, lambda: icon_on("coin_pile", (59, 31, 79))),
    "streak": (art_streak, lambda: icon_on("coins", (120, 30, 20))),
    "jackpot": (art_jackpot, lambda: icon_on("gift", (90, 20, 70))),
    "street": (art_street, lambda: ICON.crop((40, 20, 470, 450))),
}
# Card gradients (same as res/drawable/namma_notif_bg_<look>.xml), for the preview only.
GRADIENTS = {
    "bonus": ((59, 31, 79), (196, 74, 36)),
    "streak": ((110, 18, 30), (232, 96, 30)),
    "jackpot": ((88, 18, 90), (214, 140, 20)),
    "street": ((22, 18, 48), (59, 31, 79)),
}


def gradient(w: int, h: int, a: tuple[int, int, int], b: tuple[int, int, int], r: int) -> Image.Image:
    g = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(g)
    for x in range(w):
        t = x / max(1, w - 1)
        d.line([(x, 0), (x, h)], fill=tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3)) + (255,))
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, w - 1, h - 1), r, fill=255)
    g.putalpha(m)
    return g


def preview(arts: dict[str, Image.Image], icons: dict[str, Image.Image]) -> None:
    """Rough mock of the notification shade at 3× (360 dp wide phone), for the PR and the owner."""
    px = 3
    W = 360 * px
    font_b = ImageFont.truetype("/usr/share/fonts/truetype/google-fonts/Poppins-Bold.ttf", 17 * px)
    font_r = ImageFont.truetype("/usr/share/fonts/truetype/google-fonts/Poppins-Regular.ttf", 12 * px)
    font_h = ImageFont.truetype("/usr/share/fonts/truetype/google-fonts/Poppins-Regular.ttf", 11 * px)
    font_c = ImageFont.truetype("/usr/share/fonts/truetype/google-fonts/Poppins-Bold.ttf", 12 * px)
    cards = [
        ("bonus", "Daily bonus ready!", "Your ₹50 daily bonus is waiting. Start a new streak today!", "₹50", "CLAIM ₹50", True),
        ("streak", "Keep your 3-day streak!", "Day 4 bonus ₹125 is waiting at the stand", "DAY 4", "CLAIM ₹125", True),
        ("jackpot", "Jackpot day!", "Day 7 bonus ₹500 is ready. Don't break your streak now!", "₹500", "CLAIM ₹500", True),
        ("street", "Passengers waiting!", "Mylapore is busy today. Meter podu, let's go!", "", "DRIVE NOW", True),
        ("bonus", "Daily bonus ready!", "Your ₹50 daily bonus is waiting. Start a new streak today!", "₹50", "", False),
    ]
    blocks: list[Image.Image] = []
    for look, title, body, chip, cta, expanded in cards:
        a, b = GRADIENTS[look]
        content_h = (168 if expanded else 48) * px
        card_h = content_h + (40 + (40 if expanded else 8)) * px
        card = Image.new("RGBA", (W - 24 * px, card_h), (0, 0, 0, 0))
        ImageDraw.Draw(card).rounded_rectangle((0, 0, card.width - 1, card_h - 1), 22 * px, fill=(245, 242, 248, 255))
        d = ImageDraw.Draw(card)
        # system header: small auto icon tinted yellow + app name
        d.ellipse((14 * px, 12 * px, 32 * px, 30 * px), fill=(255, 194, 26, 255))
        d.text((40 * px, 12 * px), "Namma Auto • now", font=font_h, fill=(60, 60, 70, 255))
        cw = card.width - 28 * px
        g = gradient(cw, content_h, a, b, 14 * px)
        if expanded:
            art = arts[look]
            # layout: ImageView in the right 50 % of the card, scaleType fitEnd (bottom-right)
            k = min(content_h / art.height, cw * 0.5 / art.width)
            art = art.resize((int(art.width * k), int(art.height * k)), Image.LANCZOS)
            g.alpha_composite(art, (cw - art.width, content_h - art.height))
            m = Image.new("L", g.size, 0)
            ImageDraw.Draw(m).rounded_rectangle((0, 0, cw - 1, content_h - 1), 14 * px, fill=255)
            g.putalpha(Image.composite(g.getchannel("A"), Image.new("L", g.size, 0), m))
            gd = ImageDraw.Draw(g)
            tx = 16 * px
            gd.text((tx + 2, 18 * px + 3), title, font=font_b, fill=(0, 0, 0, 150))
            gd.text((tx, 18 * px), title, font=font_b, fill=(255, 194, 26, 255))
            words, line, y = body.split(), "", 48 * px
            maxw = cw * 0.56
            for wd in words:
                t = (line + " " + wd).strip()
                if gd.textlength(t, font=font_r) > maxw:
                    gd.text((tx, y), line, font=font_r, fill=(255, 246, 227, 255))
                    y += 17 * px
                    line = wd
                else:
                    line = t
            gd.text((tx, y), line, font=font_r, fill=(255, 246, 227, 255))
            bw = gd.textlength(cta + "  ›", font=font_c) + 28 * px
            by = content_h - 46 * px
            gd.rounded_rectangle((tx, by + 3 * px, tx + bw, by + 33 * px), 16 * px, fill=(196, 130, 0, 255))
            gd.rounded_rectangle((tx, by, tx + bw, by + 30 * px), 16 * px, fill=(255, 194, 26, 255))
            gd.text((tx + 14 * px, by + 6 * px), cta + "  ›", font=font_c, fill=(38, 26, 0, 255))
            if chip:
                cwid = gd.textlength(chip, font=font_c) + 20 * px
                gd.rounded_rectangle((cw - cwid - 10 * px, 10 * px, cw - 10 * px, 34 * px), 12 * px, fill=(232, 57, 46, 255))
                gd.text((cw - cwid, 13 * px), chip, font=font_c, fill=(255, 255, 255, 255))
        else:
            gd = ImageDraw.Draw(g)
            ic = icons[look].resize((36 * px, 36 * px), Image.LANCZOS)
            g.alpha_composite(ic, (8 * px, 6 * px))
            gd.text((52 * px, 4 * px), title, font=font_c, fill=(255, 194, 26, 255))
            gd.text((52 * px, 23 * px), body[:38] + "…", font=font_h, fill=(255, 246, 227, 255))
            if chip:
                cwid = gd.textlength(chip, font=font_c) + 20 * px
                gd.rounded_rectangle((cw - cwid - 10 * px, 12 * px, cw - 10 * px, 36 * px), 12 * px, fill=(255, 194, 26, 255))
                gd.text((cw - cwid, 15 * px), chip, font=font_c, fill=(38, 26, 0, 255))
        card.alpha_composite(g, (14 * px, 38 * px))
        if expanded and cta:
            d.text((26 * px, 38 * px + content_h + 10 * px), cta.title(), font=font_c, fill=(150, 100, 0, 255))
        blocks.append(card)
    H = sum(b.height for b in blocks) + 12 * px * (len(blocks) + 1)
    sheet = Image.new("RGBA", (W, H), (30, 30, 36, 255))
    y = 12 * px
    for bl in blocks:
        sheet.alpha_composite(bl, (12 * px, y))
        y += bl.height + 12 * px
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").resize((W // 2, H // 2), Image.LANCZOS).save(PREVIEW, quality=90)


def main() -> None:
    arts: dict[str, Image.Image] = {}
    icons: dict[str, Image.Image] = {}
    for look, (make_art, make_icon) in LOOKS.items():
        arts[look] = make_art()
        ring = (255, 194, 26)
        icons[look] = round_badge(make_icon(), 144, ring, None)
        a = save(arts[look], f"namma_notif_art_{look}.webp")
        i = save(icons[look], f"namma_notif_icon_{look}.webp")
        print(f"{a.name}: {a.stat().st_size // 1024} KB, {i.name}: {i.stat().st_size // 1024} KB")
    preview(arts, icons)
    print(PREVIEW)


if __name__ == "__main__":
    main()
