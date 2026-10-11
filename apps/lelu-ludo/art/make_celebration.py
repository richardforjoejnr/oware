#!/usr/bin/env python3
"""Builds the win, lose and home-run art from the owner's pack (art/source/celebration/, 2026-10-10)
into the asset catalog: a blank speech bubble and ribbons (the words are set in the app, so they can
be corrected and read aloud), cheering and toppled pawns in all four colours, and three glows.

Run from apps/lelu-ludo:  .venv/bin/python art/make_celebration.py   (see make_art.py for the venv)
"""
import numpy as np
from PIL import Image
from scipy import ndimage

from make_art import ROOT, imageset

SRC = ROOT / "source" / "celebration"
# Left to right on the pawn sheets.
COLOURS = ["red", "yellow", "green", "black"]


def trim(image: Image.Image, pad: int = 4) -> Image.Image:
    """Cropped to what can be seen, with a little room so soft edges are not cut."""
    a = np.array(image)[:, :, 3]
    ys, xs = np.nonzero(a > 8)
    return image.crop((max(xs.min() - pad, 0), max(ys.min() - pad, 0),
                       min(xs.max() + pad + 1, image.width), min(ys.max() + pad + 1, image.height)))


def fit(image: Image.Image, longest: int) -> Image.Image:
    scale = longest / max(image.size)
    return image if scale >= 1 else image.resize((round(image.width * scale), round(image.height * scale)), Image.LANCZOS)


def pawns(sheet: str) -> list[Image.Image]:
    """The four pawns of a sheet, left to right, each with the little emphasis marks drawn beside it:
    the four largest shapes are the pawns, and every mark goes with the pawn nearest to it."""
    image = Image.open(SRC / sheet).convert("RGBA")
    solid = np.array(image)[:, :, 3] > 40
    labels, n = ndimage.label(solid)
    sizes = ndimage.sum(solid, labels, range(1, n + 1))
    order = np.argsort(sizes)[::-1]
    bodies = sorted(order[:4] + 1, key=lambda k: ndimage.center_of_mass(labels == k)[1])
    marks = [k + 1 for k in order[4:] if sizes[k] >= 400]   # smaller specks are the generator's noise
    boxes = {k: ndimage.find_objects(labels == k)[0] for k in bodies}

    def gap(k: int, box) -> float:
        cy, cx = ndimage.center_of_mass(labels == k)
        dy = max(box[0].start - cy, 0, cy - box[0].stop)
        dx = max(box[1].start - cx, 0, cx - box[1].stop)
        return float(np.hypot(dx, dy))

    groups = {k: [k] for k in bodies}
    for m in marks:
        groups[min(bodies, key=lambda k: gap(m, boxes[k]))].append(m)
    rgba = np.array(image)
    out = []
    for k in bodies:
        keep = ndimage.binary_dilation(np.isin(labels, groups[k]), iterations=6)   # with its soft edge
        piece = rgba.copy()
        piece[~keep, 3] = 0
        out.append(trim(Image.fromarray(piece)))
    return out


def main() -> None:
    # The green and red bubbles are in the pack too, kept in source/ for a later use.
    imageset("Bubble-yellow", fit(trim(Image.open(SRC / "bubble-yellow.png").convert("RGBA")), 720))
    for name in ("ribbon-green", "ribbon-red"):
        imageset("Ribbon-" + name.split("-")[1], fit(trim(Image.open(SRC / f"{name}.png").convert("RGBA")), 1050))
    for colour, pawn in zip(COLOURS, pawns("pawns-cheering.png")):
        imageset(f"Cheer-{colour}", fit(pawn, 360))
    for colour, pawn in zip(COLOURS, pawns("pawns-toppled.png")):
        imageset(f"Toppled-{colour}", fit(pawn, 420))
    for name, size in (("ring", 540), ("rays", 720), ("sparkles", 720)):
        imageset(f"Glow-{name}", fit(trim(Image.open(SRC / f"glow-{name}.png").convert("RGBA")), size))


if __name__ == "__main__":
    main()
