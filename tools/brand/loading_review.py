#!/usr/bin/env python3
"""Capture the D4 loading-screen study (tests/brand/loading_preview.tscn) at several aspects.

    python3 tools/brand/loading_review.py --art build/feedback-2026-10-19/D4/keyart/keyart_master.png
    python3 tools/brand/loading_review.py --res 1280x800 --locale ko --times 3.2

Output: build/feedback-2026-10-19/D4/loading/<res>_<locale>/t*.png, frames.json, plus
sequence sheets (sequence_<res>_<locale>.png), a playback GIF and an all-aspects board.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from godot_env import GODOT, ROOT, xvfb  # noqa: E402

OUT = ROOT / "build/feedback-2026-10-19/D4/loading"
RESES = ["1280x800", "1000x625", "1280x720", "2400x1080", "1024x768"]


def run(res: str, locale: str, art: str, times: str, env: dict) -> Path:
    folder = OUT / f"{res}_{locale}"
    folder.mkdir(parents=True, exist_ok=True)
    for old in folder.glob("t*.png"):
        old.unlink()
    cmd = [str(GODOT), "--path", str(ROOT), "--resolution", res, "--fixed-fps", "60",
           "res://tests/brand/loading_preview.tscn", "--", "--out", str(folder), "--locale", locale]
    if art:
        cmd += ["--art", str(Path(art).resolve())]
    if times:
        cmd += ["--times", times]
    r = subprocess.run(cmd, env=env, text=True, capture_output=True, timeout=120)
    log = r.stdout + r.stderr
    (folder / "godot.log").write_text(log)
    bad = [line for line in log.splitlines() if "SCRIPT ERROR" in line or "ERROR:" in line]
    if r.returncode or bad:
        print(log[-3000:])
        raise SystemExit(f"{res} {locale}: failed")
    return folder


def sheet(folder: Path, res: str, locale: str) -> Path:
    meta = json.loads((folder / "frames.json").read_text())
    frames = meta["frames"]
    tiles = []
    for fr in frames:
        im = Image.open(folder / fr["file"]).convert("RGB")
        w = 420
        tiles.append((im.resize((w, round(im.height * w / im.width)), Image.LANCZOS), fr))
    tw, th = tiles[0][0].size
    cols = 4
    rows = (len(tiles) + cols - 1) // cols
    board = Image.new("RGB", (cols * (tw + 8) + 8, rows * (th + 30) + 40), "#0b141c")
    d = ImageDraw.Draw(board)
    d.text((10, 10), f"D4 loading study  {res}  {locale}", fill=(240, 220, 160))
    for i, (im, fr) in enumerate(tiles):
        x = 8 + (i % cols) * (tw + 8)
        y = 40 + (i // cols) * (th + 30)
        board.paste(im, (x, y))
        d.text((x + 4, y + th + 6), "t=%.2fs  %s  logo %.2f  bar %.0f%%" % (fr["t"], fr["phase"], fr["logo_alpha"], fr["shown"] * 100),
               fill=(200, 210, 220))
    path = OUT / f"sequence_{res}_{locale}.png"
    board.save(path)
    gif = [im for im, _ in tiles]
    gif[0].save(OUT / f"playback_{res}_{locale}.gif", save_all=True, append_images=gif[1:], duration=350, loop=0)
    return path


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--art", default="")
    ap.add_argument("--res", action="append")
    ap.add_argument("--locale", action="append")
    ap.add_argument("--times", default="")
    args = ap.parse_args()
    reses = args.res or RESES
    locales = args.locale or ["ko", "en"]
    OUT.mkdir(parents=True, exist_ok=True)
    big = max(reses, key=lambda r: int(r.split("x")[0]) * int(r.split("x")[1]))
    with xvfb(131, big) as env:
        for res in reses:
            for loc in locales:
                folder = run(res, loc, args.art, args.times, env)
                print(sheet(folder, res, loc), flush=True)


if __name__ == "__main__":
    main()
