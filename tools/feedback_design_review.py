#!/usr/bin/env python3
"""Render the requested theme, hand, reward and area-effect changes in Godot."""
import subprocess
from godot_env import ROOT, GODOT, xvfb

out = ROOT / "build/feedback-design"
out.mkdir(parents=True, exist_ok=True)
with xvfb(98, "1280x800") as env:
    for resolution in ["1280x800", "1000x625"]:
        folder = out / resolution
        folder.mkdir(parents=True, exist_ok=True)
        result = subprocess.run(
            [str(GODOT), "--path", str(ROOT), "--resolution", resolution,
             "res://tests/feedback_design_preview.tscn", "--", "--out", str(folder)],
            env=env, text=True, capture_output=True, timeout=240,
        )
        log = result.stdout + result.stderr
        (out / f"{resolution}.log").write_text(log)
        print(resolution, log[-4000:], flush=True)
        if result.returncode or "SCRIPT ERROR:" in log or "판정: 실패" in log:
            raise SystemExit(result.returncode or 1)
