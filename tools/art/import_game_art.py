"""Turns the Stitch art (assets_src/incoming/art, 1A-2I from docs prompt pack) into game files.

Raw images are flat RGB, several with a checkerboard painted in where transparency should be,
so backgrounds are removed by flood-filling low-saturation pixels from the image border (icons
have dark outlines that stop the fill). Outputs are small and packed for mobile:

  assets/ui/controls_v2.png      one 1536x768 atlas, 192 px cells (order = CELLS below)
  assets/ui/logo.png             game logo cut out, 1024 px wide
  assets/ui/loading_bg.jpg       loading screen backdrop (1F night street), 1280x720
  icon.png, assets/icon/*        launcher + adaptive icons (1B / 1D), boot splash (1E)

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
    icon.resize((512, 512), Image.LANCZOS).save(ROOT / "icon.png", optimize=True)
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


if __name__ == "__main__":
    controls()
    branding()
    print("art imported")
