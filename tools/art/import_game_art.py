"""Turns the Stitch art (assets_src/incoming/art, 1A-2I from docs prompt pack) into game files.

Raw images are flat RGB, several with a checkerboard painted in where transparency should be,
so backgrounds are removed by flood-filling low-saturation pixels from the image border (icons
have dark outlines that stop the fill). Outputs are small and packed for mobile:

  assets/ui/controls_v2.png      one 1536x768 atlas, 192 px cells (order = CELLS below)
  assets/ui/hud_v2.png           dashboard dials, needle, map frame + pins, fare meter, banners, burst
                                 (2048x1024; regions = HUD_SLOTS below, mirrored in TouchHUD.HUD_REGIONS)
  assets/ui/rewards.png          coins, stars, XP, LPG, tick, gift, padlock + 5 driver badges (5A, 5B)
                                 (1024x1024, 256 px cells; order = REWARD_CELLS, mirrored in UIKit.REWARD_CELLS)
  assets/ui/logo.png             game logo cut out, 1024 px wide
  assets/ui/loading_bg.jpg       loading screen backdrop (1F night street), 1280x720
  assets/icon/icon.png + icon/*  launcher + adaptive icons (1B / 1D), boot splash (1E)

Run: python3 tools/art/import_game_art.py   (Pillow, numpy, scipy)
"""
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "assets_src" / "incoming" / "art"
UI = ROOT / "assets" / "ui"
ICON = ROOT / "assets" / "icon"
CELL = 192
COLS = 8
# Atlas order; TouchHUD.ART_CELLS uses the same indices.
CELLS = ["steer_left", "steer_left_p", "steer_right", "steer_right_p", "gas", "gas_p", "brake", "brake_p",
         "gear_d", "gear_d_p", "gear_r", "gear_r_p", "horn", "horn_p", "air_horn", "air_horn_p",
         "camera", "camera_p", "ind_left", "ind_left_on", "ind_right", "ind_right_on", "handbrake", "handbrake_p",
         "kick", "kick_p", "wiper", "wiper_p", "pause", "pause_p", "ripple"]


def src(prefix: str) -> Path:
    return next(SRC.glob(prefix + "*.png"))


def cutout(path: Path, sat_max: int = 28, val_min: int = 150) -> np.ndarray:
    im = np.asarray(Image.open(path).convert("RGB")).astype(np.int16)
    mx, mn = im.max(2), im.min(2)
    bgish = ((mx - mn) <= sat_max) & (mx >= val_min)
    # Some exports have a thin black frame; count the outer 6 px as background so the fill gets in.
    bgish[:6], bgish[-6:], bgish[:, :6], bgish[:, -6:] = True, True, True, True
    lab, _ = ndimage.label(bgish)
    edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    keep = ~np.isin(lab, list(edge))
    keep = ndimage.binary_opening(keep, iterations=1)
    alpha = np.clip(ndimage.gaussian_filter(keep.astype(np.float32), 0.8), 0, 1)
    return np.dstack([im.astype(np.uint8), (alpha * 255).astype(np.uint8)])


def pieces(rgba: np.ndarray, min_frac: float = 0.01) -> list[Image.Image]:
    """Each separate icon in reading order (rows, then left to right)."""
    a = rgba[..., 3] > 128
    lab, _ = ndimage.label(ndimage.binary_closing(a, iterations=3))
    boxes = []
    for sl in ndimage.find_objects(lab):
        h, w = sl[0].stop - sl[0].start, sl[1].stop - sl[1].start
        if h * w >= min_frac * a.size:
            boxes.append((sl[0].start, sl[1].start, sl[0].stop, sl[1].stop))
    boxes.sort(key=lambda b: (round(b[0] / 80), b[1]))
    img = Image.fromarray(rgba, "RGBA")
    return [img.crop((x0, y0, x1, y1)) for y0, x0, y1, x1 in boxes]


def round_mask(img: Image.Image, radius_frac: float = 0.2) -> Image.Image:
    """Clip to the button's rounded-square base (painted checker can sit in the corners)."""
    from PIL import ImageDraw
    m = Image.new("L", img.size, 0)
    r = round(min(img.size) * radius_frac)
    ImageDraw.Draw(m).rounded_rectangle([1, 1, img.width - 2, img.height - 2], radius=r, fill=255)
    out = img.copy()
    out.putalpha(Image.fromarray(np.minimum(np.asarray(img.getchannel("A")), np.asarray(m))))
    return out


