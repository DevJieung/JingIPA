#!/usr/bin/env python3
"""Record visually measured release origins and build native review boards."""
from pathlib import Path
import argparse
import json
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "art/animation/roster_v1"
ap = argparse.ArgumentParser()
ap.add_argument("--ids", required=True)
ap.add_argument("--points", default="", help="id:source_x:source_y,...; measured on selected source atlas")
ap.add_argument("--out", default="origins")
a = ap.parse_args()
ids = a.ids.split(",")
point_path = WORK / "source_muzzle_points.json"
points = json.loads(point_path.read_text()) if point_path.exists() else {}
map_path = WORK / "muzzle_map.json"
muzzle = json.loads(map_path.read_text()) if map_path.exists() else {}
for item in a.points.split(",") if a.points else []:
    uid, x, y = item.split(":")
    points[uid] = [float(x), float(y)]
board = Image.new("RGB", (320 * min(4, len(ids)), 330 * ((len(ids) + 3) // 4)), (20, 25, 36))
draw = ImageDraw.Draw(board)
for index, uid in enumerate(ids):
    path = ROOT / "art/anim" / uid / "anim.json"
    meta = json.loads(path.read_text())
    if uid in points and a.points:
        box = meta["readability"]["source_cells"][6]
        transform = meta["readability"]["source_transforms"][6]
        pixel = [round((points[uid][i] - box[i]) * transform["factor"] + transform["offset"][i]) for i in range(2)]
        muzzle[uid] = {"x": pixel[0] - meta["anchor"]["x"], "y": pixel[1] - meta["anchor"]["y"]}
        if muzzle[uid]["x"] <= 0:
            raise ValueError(uid + ": release origin must be right of the feet anchor")
        meta["muzzle_at"] = muzzle[uid]
        path.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n")
    cs = meta["cell"]["w"]
    strip = Image.open(path.parent / (meta["name"] + "_attack.png"))
    hit = meta["clips"]["attack"]["hit_frame"]
    frame = strip.crop((cs * hit, 0, cs * (hit + 1), cs))
    ox, oy = index % 4 * 320, index // 4 * 330 + 30
    board.paste(frame, (ox, oy), frame)
    draw.text((ox + 8, oy - 24), uid + " " + str(meta["muzzle_at"]), fill="white")
    x = ox + meta["anchor"]["x"] + meta["muzzle_at"]["x"]
    y = oy + meta["anchor"]["y"] + meta["muzzle_at"]["y"]
    draw.line((x - 5, y, x + 5, y), fill="red")
    draw.line((x, y - 5, x, y + 5), fill="red")
    draw.line((ox + 80, oy + 225, ox + 180, oy + 225), fill=(60, 80, 95))
if a.points:
    point_path.write_text(json.dumps(points, indent=2) + "\n")
    map_path.write_text(json.dumps(muzzle, indent=2) + "\n")
out = ROOT / "build/all-hero-sprites" / (a.out + ".png")
board.save(out)
print(out)
