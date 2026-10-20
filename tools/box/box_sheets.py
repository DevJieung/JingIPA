#!/usr/bin/env python3
"""Contact sheets of the installed jewel-box art (art/ui/box/) for review records.

    python3 tools/box/box_sheets.py [OUT_DIR]   # default build/feedback-2026-10-19/D1/art

boxes_closed.png  the five closed boxes side by side on the modal's night shade
boxes_open.png    each tier's body + lid at 0 / 6 / 18 / 40 / 70 / 100 / 118 degrees (the hinge frames)
boxes_seam.png    the lid ajar at 6 degrees with the seam light added (the anticipation look)
"""
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
BOX = ROOT / "art/ui/box"
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "build/feedback-2026-10-19/D1/art"
SHADE = (14, 26, 38, 255)


def layout():
    src = (BOX / "box_layout.gd").read_text()
    tiers = {}
    for t in range(1, 6):
        blk = src.split("\t%d: {" % t)[1].split("\n\t},")[0]
        rects = {n: [float(v) for v in vals.split(",")] for n, vals in re.findall(r'"(\w+)": Rect2\(([^)]*)\)', blk)}
        anchor = [float(v) for v in re.search(r'"anchor": Vector2\(([^)]*)\)', blk).group(1).split(",")]
        tiers[t] = {"rects": rects, "anchor": anchor}
    return tiers


def place(canvas, t, name, lay, offset=(0, 0), add=False):
    r = lay[t]["rects"][name]
    im = Image.open(BOX / f"tier{t}/{name}.png").convert("RGBA")
    pos = (int(r[0] + offset[0]), int(r[1] + offset[1]))
    if not add:
        canvas.alpha_composite(im, pos)
        return
    base = np.asarray(canvas).astype(np.float32)
    s = np.asarray(im).astype(np.float32)
    x, y = pos
    h, w = s.shape[:2]
    base[y:y + h, x:x + w, :3] = np.clip(base[y:y + h, x:x + w, :3] + s[..., :3] * s[..., 3:4] / 255.0, 0, 255)
    canvas.paste(Image.fromarray(base.astype(np.uint8)))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    lay = layout()
    size = 820
    crop = (150, 60, 670, 640)
    closed = Image.new("RGBA", ((crop[2] - crop[0]) * 5, crop[3] - crop[1]), SHADE)
    seam = closed.copy()
    for k, t in enumerate(range(1, 6)):
        c = Image.new("RGBA", (size, size), SHADE)
        place(c, t, "closed", lay)
        closed.paste(c.crop(crop), (k * (crop[2] - crop[0]), 0))
        c = Image.new("RGBA", (size, size), SHADE)
        place(c, t, "body", lay)
        place(c, t, "lid_006", lay)
        place(c, t, "seam", lay, add=True)
        seam.paste(c.crop(crop), (k * (crop[2] - crop[0]), 0))
    closed.save(OUT / "boxes_closed.png")
    seam.save(OUT / "boxes_seam.png")
    angles = [0, 6, 18, 40, 70, 100, 118]
    tw, th = 260, 290
    sheet = Image.new("RGBA", (tw * len(angles), th * 5), SHADE)
    for row, t in enumerate(range(1, 6)):
        for col, a in enumerate(angles):
            c = Image.new("RGBA", (size, size), SHADE)
            place(c, t, "body", lay)
            place(c, t, f"lid_{a:03d}", lay)
            sheet.paste(c.crop((120, 20, 700, 667)).resize((tw, th), Image.LANCZOS), (col * tw, row * th))
    sheet.save(OUT / "boxes_open.png")
    print(OUT)


if __name__ == "__main__":
    main()