def flatten_checker(img: Image.Image, base: tuple[int, int, int] = (58, 44, 62), sat_max: int = 26) -> Image.Image:
    """Repaint mid-grey, unsaturated pixels (a checkerboard painted inside a 'see-through' base)
    as the solid dark base colour. Bright whites and coloured art are left alone."""
    a = np.asarray(img).copy()
    rgb = a[..., :3].astype(np.int16)
    sat = rgb.max(2) - rgb.min(2)
    val = rgb.max(2)
    hit = (sat < sat_max) & (val > 55) & (val < 185) & (a[..., 3] > 0)
    a[hit, 0], a[hit, 1], a[hit, 2] = base
    return Image.fromarray(a, "RGBA")


def glow_only(path: Path) -> Image.Image:
    """Ripple frames: keep the coloured glow, drop every grey pixel (painted checker inside the ring too)."""
    im = np.asarray(Image.open(path).convert("RGB")).astype(np.float32)
    sat = im.max(2) - im.min(2)
    alpha = np.clip((sat - 35.0) / 70.0, 0, 1) * np.clip(im.max(2) / 160.0, 0, 1)
    return Image.fromarray(np.dstack([im.astype(np.uint8), (alpha * 255).astype(np.uint8)]), "RGBA")


def fit(img: Image.Image, size: int, pad: int = 8) -> Image.Image:
    box = size - pad * 2
    s = min(box / img.width, box / img.height)
    t = img.resize((max(1, round(img.width * s)), max(1, round(img.height * s))), Image.LANCZOS)
    cell = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    cell.alpha_composite(t, ((size - t.width) // 2, (size - t.height) // 2))
    return cell


def cover(img: Image.Image, w: int, h: int) -> Image.Image:
    s = max(w / img.width, h / img.height)
    t = img.resize((round(img.width * s), round(img.height * s)), Image.LANCZOS)
    x, y = (t.width - w) // 2, (t.height - h) // 2
    return t.crop((x, y, x + w, y + h))


def controls() -> None:
    got: dict[str, Image.Image] = {}
    p = pieces(cutout(src("2B")))
    got.update(steer_left=p[0], steer_right=p[1], steer_left_p=p[2], steer_right_p=p[3])
    p = pieces(cutout(src("2C")))
    got.update(gas=p[0], brake=p[1], gas_p=p[2], brake_p=p[3])
    p = pieces(cutout(src("2D")), 0.03)
    got.update(gear_d=p[0], gear_d_p=p[1], gear_r=p[2], gear_r_p=p[3])
    p = pieces(cutout(src("2E")))
    got.update(horn=p[0], air_horn=p[1], horn_p=p[2], air_horn_p=p[3])
    p = pieces(cutout(src("2F"), val_min=90), 0.05)
    got.update(camera=flatten_checker(round_mask(p[0])), camera_p=flatten_checker(round_mask(p[1])))
    p = pieces(cutout(src("2G")))
    got.update(ind_left=flatten_checker(round_mask(p[0]), (90, 66, 82), 48), ind_left_on=flatten_checker(round_mask(p[1]), (90, 66, 82), 48), ind_right=flatten_checker(round_mask(p[2]), (90, 66, 82), 48), ind_right_on=flatten_checker(round_mask(p[3]), (90, 66, 82), 48))
    p = pieces(cutout(src("2H")))  # 4 rows x (handbrake, kick, wiper, pause); row 1 normal, row 4 pressed
    for i, name in enumerate(["handbrake", "kick", "wiper", "pause"]):
        got[name] = p[i]
        got[name + "_p"] = p[12 + i]
    ripple = glow_only(src("2I"))
    w = ripple.width
    frame = ripple.crop((w * 3 // 4 - 60, 0, w, ripple.height))  # last frame: the widest ring
    got["ripple"] = frame.crop(frame.getbbox())
    rows = (len(CELLS) + COLS - 1) // COLS
    atlas = Image.new("RGBA", (COLS * CELL, rows * CELL), (0, 0, 0, 0))
    for i, name in enumerate(CELLS):
        atlas.alpha_composite(fit(got[name], CELL), ((i % COLS) * CELL, (i // COLS) * CELL))
    atlas.save(UI / "controls_v2.png", optimize=True)


def branding() -> None:
    ICON.mkdir(parents=True, exist_ok=True)
    logo = pieces(cutout(src("1G")), 0.2)
    logo_img = max(logo, key=lambda im: im.width * im.height) if len(logo) == 1 else None
    if logo_img is None:  # logo and ribbon are two pieces: take their union
        rgba = cutout(src("1G"))
        ys, xs = np.nonzero(rgba[..., 3] > 128)
        logo_img = Image.fromarray(rgba, "RGBA").crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    s = 1024 / logo_img.width
    logo_img.resize((1024, round(logo_img.height * s)), Image.LANCZOS).save(UI / "logo.png", optimize=True)
    cover(Image.open(src("1F")).convert("RGB"), 1280, 720).save(UI / "loading_bg.jpg", quality=86)
    cover(Image.open(src("1E")).convert("RGB"), 1280, 720).save(ICON / "boot_splash.png", optimize=True)
    icon = Image.open(src("1B")).convert("RGB")
    icon.resize((512, 512), Image.LANCZOS).save(ROOT / "assets" / "icon" / "icon.png", optimize=True)
    icon.resize((192, 192), Image.LANCZOS).save(ICON / "icon_192.png", optimize=True)
    # Adaptive: driver + auto cut out of 1D layer 1, kept inside the 66 % safe circle.
    fg = Image.fromarray(cutout(src("1D.Android_adaptive_icon_layer1"), sat_max=20, val_min=225), "RGBA")
    fg = fg.crop(fg.getbbox())
    fg_cell = fit(fg, 432, pad=round(432 * 0.17))
    fg_cell.save(ICON / "adaptive_fg_432.png", optimize=True)
    Image.open(src("1D.Android_adaptive_icon_layer2")).convert("RGB").resize((432, 432), Image.LANCZOS).save(ICON / "adaptive_bg_432.png")
    mono = Image.new("RGBA", fg_cell.size, (255, 255, 255, 0))
    mono.putalpha(fg_cell.getchannel("A"))
    mono.save(ICON / "adaptive_mono_432.png", optimize=True)


# name -> (x, y, w, h) in assets/ui/hud_v2.png. Keep in sync with TouchHUD.HUD_REGIONS.
HUD_SLOTS = {
    "speedo": (0, 0, 512, 512), "lpg": (512, 0, 384, 384), "map_frame": (896, 0, 512, 512),
    "burst": (1408, 0, 512, 512), "needle": (0, 512, 128, 512), "meter_hire": (128, 512, 512, 256),
    "meter_fare": (640, 512, 512, 256), "pin_player": (1152, 512, 128, 128), "pin_rider": (1280, 512, 128, 128),
    "pin_lpg": (1408, 512, 128, 128), "banner_yellow": (128, 784, 640, 120), "banner_red": (768, 784, 640, 120),
    "banner_green": (1408, 784, 640, 120),
}


def fit_rect(img: Image.Image, w: int, h: int, pad: int = 4) -> Image.Image:
    s = min((w - pad * 2) / img.width, (h - pad * 2) / img.height)
    t = img.resize((max(1, round(img.width * s)), max(1, round(img.height * s))), Image.LANCZOS)
    cell = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    cell.alpha_composite(t, ((w - t.width) // 2, (h - t.height) // 2))
    return cell


def cut_black(path: Path) -> np.ndarray:
    """Ring on a black background: drop near-black regions touching the border or the centre."""
    im = np.asarray(Image.open(path).convert("RGB")).astype(np.int16)
    dark = im.max(2) < 40
    lab, _ = ndimage.label(dark)
    h, w = dark.shape
    seeds = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) | {lab[h // 2, w // 2]}
    keep = ~np.isin(lab, list(seeds - {0}))
    alpha = np.clip(ndimage.gaussian_filter(keep.astype(np.float32), 0.8), 0, 1)
    return np.dstack([im.astype(np.uint8), (alpha * 255).astype(np.uint8)])


def largest(parts: list[Image.Image], n: int) -> list[Image.Image]:
    return sorted(parts, key=lambda im: im.width * im.height, reverse=True)[:n]


def blank_display(img: Image.Image) -> Image.Image:
    """Paint over the baked "Rs 125 / 3.2 km" digits so the game can print the live fare:
    the dark glass + red digits under the digits' centre become one flat dark panel."""
    a = np.asarray(img).copy()
    rgb = a[..., :3].astype(int)
    h = a.shape[0]
    red = (rgb[..., 0] > 140) & (rgb[..., 1] < 120) & (rgb[..., 2] < 120) & (a[..., 3] > 0)
    red[: h // 3] = False  # the red flag on top stays
    ys, xs = np.nonzero(red)
    cy, cx = int(ys.mean()), int(xs.mean())
    glass = (rgb.max(2) < 95) | red
    lab, _ = ndimage.label(ndimage.binary_closing(glass, iterations=2))
    region = ndimage.binary_fill_holes(lab == lab[cy, cx])
    region = ndimage.binary_erosion(region, iterations=2)
    a[region, 0], a[region, 1], a[region, 2] = 22, 8, 12
    ry, rx = np.nonzero(region)
    print(f"  meter display rect (fraction): {rx.min() / a.shape[1]:.3f} {ry.min() / h:.3f} "
          f"{(rx.max() - rx.min()) / a.shape[1]:.3f} {(ry.max() - ry.min()) / h:.3f}")
    return Image.fromarray(a, "RGBA")


def colour_key(path: Path, sat_min: int = 45, grow: int = 6) -> np.ndarray:
    """For art on a dark two-tone checker: keep saturated shapes, fill their holes, and grow a few
    pixels so the dark outline stays. Grey caption text is dropped."""
    im = np.asarray(Image.open(path).convert("RGB")).astype(np.int16)
    sat = im.max(2) - im.min(2)
    m = ndimage.binary_opening(sat > sat_min, iterations=2)
    m = ndimage.binary_fill_holes(ndimage.binary_dilation(m, iterations=grow))
    alpha = np.clip(ndimage.gaussian_filter(m.astype(np.float32), 1.0), 0, 1)
    return np.dstack([im.astype(np.uint8), (alpha * 255).astype(np.uint8)])


def big_parts(parts: list[Image.Image], n: int) -> list[Image.Image]:
    """The n main pieces in reading order, ignoring small caption text the generator added."""
    top = max(im.width * im.height for im in parts)
    return [im for im in parts if im.width * im.height >= 0.4 * top][:n]


def hud() -> None:
    got: dict[str, Image.Image] = {}
    got["speedo"] = largest(pieces(cutout(SRC / "3A.Dashboard_set_speedometer.png")), 1)[0]
    got["needle"] = largest(pieces(cutout(SRC / "3A.Dashboard_set_speedometer_needle.png", sat_max=20, val_min=225)), 1)[0]
    got["lpg"] = largest(pieces(cutout(SRC / "3A.Dashboard_set_LPG_dial.png", sat_max=20, val_min=225)), 1)[0]
    rgba = cut_black(SRC / "3A.Dashboard_set_mini-map_frame.png")
    ys, xs = np.nonzero(rgba[..., 3] > 128)
    got["map_frame"] = Image.fromarray(rgba, "RGBA").crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    # Three pins side by side with captions under them: crop each column above the captions.
    keyed = Image.fromarray(colour_key(src("3B")), "RGBA")
    w, h = keyed.size
    cols = {"pin_player": (0.0, 0.34), "pin_rider": (0.35, 0.65), "pin_lpg": (0.66, 1.0)}
    for name, (c0, c1) in cols.items():
        part = keyed.crop((round(w * c0), round(h * 0.22), round(w * c1), round(h * 0.66)))
        got[name] = part.crop(part.getbbox())
    meters = big_parts(pieces(cutout(src("3C"), val_min=90), 0.05), 2)
    got["meter_hire"], got["meter_fare"] = meters[0], blank_display(meters[1])
    banners = big_parts(pieces(cutout(src("3D"), val_min=90), 0.02), 3)
    got.update(banner_yellow=banners[0], banner_red=banners[1], banner_green=banners[2])
    burst_a = colour_key(src("3E"), sat_min=60, grow=3)
    # The rays were painted see-through, so grey checker squares sit between them: drop light,
    # unsaturated pixels inside the mask (dark outlines stay).
    rgb = burst_a[..., :3].astype(np.int16)
    grey = ((rgb.max(2) - rgb.min(2)) < 40) & (rgb.max(2) > 70)
    burst_a[..., 3] = np.where(grey, 0, burst_a[..., 3])
    burst = Image.fromarray(burst_a, "RGBA")
    got["burst"] = burst.crop(burst.getbbox())
    atlas = Image.new("RGBA", (2048, 1024), (0, 0, 0, 0))
    for name, (x, y, w, h) in HUD_SLOTS.items():
        atlas.alpha_composite(fit_rect(got[name], w, h, 0 if name.startswith("banner") else 4), (x, y))
    atlas.save(UI / "hud_v2.png", optimize=True)


REWARD_CELLS = ["coin", "coins", "coin_pile", "star", "star_half", "star_empty", "xp", "lpg",
                "tick", "gift", "lock", "badge_bronze", "badge_silver", "badge_gold", "badge_ruby", "badge_diamond"]


def flat_cut(path: Path, bg: tuple[int, int, int], tol: int = 11) -> np.ndarray:
    """Art on one flat colour: flood that colour in from the border."""
    im = np.asarray(Image.open(path).convert("RGB")).astype(np.int16)
    near = np.abs(im - np.array(bg)).max(2) <= tol
    near[:4], near[-4:], near[:, :4], near[:, -4:] = True, True, True, True
    lab, _ = ndimage.label(near)
    edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    keep = ndimage.binary_opening(~np.isin(lab, list(edge)), iterations=1)
    alpha = np.clip(ndimage.gaussian_filter(keep.astype(np.float32), 0.8), 0, 1)
    return np.dstack([im.astype(np.uint8), (alpha * 255).astype(np.uint8)])


def split_rows(img: Image.Image) -> list[Image.Image]:
    """Two icons stacked in one piece: cut at the emptiest row near the middle."""
    a = np.asarray(img.getchannel("A")) > 64
    rows = a.sum(1)
    h = len(rows)
    mid = int(np.argmin(rows[h // 4: 3 * h // 4])) + h // 4
    top, bot = img.crop((0, 0, img.width, mid)), img.crop((0, mid, img.width, h))
    return [top.crop(top.getbbox()), bot.crop(bot.getbbox())]


def rewards() -> None:
    r = pieces(flat_cut(SRC / "5A.Reward_icon_sheet.png", (33, 36, 41)), 0.003)
    # Reading order on the sheet: coin, stack, pile, small stars, big empty star, bolt+gift, LPG,
    # big full / half / empty stars, tick, padlock.
    bolt, gift = split_rows(r[5])
    got = {"coin": r[0], "coins": r[1], "coin_pile": r[2], "star": r[7], "star_half": r[8], "star_empty": r[9],
           "xp": bolt, "lpg": r[6], "tick": r[10], "gift": gift, "lock": r[11]}
    badges = pieces(cutout(SRC / "5B.Driver_level_badges.png", val_min=100), 0.02)
    for name, im in zip(["badge_bronze", "badge_silver", "badge_gold", "badge_ruby", "badge_diamond"], badges):
        got[name] = im
    atlas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    for i, name in enumerate(REWARD_CELLS):
        atlas.alpha_composite(fit(got[name], 256, pad=10), ((i % 4) * 256, (i // 4) * 256))
    atlas.save(UI / "rewards.png", optimize=True)


def portraits() -> None:
    """Rider portraits shown inside the Stitch screens (4G haggle, 4F fare). Cropped, rounded."""
    from PIL import ImageDraw
    crops = [(SRC / "screens/4G.Haggle_card/screen.png", (1056, 852, 1400, 1226)),
             (SRC / "screens/4F.Ride_complete-fare_result/screen.png", (132, 1000, 282, 1150))]
    atlas = Image.new("RGBA", (512, 256), (0, 0, 0, 0))
    for i, (path, box) in enumerate(crops):
        im = Image.open(path).convert("RGB").crop(box)
        side = min(im.size)
        im = im.crop(((im.width - side) // 2, (im.height - side) // 2, (im.width + side) // 2, (im.height + side) // 2))
        im = im.resize((248, 248), Image.LANCZOS).convert("RGBA")
        m = Image.new("L", (248, 248), 0)
        ImageDraw.Draw(m).rounded_rectangle([0, 0, 247, 247], radius=40, fill=255)
        im.putalpha(m)
        atlas.alpha_composite(im, (i * 256 + 4, 4))
    atlas.save(UI / "portraits.png", optimize=True)


if __name__ == "__main__":
    portraits()
    rewards()
    hud()
    controls()
    branding()
    print("art imported")
