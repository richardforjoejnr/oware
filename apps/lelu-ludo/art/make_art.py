#!/usr/bin/env python3
"""Builds Lelu Ludo's in-app art from the owner's source images (art/source/) into the asset catalog.

Run from apps/lelu-ludo:  python3 -m venv .venv && .venv/bin/pip install -r art/requirements.txt
                          .venv/bin/python art/make_art.py
Deterministic: the same sources give the same images. Crops are measured on the sources as given
(2026-10-04); if a source is regenerated, re-measure the boxes below.
"""
import json
import pathlib

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

ROOT = pathlib.Path(__file__).resolve().parent
SRC = ROOT / "source"
OUT = ROOT.parent / "LeluLudo" / "Resources" / "Assets.xcassets" / "Art"


def imageset(name: str, image: Image.Image, scale: str = "3x") -> None:
    folder = OUT / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    image.save(folder / f"{name}.png", optimize=True)
    entry = {"idiom": "universal", "filename": f"{name}.png"}
    if scale:
        entry["scale"] = scale
    (folder / "Contents.json").write_text(json.dumps({"images": [entry], "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")


def clean_cutout(rgba: Image.Image, erode: int = 2) -> Image.Image:
    """Keeps the largest shape, trims the coloured halo the generator left round its edge, and crops tight."""
    a = np.array(rgba.convert("RGBA"))
    solid = a[:, :, 3] > 100
    labels, n = ndimage.label(solid)
    if n > 1:
        sizes = ndimage.sum(solid, labels, range(1, n + 1))
        solid = labels == (1 + int(np.argmax(sizes)))
    solid = ndimage.binary_fill_holes(solid)
    solid = ndimage.binary_erosion(solid, iterations=erode)
    alpha = Image.fromarray((solid * 255).astype("uint8")).filter(ImageFilter.GaussianBlur(1.0))
    a[:, :, 3] = np.array(alpha)
    out = Image.fromarray(a)
    return out.crop(out.getbbox())


def fit(image: Image.Image, height: int) -> Image.Image:
    return image.resize((round(image.width * height / image.height), height), Image.LANCZOS)


def pawns() -> None:
    """Rows of the source: red, yellow, green, blue. Black is the blue pawn turned to ebony (Lelu plays black, not blue)."""
    src = Image.open(SRC / "pieces.png").convert("RGBA")
    rows = {"red": (11, 260), "yellow": (278, 530), "green": (547, 802), "black": (817, 1074)}
    for name, (y0, y1) in rows.items():
        pawn = clean_cutout(src.crop((248, y0, 433, y1)))
        if name == "black":
            a = np.array(pawn).astype(float)
            lum = 0.3 * a[:, :, 0] + 0.59 * a[:, :, 1] + 0.11 * a[:, :, 2]
            l = np.clip((lum - 10) / 150, 0, 1) ** 0.9
            a[:, :, 0], a[:, :, 1], a[:, :, 2] = 28 + l * 150, 24 + l * 135, 22 + l * 120
            pawn = Image.fromarray(a.astype("uint8"))
        imageset(f"Pawn-{name}", fit(pawn, 240))


# The dice sheet's front faces: (row, column) of each value; the 6 is the black star. The 2 is made
# from the 1 (see two_from_one).
DIE_FACES = {1: (0, 1), 3: (0, 2), 4: (1, 2), 5: (0, 3), 6: (1, 0), "flag": (0, 0)}


def dice() -> None:
    src = Image.open(SRC / "dice.png").convert("RGBA")
    xs = [545, 770, 995, 1225, 1445]
    ys = [595, 812, 1030]
    for value, (r, c) in DIE_FACES.items():
        die = clean_cutout(src.crop((xs[c], ys[r], xs[c + 1], ys[r + 1])), erode=3)
        die = fit(die, 240)
        imageset(f"Die-{value}", die)
        if value == 1:
            imageset("Die-2", two_from_one(die))
    imageset("DiceCup", fit(clean_cutout(src.crop((10, 40, 510, 1030))), 360))
    return src


def board_parts() -> None:
    board = Image.open(SRC / "board-top.png").convert("RGB")
    # The carved front of the box: LELU LUDO between Adinkra and chevrons. The beige table showing
    # round its brass corners becomes transparent.
    plaque = np.array(board.crop((122, 884, 1330, 1036)).convert("RGBA")).astype(int)
    r, g, b = plaque[:, :, 0], plaque[:, :, 1], plaque[:, :, 2]
    mx, mn = np.maximum(np.maximum(r, g), b), np.minimum(np.minimum(r, g), b)
    table = (mx > 170) & ((mx - mn) / np.maximum(mx, 1) < 0.33)
    plaque[:, :, 3] = np.where(table, 0, 255)
    imageset("BoardPlaque", Image.fromarray(plaque.astype("uint8")))
    # Frame wood: the left rail's grain, as a texture the board's frame repeats.
    rail = board.crop((150, 150, 232, 790)).resize((96, 768), Image.LANCZOS)
    imageset("WoodGrain", rail, scale="")


def grain(size: int, light: tuple, dark: tuple, seed: int) -> Image.Image:
    """Straight wood grain between two colours (generated, tileable sideways)."""
    rng = np.random.default_rng(seed)
    w = h = size
    x = np.arange(w)[None, :] * np.ones((h, 1))
    y = np.arange(h)[:, None] * np.ones((1, w))
    lines = np.zeros((h, w))
    for k in (3, 7, 13, 29, 53):
        phase = rng.uniform(0, 2 * np.pi)
        wobble = 2.5 * np.sin(2 * np.pi * y / h * rng.integers(1, 3) + phase) * size / 512
        lines += np.sin(2 * np.pi * (x + wobble) * k / w + phase) / k ** 0.6
    lines = (lines - lines.min()) / (lines.max() - lines.min())
    noise = ndimage.gaussian_filter(rng.normal(size=(h, w)), (6 * size / 512, 0.6), mode="wrap")
    t = np.clip(lines * 0.75 + noise * 0.9 + 0.1, 0, 1)[..., None] * 0.55
    rgb = np.array(light)[None, None, :] * (1 - t) + np.array(dark)[None, None, :] * t
    return Image.fromarray(rgb.astype("uint8"))


def maple() -> None:
    """The board's squares: pale maple with a fine straight grain."""
    imageset("Maple", grain(512, (238, 224, 194), (214, 191, 150), seed=7), scale="")
    # Behind the screens: dark mahogany, seamless both ways (the rail crop shows a seam when repeated).
    imageset("DarkWood", grain(512, (96, 52, 30), (34, 16, 9), seed=5), scale="")


def menu() -> None:
    src = Image.open(SRC / "menu.png").convert("RGB")
    imageset("MenuTitle", src.crop((64, 124, 882, 348)))
    tiles = {"start": (50, 398, 316, 650), "friends": (634, 398, 898, 650), "settings": (544, 1302, 794, 1546)}
    for name, box in tiles.items():
        imageset(f"Tile-{name}", src.crop(box))


def app_icon() -> None:
    """The star die on dark wood: the black star 6 is Lelu Ludo's mark."""
    wood = grain(1024, (112, 58, 34), (40, 18, 10), seed=11).rotate(90)
    a = np.array(wood).astype(float)
    yy, xx = np.mgrid[0:1024, 0:1024]
    glow = 1.25 - 0.6 * (((xx - 512) ** 2 + (yy - 470) ** 2) ** 0.5 / 724)
    a = np.clip(a * glow[..., None], 0, 255)
    icon = Image.fromarray(a.astype("uint8"))
    die = Image.open(OUT / "Die-6.imageset" / "Die-6.png")
    die = fit(die, 700)
    shadow = Image.new("RGBA", icon.size, (0, 0, 0, 0))
    sx, sy = (1024 - die.width) // 2, (1024 - die.height) // 2 + 20
    sh = Image.new("RGBA", die.size, (0, 0, 0, 160))
    shadow.paste(sh, (sx + 18, sy + 30), die)
    shadow = shadow.filter(ImageFilter.GaussianBlur(24))
    icon = Image.alpha_composite(icon.convert("RGBA"), shadow)
    icon.alpha_composite(die, (sx, sy))
    folder = ROOT.parent / "LeluLudo" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
    icon.convert("RGB").save(folder / "AppIcon.png", optimize=True)   # no transparency, as the App Store requires
    (folder / "Contents.json").write_text(json.dumps({
        "images": [{"idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": "AppIcon.png"}],
        "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")


def two_from_one(one: Image.Image) -> Image.Image:
    """The sheet has no die showing 2 on its front (the one at row 1, column 1 shows 1 in front and 2
    on its side), so the 2 is made from the 1: the centre pip is covered with wood from the same face
    and the pip is set down twice on the diagonal."""
    a = np.array(one).astype(float)
    dark = (a[:, :, :3].sum(2) < 150) & (a[:, :, 3] > 200)
    labels, n = ndimage.label(dark)
    boxes = ndimage.find_objects(labels)
    front = min(range(n), key=lambda i: boxes[i][1].start)        # the leftmost pip is the front face's
    ys, xs = boxes[front]
    cy, cx = (ys.start + ys.stop) // 2, (xs.start + xs.stop) // 2
    h, w = ys.stop - ys.start + 10, xs.stop - xs.start + 10
    pip = a[cy - h // 2:cy + h // 2, cx - w // 2:cx + w // 2].copy()
    wood = a[cy - h // 2:cy + h // 2, cx + w - w // 2:cx + w + w // 2].copy()
    yy, xx = np.mgrid[0:h // 2 * 2, 0:w // 2 * 2]
    soft = np.clip(1.6 - (((yy - h / 2) / (h / 2)) ** 2 + ((xx - w / 2) / (w / 2)) ** 2), 0, 1)[..., None]
    region = a[cy - h // 2:cy + h // 2, cx - w // 2:cx + w // 2]
    region[:, :, :3] = region[:, :, :3] * (1 - soft) + wood[:, :, :3] * soft
    pip_mask = (pip[:, :, :3].sum(2) < 260)[..., None] * 1.0
    pip_mask = ndimage.gaussian_filter(pip_mask, (0.8, 0.8, 0))
    for dy, dx in ((-int(h * 0.8), -int(w * 0.85)), (int(h * 0.8), int(w * 0.85))):
        y0, x0 = cy + dy - h // 2, cx + dx - w // 2
        target = a[y0:y0 + pip.shape[0], x0:x0 + pip.shape[1]]
        target[:, :, :3] = target[:, :, :3] * (1 - pip_mask) + pip[:, :, :3] * pip_mask
    return Image.fromarray(a.astype("uint8"))


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    pawns()
    dice()
    board_parts()
    maple()
    menu()
    app_icon()
    print("art written to", OUT)
