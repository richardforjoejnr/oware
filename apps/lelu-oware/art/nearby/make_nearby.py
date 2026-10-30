"""Nearby play art: cuts the owner's carved-wood UI kit (ui-kit.png, 2026-10-30) into pieces and
with --install, builds them as imagesets in Oware's asset catalogue (Assets.xcassets/Nearby).

    python3 make_nearby.py             # pieces/ only
    python3 make_nearby.py --install   # and the asset catalogue, once the screens use them

The kit already has a transparent background, so each piece is its box on the sheet, cleared of
any scrap of a neighbour and trimmed to what is drawn. Boxes were measured on the 1536 × 1024
sheet. Pieces land in pieces/ (kept out of the app until a screen uses them). Needs Pillow, NumPy and
SciPy (see ../../../lelu-ludo/art/requirements.txt).

What each piece is for: docs/NEARBY_PLAY_REDESIGN.md, "Assets".
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = Path(__file__).resolve().parent
SHEET = HERE / "ui-kit.png"
PIECES_DIR = HERE / "pieces"
CATALOGUE = HERE.parents[1] / "Oware" / "Resources" / "Assets.xcassets" / "Nearby"

# name: (left, top, right, bottom) on the sheet; every piece drawn inside the box is kept.
PIECES = {
    # Two carved phones, gold (you) and red (them), seeds between: Home ▸ Play nearby.
    "nearby-icon": (19, 61, 317, 310),
    # The phones joined by a line of seeds: the game screen's connection header and the
    # reconnecting indicator (dots can be redrawn in code to pulse).
    "nearby-link": (403, 657, 755, 812),
    # Six seeds in a ring: the searching indicator, turned slowly in code.
    "nearby-seed-ring": (151, 644, 319, 814),
    # Ready seals: gold once a player is ready, dark while waiting.
    "nearby-seal-ready": (722, 506, 867, 652),
    "nearby-seal-waiting": (874, 506, 1014, 649),
    # Status pips: searching (dashed), connected, reconnecting, lost, calling, idle.
    "nearby-pip-searching": (42, 826, 99, 882),
    "nearby-pip-connected": (113, 829, 165, 880),
    "nearby-pip-waiting": (181, 829, 233, 880),
    "nearby-pip-lost": (249, 829, 301, 880),
    "nearby-pip-calling": (317, 828, 371, 881),
    "nearby-pip-idle": (387, 828, 438, 880),
    # Cards and tiles (stretch with cap insets, see the doc).
    "nearby-card-game": (331, 61, 1015, 319),
    "nearby-card-rejoin": (1026, 83, 1514, 299),
    "nearby-tile-gold": (19, 336, 520, 494),
    "nearby-tile-red": (529, 336, 1021, 494),
    "nearby-chip-rule": (16, 512, 353, 614),
    "nearby-chip-start": (356, 513, 701, 614),
    "nearby-sheet": (1024, 308, 1521, 851),
    # Buttons: primary (gold), secondary (wood), leave (red), small.
    "nearby-button-gold": (15, 891, 278, 987),
    "nearby-button-wood": (289, 892, 556, 988),
    "nearby-button-red": (564, 893, 833, 988),
    "nearby-button-small": (842, 891, 996, 994),
    # Carved band with red, gold and green inlays: a divider.
    "nearby-band": (1020, 905, 1520, 968),
}


def cut(sheet: np.ndarray, box: tuple[int, int, int, int]) -> Image.Image:
    left, top, right, bottom = box
    piece = sheet[top:bottom, left:right].copy()
    # Keep what lies mostly inside the box: drop scraps of neighbours that only touch its edge.
    labels, count = ndimage.label(piece[:, :, 3] > 0)
    for i, part in enumerate(ndimage.find_objects(labels), start=1):
        rows, cols = part
        touches = rows.start == 0 or cols.start == 0 or rows.stop == piece.shape[0] or cols.stop == piece.shape[1]
        if touches and (labels == i).sum() < 200:
            piece[labels == i, 3] = 0
    image = Image.fromarray(piece)
    return image.crop(image.getbbox())


def write_imageset(name: str, image: Image.Image) -> None:
    folder = CATALOGUE / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    image.save(folder / f"{name}.png", optimize=True)
    (folder / "Contents.json").write_text(json.dumps({
        "images": [{"filename": f"{name}.png", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2) + "\n")


def main() -> None:
    sheet = np.array(Image.open(SHEET).convert("RGBA"))
    install = "--install" in sys.argv
    PIECES_DIR.mkdir(exist_ok=True)
    if install:
        CATALOGUE.mkdir(parents=True, exist_ok=True)
        (CATALOGUE / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    for name, box in PIECES.items():
        image = cut(sheet, box)
        image.save(PIECES_DIR / f"{name}.png", optimize=True)
        if install:
            write_imageset(name, image)
        print(f"{name:24} {image.width}×{image.height}")


if __name__ == "__main__":
    main()
