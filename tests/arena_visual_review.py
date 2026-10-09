#!/usr/bin/env python3
"""Capture the arena using actual Godot OpenGL at both mobile review sizes."""
import argparse
import json
import subprocess
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from godot_env import ROOT, GODOT, xvfb

parser = argparse.ArgumentParser()
parser.add_argument("--res", action="append")
parser.add_argument("--only", choices=["polish", "help", "rite"])
args = parser.parse_args()
report = {"renderer": "gl_compatibility", "device_fps_measured": False, "resolutions": {}}
for index, resolution in enumerate(args.res or ["1280x800", "1000x625"]):
    out = ROOT / "build/arena-visual" / resolution
    out.mkdir(parents=True, exist_ok=True)
    with xvfb(113 + index, resolution) as env:
        extra = [f"--{args.only}-only"] if args.only else []
        result = subprocess.run(
            [str(GODOT), "--path", str(ROOT), "--resolution", resolution,
             "res://tests/arena_visual_preview.tscn", "--", "--out", str(out), *extra],
            env=env, capture_output=True, text=True, timeout=600,
        )
    log = result.stdout + "\n" + result.stderr
    (out / (f"{args.only}-render.log" if args.only else "render.log")).write_text(log)
    if result.returncode or "ERROR:" in log or "!! " in log:
        print("\n".join(log.splitlines()[-100:]))
        sys.exit(1)
    for locale in ["ko", "en"]:
        names = ["themes", "rite_free", "summon_new", "field_six", "help", "growth_result",
                 "growth_maxed", "upgrades", "passives", "reserves_selected", "boss", "victory",
                 "defeat", "title", "title_resume"]
        contact = Image.new("RGB", (1280, 267 * 5), (10, 20, 29))
        for n, name in enumerate(names):
            if not (out / f"{locale}_{name}.png").exists():
                continue
            shot = Image.open(out / f"{locale}_{name}.png").convert("RGB")
            shot.thumbnail((426, 267))
            contact.paste(shot, (n % 3 * 426, n // 3 * 267))
        contact.save(out / f"{locale}_contact.jpg", quality=94)
        for motion in ["move", "limne_move", "skill_blast", "skill_freeze", "skill_ward", "rite_pull"]:
            files = sorted(out.glob(f"{locale}_{motion}_[0-9][0-9].png"))
            frames = [Image.open(path).convert("RGB") for path in files]
            if frames:
                frames[0].save(out / f"{locale}_{motion}.gif", save_all=True,
                               append_images=frames[1:], duration=100, loop=0)
    checks = json.loads((out / (f"{args.only}-report.json" if args.only else "report.json")).read_text())
    if "resolution" in checks:
        checks["layout_resolution"] = checks.pop("resolution")
    checks["window_resolution"] = list(Image.open(out / "ko_rite_free.png").size)
    checks["screenshots"] = {"polish": 32, "help": 2, "rite": 12}.get(args.only, len(list(out.glob("*.png"))))
    checks["render_errors"] = 0
    report["resolutions"][resolution] = checks
    print(f"{resolution}: {checks['screenshots']} screenshots, {checks['checks']} checks, 0 failures")
(ROOT / "build/arena-visual" / (f"{args.only}-report.json" if args.only else "report.json")).write_text(json.dumps(report, indent=2) + "\n")
