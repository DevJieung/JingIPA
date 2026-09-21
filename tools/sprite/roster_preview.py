#!/usr/bin/env python3
"""Capture native Godot Idle/Attack/Shot playback at the two design viewports."""
from pathlib import Path
import argparse
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from godot_env import GODOT, xvfb  # noqa: E402

p = argparse.ArgumentParser()
p.add_argument("--ids", default="chispa,solana,jokull,rhiannon")
p.add_argument("--group", default="sample")
p.add_argument("--res", default="1280x800,1000x625")
a = p.parse_args()
for resolution in a.res.split(","):
    with xvfb(94, resolution) as env:
        subprocess.run([str(GODOT), "--path", str(ROOT), "--resolution", resolution,
                        "res://tests/all_hero_sprites_preview.tscn", "--",
                        str(ROOT / "build/all-hero-sprites" / a.group / resolution), a.ids], env=env, check=True, timeout=120)
