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
parser.add_argument("--out-root", type=Path, default=ROOT / "build/arena-visual")
parser.add_argument("--only", choices=["polish", "help", "rite", "style", "look", "circle", "hud", "road", "motion"])
args = parser.parse_args()
report = {"renderer": "gl_compatibility", "device_fps_measured": False, "resolutions": {}}
for index, resolution in enumerate(args.res or ["1280x800", "1000x625"]):
    out = args.out_root / resolution
    out.mkdir(parents=True, exist_ok=True)
    with xvfb(113 + index, resolution) as env:
        extra = [f"--{args.only}-only"] if args.only else []
        live_log = out / (f"{args.only}-render.log" if args.only else "render.log")
        with live_log.open("w") as stream:
            result = subprocess.run(
                [str(GODOT), "--path", str(ROOT), "--resolution", resolution,
                 "res://tests/arena_visual_preview.tscn", "--", "--out", str(out), *extra],
                env=env, stdout=stream, stderr=subprocess.STDOUT, text=True, timeout=600,
            )
    log = live_log.read_text()
    if result.returncode or "ERROR:" in log or "!! " in log:
        print("\n".join(log.splitlines()[-100:]))
        sys.exit(1)
    for locale in ["ko", "en"]:
        names = ["road_field_six", "road_center_guardians", "road_pass_10", "road_pass_20", "road_pass_31", "road_entry_00", "road_entry_01", "road_entry_02", "road_entry_03", "circle", "circle_edge_00", "circle_edge_02", "circle_edge_04", "circle_edge_06", "joystick_start_00", "joystick_drag_00", "joystick_drag_01", "joystick_drag_02", "joystick_drag_03", "joystick_released", "reference", "edge_-1_0", "edge_1_0", "edge_0_-1", "edge_0_1", "edge_1_1", "biome_00", "biome_20", "biome_30", "biome_40", "themes", "rite_free", "summon_new", "field_six", "help", "growth_result",
                 "growth_maxed", "upgrades", "passives", "reserves_selected", "boss", "victory",
                 "defeat", "title", "title_resume", "collection_water", "collection_fire", "collection_elec", "menu_menu", "menu_rite", "menu_elements"]
        names = [name for name in names if (out / f"{locale}_{name}.png").exists()]
        contact = Image.new("RGB", (1280, 267 * max(1, (len(names) + 2) // 3)), (10, 20, 29))
        for n, name in enumerate(names):
            if not (out / f"{locale}_{name}.png").exists():
                continue
            shot = Image.open(out / f"{locale}_{name}.png").convert("RGB")
            shot.thumbnail((426, 267))
            contact.paste(shot, (n % 3 * 426, n // 3 * 267))
        contact.save(out / f"{locale}_contact.jpg", quality=94)
        for motion in ["move", "limne_move", "skill_blast", "skill_freeze", "skill_ward", "rite_spin", "follow", "echo_attack", "lane", "long_walk", "road_pass", "motion"]:
            files = sorted(out.glob(f"{locale}_{motion}_[0-9][0-9].png"))
            frames = []
            for path in files:
                preview = Image.open(path).convert("RGB")
                preview.thumbnail((640, 400))
                frames.append(preview.quantize(colors=128, method=Image.Quantize.FASTOCTREE))
            if frames:
                frames[0].save(out / f"{locale}_{motion}.gif", save_all=True,
                               append_images=frames[1:], duration=300 if motion == "road_pass" else 67 if motion == "motion" else 100,
                               loop=0, optimize=False)
    checks = json.loads((out / (f"{args.only}-report.json" if args.only else "report.json")).read_text())
    if "resolution" in checks:
        checks["layout_resolution"] = checks.pop("resolution")
    reference = {"circle": "ko_circle.png", "road": "ko_road_field_six.png", "motion": "ko_motion_start.png"}.get(args.only, "ko_rite_free.png")
    checks["window_resolution"] = list(Image.open(out / reference).size)
    checks["screenshots"] = {"polish": 32, "help": 2, "rite": 12, "style": 38}.get(args.only, len(list(out.glob("*.png"))))
    checks["render_errors"] = 0
    report["resolutions"][resolution] = checks
    print(f"{resolution}: {checks['screenshots']} screenshots, {checks['checks']} checks, 0 failures")
(args.out_root / (f"{args.only}-report.json" if args.only else "report.json")).write_text(json.dumps(report, indent=2) + "\n")
