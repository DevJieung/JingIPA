#!/usr/bin/env python3
"""Capture hero facing after stopping/blocking with actual Godot OpenGL (both review sizes).

    python3 tests/arena_facing_review.py [--out-root build/facing]

Writes ko_facing_NNN.png, ko_facing.gif, ko_facing_contact.jpg, facing-report.json and
render.log per resolution. Fails when Godot reports an error or a check fails.
"""
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
parser.add_argument("--out-root", type=Path, default=ROOT / "build/facing")
args = parser.parse_args()
report = {"renderer": "gl_compatibility", "device_fps_measured": False, "resolutions": {}}
for index, resolution in enumerate(args.res or ["1280x800", "1000x625"]):
    out = args.out_root / resolution
    out.mkdir(parents=True, exist_ok=True)
    log_path = out / "render.log"
    with xvfb(131 + index, resolution) as env, log_path.open("w") as stream:
        result = subprocess.run(
            [str(GODOT), "--path", str(ROOT), "--resolution", resolution,
             "res://tests/arena_facing_preview.tscn", "--", "--out", str(out)],
            env=env, stdout=stream, stderr=subprocess.STDOUT, text=True, timeout=900,
        )
    log = log_path.read_text()
    if result.returncode or "ERROR:" in log or "!! " in log:
        print("\n".join(log.splitlines()[-60:]))
        sys.exit(1)
    frames = sorted(out.glob("ko_facing_[0-9][0-9][0-9].png"))
    images = []
    for path in frames:
        img = Image.open(path).convert("RGB")
        img.thumbnail((640, 400))
        images.append(img.quantize(colors=128, method=Image.Quantize.FASTOCTREE))
    if images:
        images[0].save(out / "ko_facing.gif", save_all=True, append_images=images[1:], duration=83, loop=0, optimize=False)
    picks = frames[:: max(1, len(frames) // 12)][:12]
    contact = Image.new("RGB", (1280, 267 * max(1, (len(picks) + 2) // 3)), (10, 20, 29))
    for n, path in enumerate(picks):
        shot = Image.open(path).convert("RGB")
        shot.thumbnail((426, 267))
        contact.paste(shot, (n % 3 * 426, n // 3 * 267))
    contact.save(out / "ko_facing_contact.jpg", quality=94)
    checks = json.loads((out / "facing-report.json").read_text())
    checks["render_errors"] = 0
    report["resolutions"][resolution] = checks
    print(f"{resolution}: {len(frames)} frames, {checks['checks']} checks, {checks['failures']} failures, "
          f"max off east {checks['max_off_east_deg']:.1f} deg")
(args.out_root / "facing-report.json").write_text(json.dumps(report, indent=2) + "\n")
