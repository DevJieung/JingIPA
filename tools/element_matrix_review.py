#!/usr/bin/env python3
"""Render the bilingual element matrix through the real menu in both screen sizes."""
import subprocess
from godot_env import ROOT, GODOT, xvfb

out = ROOT / "build/element-matrix"
with xvfb(113, "1280x800") as env:
    for resolution in ["1280x800", "1000x625"]:
        folder = out / resolution
        folder.mkdir(parents=True, exist_ok=True)
        result = subprocess.run(
            [str(GODOT), "--path", str(ROOT), "--resolution", resolution,
             "res://tests/element_matrix_preview.tscn", "--", "--out", str(folder)],
            env=env, capture_output=True, text=True, timeout=120)
        log = result.stdout + result.stderr
        (out / f"{resolution}.log").write_text(log)
        print(resolution, log[-5000:], flush=True)
        if result.returncode or "ERROR:" in log or "판정: 정상" not in log:
            raise SystemExit(result.returncode or 1)
