"""Side art for the board held upright: the carved rails along each home row, the name plaque on
each rail, and the ring round each house, in gold (South, you) and red (North).

    python3 make_sides.py [SHEETS_DIR]

With SHEETS_DIR (the owner's sheets of 2026-10-10: board.png, plaques.png, bowls.png), first cuts
the pieces out of them into source/. Then builds the imagesets in Oware's asset catalogue from
source/. Needs Pillow, NumPy and SciPy (see ../../../lelu-ludo/art/requirements.txt).
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps
from scipy import ndimage

HERE = Path(__file__).resolve().parent
SOURCE = HERE / "source"
CATALOGUE = HERE.parents[1] / "Oware" / "Resources" / "Assets.xcassets" / "Board"

# (sheet, crop box) for each piece, measured on the 1254×1254 sheets.
PIECES = {
    "rail-gold": ("board.png", (701, 455, 836, 1207)),
    "rail-red": ("board.png", (841, 455, 956, 1207)),
    "plaque-gold": ("plaques.png", (29, 30, 287, 630)),
    "plaque-red": ("plaques.png", (332, 28, 596, 631)),
    "ring-gold": ("bowls.png", (29, 375, 315, 660)),
    "ring-red": ("bowls.png", (330, 375, 612, 658)),
}

# A rail as drawn is about 1:5.6 and changes width along its length; on an upright phone it runs
# about 1:14. So the rail is rebuilt at one width: its even middle section repeated (every other
# copy upside down, so the carving meets itself at each join) between its two rounded ends.
RAIL_ASPECT = 14
# Per rail (as drawn): the even section (top, bottom, left, right) and each end (rows, columns).
RAIL_PARTS = {
    "rail-gold": {"band": (185, 565, 0, 135), "top": (0, 40, 0, 112), "bottom": (715, 752, 0, 101)},
    "rail-red": {"band": (180, 570, 23, 115), "top": (0, 40, 5, 115), "bottom": (715, 752, 0, 112)},
}


def cut(sheets: Path) -> None:
    """Each piece, with any scrap of a neighbouring piece inside its box cleared away."""
    SOURCE.mkdir(exist_ok=True)
    for name, (sheet, box) in PIECES.items():
        piece = np.array(Image.open(sheets / sheet).convert("RGBA").crop(box))
        labels, count = ndimage.label(piece[:, :, 3] > 0)
        if count > 1:
            largest = np.argmax(np.bincount(labels.ravel())[1:]) + 1
            piece[labels != largest, 3] = 0
        Image.fromarray(piece).save(SOURCE / f"{name}.png")


def fill(band: Image.Image, height: int) -> Image.Image:
    """`band` repeated (every other copy upside down) to `height` rows."""
    out = Image.new("RGBA", (band.width, height))
    y, flip = 0, False
    while y < height:
        out.alpha_composite(ImageOps.flip(band) if flip else band, (0, y))
        y += band.height
        flip = not flip
    return out


def long_rail(name: str) -> Image.Image:
    rail = Image.open(SOURCE / f"{name}.png")
    parts = RAIL_PARTS[name]

    def piece(key: str) -> Image.Image:
        top, bottom, left, right = parts[key]
        return rail.crop((left, top, right, bottom))

    band = piece("band")
    ends = [piece(k).resize((band.width, piece(k).height), Image.LANCZOS) for k in ("top", "bottom")]
    total = band.width * RAIL_ASPECT
    middle = fill(band, total - sum(e.height for e in ends))
    out = Image.new("RGBA", (band.width, total))
    out.alpha_composite(ends[0], (0, 0))
    out.alpha_composite(middle, (0, ends[0].height))
    out.alpha_composite(ends[1], (0, total - ends[1].height))
    # As drawn the straight edge is on the gold rail's left and the red rail's right; on the board
    # the straight edge lies along the board's edge (gold on the right, red on the left).
    return ImageOps.mirror(out)


def write_imageset(name: str, image: Image.Image) -> None:
    folder = CATALOGUE / f"{name}.imageset"
    folder.mkdir(exist_ok=True)
    image.save(folder / f"{name}.png", optimize=True)
    (folder / "Contents.json").write_text(json.dumps({
        "images": [{"filename": f"{name}.png", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2) + "\n")


def main() -> None:
    if len(sys.argv) > 1:
        cut(Path(sys.argv[1]))
    write_imageset("railGold", long_rail("rail-gold"))
    write_imageset("railRed", long_rail("rail-red"))
    for colour in ("gold", "red"):
        write_imageset(f"plaque{colour.title()}", Image.open(SOURCE / f"plaque-{colour}.png"))
        write_imageset(f"ring{colour.title()}", Image.open(SOURCE / f"ring-{colour}.png"))


if __name__ == "__main__":
    main()
