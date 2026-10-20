#!/usr/bin/env python3
"""Jewel box in the real game flow (D1): runs tests/box_flow_capture.tscn at 1280x800 and 1000x625,
ko and en, and turns each segment into an MP4, a GIF and a contact sheet, plus one MP4 of the whole flow.

    python3 tests/box_flow_review.py [--res 1280x800,1000x625] [--lang ko,en] [--xvfb]

Output: build/feedback-2026-10-19/D1/flow/<res>/<lang>/<segment>/NNNN.png, <segment>.mp4|.gif|_sheet.jpg,
flow.mp4, flow.json (per frame: segment, game time, modal, box deal/pick clocks, ready, grade).

Renders on the login session's GPU display (:1, NVIDIA) through an off-screen viewport, the window kept
tiny; GPU captures share build/casual-overhaul/gpu.lock with the other workers. --xvfb uses software GL.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from godot_env import GODOT, xvfb  # noqa: E402

OUT = ROOT / "build/feedback-2026-10-19/D1/flow"
LOCK = ROOT / "build/casual-overhaul/gpu.lock"
# Segments kept every frame (the boxes) play at 30 fps; the rest were kept every third frame.
SPARSE = {"title", "to_stage", "battle", "prep"}


def run(res: str, lang: str, use_xvfb: bool) -> dict:
    dest = OUT / res / lang
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    args = [str(GODOT), "--path", str(ROOT), "--fixed-fps", "30", "--disable-vsync", "res://tests/box_flow_capture.tscn",
            "--", "--out", str(dest), "--lang", lang]
    t0 = time.time()
    if use_xvfb:
        with xvfb(392, res) as env:
            p = subprocess.run([*args[:1], "--resolution", res, *args[1:]], env=env, capture_output=True, text=True, timeout=3600)
    else:
        env = dict(os.environ, DISPLAY=":1", XAUTHORITY="/run/user/1000/gdm/Xauthority", STELLARDEFENSE_NO_SAVE="1")
        p = subprocess.run(["flock", str(LOCK), *args, "--film", res], env=env, capture_output=True, text=True, timeout=3600)
    log = p.stdout + p.stderr
    (dest / "godot.log").write_text(log)
    verdict = [ln for ln in log.splitlines() if "판정" in ln or ln.startswith("!!") or "SCRIPT ERROR" in ln]
    return {"res": res, "lang": lang, "seconds": round(time.time() - t0, 1), "verdict": verdict[:20]}


def movies(dest: Path) -> list[str]:
    from PIL import Image, ImageDraw
    meta = json.loads((dest / "flow.json").read_text())
    rows: dict[str, list] = {}
    for r in meta["frames"]:
        rows.setdefault(r["segment"], []).append(r)
    parts = []
    order = []
    for r in meta["frames"]:
        if r["segment"] not in order:
            order.append(r["segment"])
    for seg in order:
        d = dest / seg
        if not (d / "0000.png").exists():
            continue
        fps = 10 if seg in SPARSE else 30
        mp4 = dest / f"{seg}.mp4"
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(fps), "-i", str(d / "%04d.png"),
                        "-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2,fps=30", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", str(mp4)])
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(fps), "-i", str(d / "%04d.png"),
                        "-vf", "fps=15,scale=640:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=192[p];[b][p]paletteuse=dither=bayer:bayer_scale=4",
                        str(dest / f"{seg}.gif")])
        parts.append(mp4)
        frames = sorted(d.glob("[0-9][0-9][0-9][0-9].png"))
        step = max(1, len(frames) // 24)
        pick = frames[::step][:30]
        tw, th, cols = 400, 250, 6
        sheet = Image.new("RGB", (tw * cols, th * ((len(pick) + cols - 1) // cols)))
        info = {r["frame"]: r for r in rows[seg]}
        for k, f in enumerate(pick):
            im = Image.open(f).convert("RGB").resize((tw, th), Image.LANCZOS)
            r = info.get(int(f.stem), {})
            label = f"{seg} t={r.get('t', 0):.2f}"
            if "deal" in r:
                label += f" deal={r['deal']:.2f}{' R' if r.get('ready') else ''}"
            dr = ImageDraw.Draw(im)
            dr.rectangle((0, 0, 230, 16), fill=(0, 0, 0))
            dr.text((3, 2), label, fill=(255, 230, 0))
            sheet.paste(im, ((k % cols) * tw, (k // cols) * th))
        sheet.save(dest / f"{seg}_sheet.jpg", quality=86)
    lst = dest / "parts.txt"
    lst.write_text("".join(f"file '{p}'\n" for p in parts))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", str(lst), "-c", "copy", str(dest / "flow.mp4")])
    return order


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--res", default="1280x800,1000x625")
    ap.add_argument("--lang", default="ko,en")
    ap.add_argument("--xvfb", action="store_true")
    a = ap.parse_args()
    summary = []
    for res in a.res.split(","):
        for lang in a.lang.split(","):
            info = run(res, lang, a.xvfb)
            dest = OUT / res / lang
            if (dest / "flow.json").exists():
                info["segments"] = movies(dest)
            summary.append(info)
            print(json.dumps(info, ensure_ascii=False), flush=True)
    (OUT / "review.json").write_text(json.dumps(summary, indent=1, ensure_ascii=False))
    bad = [s for s in summary if not any("정상" in v for v in s["verdict"])]
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
