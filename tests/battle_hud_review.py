#!/usr/bin/env python3
"""Photograph the battle HUD of the 2026-10-19 feedback (D6) at both review sizes, ko and en.

    python3 tests/battle_hud_review.py                       # every set, 1280x800 + 1000x625
    python3 tests/battle_hud_review.py --only aim,pop --sizes 1280x800 --locales ko

Runs tests/battle_hud_preview.tscn on the login session's GPU display (:1, one capture at a time
under build/casual-overhaul/gpu.lock, --disable-vsync) and falls back to Xvfb. Writes, per size,
build/feedback-2026-10-19/D6/<size>/<locale>_<name>.png (+ .json: text boxes and touch zones),
motion strips (<locale>_motion_<set>.jpg) and a contact sheet of the stills (sheet_<locale>.jpg).
"""
import argparse
import contextlib
import os
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from godot_env import ROOT, GODOT, xvfb

OUT = ROOT / "build/feedback-2026-10-19/D6"


def display(res: str):
    auth = Path(f"/run/user/{os.getuid()}/gdm/Xauthority")
    if os.environ.get("REVIEW_DISPLAY", "auto") != "xvfb" and auth.exists():
        env = dict(os.environ, DISPLAY=":1", XAUTHORITY=str(auth), STELLARDEFENSE_NO_SAVE="1")
        probe = subprocess.run(["xdpyinfo", "-queryExtensions"], env=env, capture_output=True, text=True)
        if probe.returncode == 0 and "NV-GLX" in probe.stdout:
            return contextlib.nullcontext(env)
    return xvfb(97, res)


def strip(paths, out, cell_w=320, columns=6):
    shots = [Image.open(p).convert("RGB") for p in paths]
    if not shots:
        return
    cell_h = round(cell_w * shots[0].height / shots[0].width)
    rows = (len(shots) + columns - 1) // columns
    canvas = Image.new("RGB", (columns * cell_w + (columns - 1) * 4, rows * (cell_h + 16) + (rows - 1) * 4), (8, 12, 16))
    draw = ImageDraw.Draw(canvas)
    for n, shot in enumerate(shots):
        x = n % columns * (cell_w + 4)
        y = n // columns * (cell_h + 16 + 4)
        canvas.paste(shot.resize((cell_w, cell_h), Image.LANCZOS), (x, y))
        draw.text((x + 4, y + cell_h + 2), Path(paths[n]).stem, fill=(214, 222, 226))
    canvas.save(out, quality=92)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sizes", default="1280x800,1000x625")
    parser.add_argument("--locales", default="ko,en")
    parser.add_argument("--only", default="")
    parser.add_argument("--timeout", type=int, default=1200)
    args = parser.parse_args()
    code = 0
    for res in args.sizes.split(","):
        out = OUT / res
        out.mkdir(parents=True, exist_ok=True)
        cmd = [str(GODOT), "--disable-vsync", "--path", str(ROOT), "--resolution", "96x60",
               "res://tests/battle_hud_preview.tscn", "--", "--film", res, "--out", str(out),
               "--locales", args.locales, "--timeout", str(args.timeout)]
        if args.only:
            cmd += ["--only", args.only]
        lock = ROOT / "build/casual-overhaul/gpu.lock"
        lock.parent.mkdir(parents=True, exist_ok=True)
        with display(res) as env:
            with open(lock, "w") as handle:
                import fcntl
                fcntl.flock(handle, fcntl.LOCK_EX)
                run = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=args.timeout + 120)
        log = out / "run.log"
        log.write_text(run.stdout + "\n---- stderr ----\n" + run.stderr)
        tail = [line for line in run.stdout.splitlines() if "판정" in line or "건" in line]
        print(res, "exit", run.returncode, *tail[-2:])
        errors = [line for line in run.stderr.splitlines() if line.startswith("!!") or "ERROR" in line or "SCRIPT ERROR" in line]
        for line in errors[:30]:
            print("  ", line)
        if run.returncode != 0:
            code = 1
        for locale in args.locales.split(","):
            stills = sorted(p for p in out.glob(f"{locale}_*.png") if "_motion_" not in p.name)
            strip(stills, out / f"sheet_{locale}.jpg", 320, 4)
            for motion in ["pop", "aim", "cast", "elite", "final"]:
                frames = sorted(out.glob(f"{locale}_motion_{motion}_*.png"))
                if frames:
                    strip(frames, out / f"{locale}_motion_{motion}.jpg", 256, 6)
    return code


if __name__ == "__main__":
    raise SystemExit(main())
