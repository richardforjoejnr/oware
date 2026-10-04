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


def pawn_from_above(side: Image.Image, dark: bool = False) -> Image.Image:
    """The same turned-wood pawn seen from straight above (the board is seen from above, as in Lelu
    Oware): a wide bevelled base, a groove, the neck's collar and the round head, lit from the top
    left, in the pawn's own paint with a little grain. Colours come from the side-view pawn."""
    a = np.array(side).astype(float)
    solid = a[..., 3] > 200
    lum = a[..., :3].mean(-1)
    mid = solid & (lum > np.percentile(lum[solid], 35)) & (lum < np.percentile(lum[solid], 80))
    paint = np.median(a[mid][:, :3], axis=0)
    n = 240
    yy, xx = (np.mgrid[0:n, 0:n] - (n - 1) / 2) / (n / 2)       # -1…1
    r = np.hypot(xx, yy)
    light = np.array([-0.45, -0.55, 0.70]); light /= np.linalg.norm(light)

    def dome(radius: float, height: float):
        """Shading of a rounded surface (radius in the -1…1 frame): normal from a squashed sphere."""
        t = np.clip(r / radius, 0, 1)
        nz = np.sqrt(np.clip(1 - t ** 2, 0, 1)) * height + (1 - height) * 0.9
        nx, ny = xx / radius * (1 - height * 0.2), yy / radius * (1 - height * 0.2)
        norm = np.sqrt(nx ** 2 + ny ** 2 + nz ** 2)
        return np.clip((nx * light[0] + ny * light[1] + nz * light[2]) / norm, 0, 1)

    shade = np.zeros((n, n))
    alpha = np.zeros((n, n))
    base, groove, collar, head = 0.97, 0.70, 0.62, 0.50
    shade = np.where(r <= base, 0.35 + 0.65 * dome(base, 0.35), shade)          # the base, a low dome
    shade = np.where((r > groove - 0.035) & (r < groove), shade * 0.55, shade)  # the turned groove
    shade = np.where(r <= collar, 0.30 + 0.70 * dome(collar, 0.6), shade)       # the collar under the head
    shade = np.where(r <= head, 0.25 + 0.80 * dome(head, 1.0), shade)           # the head
    alpha = np.clip((base - r) * n / 2.5, 0, 1)
    # The real paint and wear: a patch of the side-view pawn's body, its light evened out, laid over.
    h, w = a.shape[:2]
    patch = a[int(h * 0.62):int(h * 0.86), int(w * 0.3):int(w * 0.7), :3].mean(-1)
    patch = np.array(Image.fromarray(patch.astype("uint8")).resize((n, n), Image.BICUBIC)).astype(float)
    detail = patch / np.maximum(ndimage.gaussian_filter(patch, 18), 1)
    detail = 1 + (detail - 1) * 0.45
    if dark:
        paint = paint * 0.75
    rgb = paint[None, None, :] * np.clip(shade * 1.1 * detail, 0, 1.5)[..., None]
    # A soft sheen on the head.
    spec = np.exp(-(((xx + 0.16) ** 2 + (yy + 0.19) ** 2) / 0.02)) * (r <= head)
    rgb = rgb + spec[..., None] * (85 if dark else 75)
    out = np.dstack([np.clip(rgb, 0, 255), alpha * 255]).astype("uint8")
    return Image.fromarray(out)


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
        imageset(f"PawnTop-{name}", pawn_from_above(pawn, dark=name == "black"))


# The dice sheet's front faces: (row, column) of each value; the 6 is the black star. The 2 is its own
# image (die-2.png).
DIE_FACES = {1: (0, 1), 3: (0, 2), 4: (1, 2), 5: (0, 3), 6: (1, 0), "flag": (0, 0)}


