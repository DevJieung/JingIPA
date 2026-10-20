#!/usr/bin/env python3
"""Jewel-box ceremony captures (F10/F11, D1): real Godot GL renders of tests/box_preview.tscn.

    python3 tests/box_review.py                    # everything: both sizes, both languages
    python3 tests/box_review.py --only full_t3,pick_new --res 1280x800 --lang ko
    python3 tests/box_review.py --list

Each scenario writes frames (every 1/30 s), a GIF and an MP4 (motion sets) or one PNG (stills),
plus a contact sheet with the clock and the live particle count on every tile, under
build/feedback-2026-10-19/D1/<res>/<lang>/. A summary (settle times, particle peaks) goes to
build/feedback-2026-10-19/D1/review.json.

The modal floats over the paused field, so the background is a real arena capture of the same
language (build/casual-overhaul/after/wp-e/hud/<res>/<lang>_field_six.png) under the shade.
Rendering uses Xvfb (software GL): the preview is 2D only, a frame costs ~50 ms.
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from godot_env import GODOT, xvfb  # noqa: E402

OUT = ROOT / "build/feedback-2026-10-19/D1"
BG = ROOT / "build/casual-overhaul/after/wp-e/hud"

# name: (motion?, preview args)
SCENARIOS: dict[str, tuple[bool, list[str]]] = {
    "full_t1": (True, ["--tier=1", "--stars=1,1,2,1,1"]),
    "full_t2": (True, ["--tier=2", "--stars=2,1,1,3,2"]),
    "full_t3": (True, ["--tier=3", "--stars=1,2,3,2,4"]),
    "full_t4": (True, ["--tier=4", "--stars=2,4,3,2,1"]),
    "full_t5": (True, ["--tier=5", "--stars=3,5,2,4,1"]),
    "fast_t2": (True, ["--tier=2", "--stars=2,1,3,2,1", "--fast"]),
    "reroll_up": (True, ["--tier=2", "--stars=2,1,1,2,1", "--settled", "--reroll-at=0.3", "--reroll-tier=4",
                         "--reroll-stars=2,4,3,1,2", "--dur=6.0"]),
    "reroll_same": (True, ["--tier=3", "--stars=3,1,2,2,1", "--settled", "--reroll-at=0.3", "--reroll-tier=3",
                           "--reroll-stars=1,3,2,1,2", "--dur=4.6"]),
    "skip": (True, ["--tier=3", "--stars=2,5,1,3,2", "--skip-at=0.9", "--dur=2.6"]),
    "pick_new": (True, ["--tier=3", "--stars=1,2,3,2,4", "--settled", "--pick-at=0.3", "--pick=4", "--dur=2.2"]),
    "pick_growth": (True, ["--tier=2", "--stars=2,3,1,2,2", "--settled", "--pick-at=0.3", "--pick=1", "--dur=2.2"]),
    "pick_eye": (True, ["--tier=3", "--stars=3,2,1,3,2", "--settled", "--pick-at=0.3", "--pick=0", "--eye", "--joker", "--dur=2.2"]),
    "still_mix": (False, ["--tier=3", "--stars=1,2,3,4,5", "--settled"]),
    "still_low": (False, ["--tier=1", "--stars=1,1,2,1,1", "--settled"]),
}
SIZES = ["1280x800", "1000x625"]
LANGS = ["ko", "en"]


def run(res: str, lang: str, name: str, display: int) -> dict:
    motion, args = SCENARIOS[name]
    dest = OUT / res / lang / name
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    bg = BG / res / f"{lang}_field_six.png"
    cmd = [str(GODOT), "--path", str(ROOT), "--resolution", res, "res://tests/box_preview.tscn", "--",
           f"--shot={dest}", f"--lang={lang}", f"--bg={bg}", *args]
    if not motion:
        cmd += ["--dur=0.0"]
    t0 = time.time()
    with xvfb(display, res) as env:
        p = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=900)
    log = p.stdout + p.stderr
    (dest / "godot.log").write_text(log)
    # Only errors raised from this work's files count; another worker's half-edited script elsewhere in
    # the tree (seen: game/arena_sim.gd) is reported separately and retried by hand.
    lines = log.splitlines()
    errors, foreign = [], []
    for k, ln in enumerate(lines):
        if "SCRIPT ERROR" in ln or ("ERROR" in ln and "V-Sync" not in ln and "MSAA" not in ln):
            where = " ".join(lines[k:k + 2])
            (errors if ("box_ceremony" in where or "box_preview" in where or "box_layout" in where) else foreign).append(where)
    meta = json.loads((dest / "meta.json").read_text()) if (dest / "meta.json").exists() else {}
    frames = sorted(dest.glob("[0-9][0-9][0-9][0-9].png"))
    info = {"res": res, "lang": lang, "name": name, "frames": len(frames), "seconds": round(time.time() - t0, 1),
            "settle": meta.get("settle"), "max_particles": meta.get("max_particles"),
            "draw_ms_mean": round(meta.get("draw_us_mean", 0) / 1000.0, 2), "draw_ms_max": round(meta.get("draw_us_max", 0) / 1000.0, 2),
            "errors": errors[:8], "foreign_errors": len(foreign)}
    if frames:
        if motion:
            make_movie(dest, frames, name)
            make_sheet(dest, frames, meta, name)
        else:
            shutil.copy(frames[-1], OUT / res / lang / f"{name}.png")
    return info


def make_movie(dest: Path, frames: list[Path], name: str) -> None:
    mp4 = dest.parent / f"{name}.mp4"
    gif = dest.parent / f"{name}.gif"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", "30", "-i", str(dest / "%04d.png"),
                    "-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", str(mp4)],
                   check=False)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", "30", "-i", str(dest / "%04d.png"),
                    "-vf", "fps=20,scale=640:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=192[p];[b][p]paletteuse=dither=bayer:bayer_scale=4",
                    str(gif)], check=False)


def make_sheet(dest: Path, frames: list[Path], meta: dict, name: str, cols: int = 6, step: int = 3) -> None:
    from PIL import Image, ImageDraw
    rows_meta = {r["frame"]: r for r in meta.get("frames", [])}
    pick = frames[::step]
    tw, th = 400, 250
    rows = (len(pick) + cols - 1) // cols
    sheet = Image.new("RGB", (tw * cols, th * rows), (0, 0, 0))
    for k, f in enumerate(pick):
        im = Image.open(f).convert("RGB").resize((tw, th), Image.LANCZOS)
        idx = int(f.stem)
        r = rows_meta.get(idx, {})
        d = ImageDraw.Draw(im)
        d.rectangle((0, 0, 150, 16), fill=(0, 0, 0))
        d.text((4, 2), f"t={r.get('t', 0):.2f} p={r.get('particles', 0)}{' R' if r.get('ready') else ''}", fill=(255, 230, 0))
        sheet.paste(im, ((k % cols) * tw, (k // cols) * th))
    sheet.save(dest.parent / f"{name}_sheet.jpg", quality=86)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", default="")
    ap.add_argument("--res", default="")
    ap.add_argument("--lang", default="")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--display", type=int, default=380)
    args = ap.parse_args()
    if args.list:
        print("\n".join(SCENARIOS))
        return 0
    names = [n for n in (args.only.split(",") if args.only else SCENARIOS) if n]
    sizes = args.res.split(",") if args.res else SIZES
    langs = args.lang.split(",") if args.lang else LANGS
    summary = []
    for res in sizes:
        for lang in langs:
            for name in names:
                info = run(res, lang, name, args.display)
                summary.append(info)
                flag = "!!" if info["errors"] else "ok"
                print(f"{flag} {res} {lang} {name}: {info['frames']} frames, settle {info['settle']}, "
                      f"peak particles {info['max_particles']}, {info['seconds']}s", flush=True)
                for e in info["errors"]:
                    print("   ", e)
    path = OUT / "review.json"
    old = json.loads(path.read_text()) if path.exists() else []
    keep = [o for o in old if not any(o["res"] == s["res"] and o["lang"] == s["lang"] and o["name"] == s["name"] for s in summary)]
    path.write_text(json.dumps(keep + summary, indent=1, ensure_ascii=False))
    bad = [s for s in summary if s["errors"] or not s["frames"]]
    print(f"\n{len(summary)} runs, {len(bad)} with errors -> {OUT}")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
