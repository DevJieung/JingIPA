#!/usr/bin/env python3
"""Contact sheet + GIF of a tests/brand/flow_capture.tscn run.  python3 tools/brand/flow_sheet.py <dir>"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw

folder = Path(sys.argv[1])
steps = json.loads((folder / "steps.json").read_text())
boot = [s for s in steps if s["label"].startswith("boot")]
rest = [s for s in steps if not s["label"].startswith("boot")]
# keep every other boot frame so logo, cover and title arrival all show
pick = boot[::max(1, len(boot) // 12)] + rest
tiles = []
for s in pick:
    im = Image.open(folder / s["file"]).convert("RGB")
    tiles.append((im.resize((400, round(im.height * 400 / im.width)), Image.LANCZOS), s["label"]))
tw, th = tiles[0][0].size
cols = 5
rows = (len(tiles) + cols - 1) // cols
sheet = Image.new("RGB", (cols * (tw + 6) + 6, rows * (th + 24) + 6), "#0b141c")
d = ImageDraw.Draw(sheet)
for i, (im, label) in enumerate(tiles):
    x, y = 6 + (i % cols) * (tw + 6), 6 + (i // cols) * (th + 24)
    sheet.paste(im, (x, y))
    d.text((x + 4, y + th + 4), label, fill=(230, 220, 180))
sheet.save(folder / "flow_sheet.png")
frames = [Image.open(folder / s["file"]).convert("RGB").resize((640, round(th * 640 / tw)), Image.LANCZOS) for s in steps]
durations = [120 if s["label"].startswith("boot") else 1400 for s in steps]
frames[0].save(folder / "flow.gif", save_all=True, append_images=frames[1:], duration=durations, loop=0)
print(folder / "flow_sheet.png", len(steps), "frames")
