#!/usr/bin/env python3
"""Film the D3 (feedback 2026-10-19) battlefield visuals in real GL and assemble review media.

    python3 tests/3d/d3_review.py                                  # all scenes, 4 fields, both sizes
    python3 tests/3d/d3_review.py --scene ring --field calm_lake --res 1280x800
    python3 tests/3d/d3_review.py --gpu xvfb                       # software GL instead of :1
    python3 tests/3d/d3_review.py --scene game --field calm_lake   # the real screen and simulator
    python3 tests/3d/d3_review.py --scene hell --res 1280x800      # Hellbound's endless waves

Runs tests/3d/d3_visual_preview.tscn (see its header for the scenes) on the login session's GPU
display (:1, behind a 96x60 window, the picture drawn off-screen at the window size) or Xvfb,
then builds <prefix>.gif, <prefix>_zoom.gif and <prefix>_contact.jpg for every filmed sequence
(tools/3d/vfx_review.py assemble). Serialise GPU runs with `flock build/casual-overhaul/gpu.lock`.
Outputs: build/feedback-2026-10-19/D3/<res>/ (PNG frames, render.log, d3-report.json).
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools" / "3d"))
from godot_env import ROOT, GODOT  # noqa: E402
from vfx_review import assemble, gpu_display  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--res", action="append", help="WxH; repeatable (default 1280x800 and 1000x625)")
    parser.add_argument("--scene", default="all")
    parser.add_argument("--field", default="all")
    parser.add_argument("--gpu", default="auto")
    parser.add_argument("--out-root", default=str(ROOT / "build/feedback-2026-10-19/D3"))
    parser.add_argument("--display-base", type=int, default=460)
    parser.add_argument("--old-ring", action="store_true", help="ring: also film the pre-2026-10-19 selection ring (ringold_*)")
    args = parser.parse_args()
    failed = False
    for index, res in enumerate(args.res or ["1280x800", "1000x625"]):
        out = Path(args.out_root) / res
        out.mkdir(parents=True, exist_ok=True)
        display = gpu_display(args.gpu, args.display_base + index, res)
        command = [str(GODOT), "--path", str(ROOT), "--resolution", res, "res://tests/3d/d3_visual_preview.tscn", "--",
                   "--out", str(out), "--scene", args.scene, "--field", args.field]
        if display["gpu"]:
            command[1:1] = ["--disable-vsync"]
            command += ["--film", res]
        if args.old_ring:
            command.append("--old-ring")
        with display["context"] as env:
            env = dict(env)
            env["STELLARDEFENSE_NO_SAVE"] = "1"
            result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=3600)
        log = result.stdout + "\n" + result.stderr
        (out / f"render-{args.scene}-{args.field}.log").write_text(log)
        verdict = "판정: 정상" in result.stdout
        errors = [line for line in log.splitlines() if ("ERROR:" in line or "SCRIPT ERROR" in line)
                  and "still in use at exit" not in line]
        print(res, "exit", result.returncode, "verdict", verdict, "errors", len(errors))
        for line in errors[:12]:
            print("   ", line)
        for line in log.splitlines():
            if line.startswith("!! "):
                print("   ", line)
        report_path = out / "d3-report.json"
        if report_path.exists():
            report = json.loads(report_path.read_text())
            for sequence in report.get("sequences", []):
                duration = int(1000 * sequence["tick"] * sequence["ticks_per_frame"]) if sequence["ticks_per_frame"] > 1 else 66
                assemble(out, sequence["prefix"], duration, sequence.get("focus"))
        if result.returncode or not verdict or errors:
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