def dice() -> None:
    src = Image.open(SRC / "dice.png").convert("RGBA")
    xs = [545, 770, 995, 1225, 1445]
    ys = [595, 812, 1030]
    for value, (r, c) in DIE_FACES.items():
        die = clean_cutout(src.crop((xs[c], ys[r], xs[c + 1], ys[r + 1])), erode=3)
        die = fit(die, 240)
        imageset(f"Die-{value}", die)

    # The sheet had no die showing 2 in front; the owner made one to match (die-2.png).
    imageset("Die-2", fit(clean_cutout(Image.open(SRC / "die-2.png").convert("RGBA"), erode=3), 240))
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
    # The frame's top and bottom rails: the same mahogany with its grain running along them.
    imageset("DarkWoodAcross", grain(512, (104, 56, 32), (38, 18, 10), seed=6).rotate(90), scale="")
    # The table: woven sand cloth, seamless both ways.
    rng = np.random.default_rng(3)
    weave = (ndimage.gaussian_filter(rng.normal(size=(256, 256)), (0.5, 3), mode="wrap")
             + ndimage.gaussian_filter(rng.normal(size=(256, 256)), (3, 0.5), mode="wrap"))
    weave = (weave - weave.min()) / (weave.max() - weave.min())
    sand = np.array([222, 199, 166])[None, None, :] * (0.9 + 0.14 * weave[..., None])
    imageset("Linen", Image.fromarray(sand.clip(0, 255).astype("uint8")), scale="")


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


def cut_from_table(rgb: np.ndarray) -> np.ndarray:
    """Alpha for an object photographed on a plain light table: the table is the light, unsaturated
    pixels joined to the picture's edge."""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx, mn = np.maximum(np.maximum(r, g), b), np.minimum(np.minimum(r, g), b)
    # The table and the soft shadow on it: unsaturated, from light down to mid grey-brown.
    tableish = (mx > 85) & ((mx - mn) / np.maximum(mx, 1) < 0.34)
    labels, _ = ndimage.label(tableish)
    edge = set(np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))) - {0}
    thing = ndimage.binary_fill_holes(ndimage.binary_opening(~np.isin(labels, list(edge)), iterations=2))
    thing = ndimage.binary_erosion(thing, iterations=2)   # no rim of table left on the edge
    return np.array(Image.fromarray((thing * 255).astype("uint8")).filter(ImageFilter.GaussianBlur(1.2)))


def support_tile() -> None:
    """The Support tile (for the tip jar), made by the owner to match the menu tiles."""
    rgb = np.array(Image.open(SRC / "tile-support.png").convert("RGB")).astype(int)
    tile = Image.fromarray(np.dstack([rgb, cut_from_table(rgb)]).astype("uint8"))
    tile = tile.crop(tile.getbbox())
    imageset("Tile-support", tile.resize((300, round(tile.height * 300 / tile.width)), Image.LANCZOS))


def blue_to_black(rgb: np.ndarray) -> np.ndarray:
    """Repaints blue (paint and pawns) as Lelu's ebony black, keeping the light and grain."""
    a = rgb.astype(float)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    mx, mn = np.maximum(np.maximum(r, g), b), np.minimum(np.minimum(r, g), b)
    blue = (b == mx) & (b - np.maximum(r, g) > 18) & ((mx - mn) / np.maximum(mx, 1) > 0.28)
    blue = ndimage.binary_closing(blue, iterations=1)
    weight = ndimage.gaussian_filter(blue.astype(float), 0.8)[..., None]
    lum = 0.3 * r + 0.59 * g + 0.11 * b
    l = np.clip((lum - 10) / 170, 0, 1) ** 1.25
    ebony = np.stack([22 + l * 135, 19 + l * 122, 17 + l * 108], -1)
    return a * (1 - weight) + ebony * weight


def board_perspective() -> None:
    """The boxed board in three-quarter view (the menu's centrepiece): blue repainted black, the table
    round it made transparent (light, unsaturated pixels joined to the picture's edge)."""
    rgb = np.array(Image.open(SRC / "board-perspective.png").convert("RGB")).astype(int)
    alpha = cut_from_table(rgb)
    out = np.dstack([blue_to_black(rgb).clip(0, 255), alpha]).astype("uint8")
    image = Image.fromarray(out)
    image = image.crop(image.getbbox())
    imageset("BoardBox", image.resize((image.width * 2 // 3, image.height * 2 // 3), Image.LANCZOS))


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    pawns()
    dice()
    board_parts()
    board_perspective()
    support_tile()
    maple()
    menu()
    app_icon()
    print("art written to", OUT)
