#!/usr/bin/env python3
"""Capture native Godot Idle/Attack/Shot playback at the two design viewports."""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from godot_env import GODOT, xvfb  # noqa: E402

for resolution in sys.argv[1:] or ["1280x800", "1000x625"]:
    with xvfb(94, resolution) as env:
        subprocess.run([str(GODOT), "--path", str(ROOT), "--resolution", resolution,
                        "res://tests/element_aoe_preview.tscn", "--",
                        str(ROOT / "build/element-aoe-sprites" / resolution)], env=env, check=True, timeout=120)
