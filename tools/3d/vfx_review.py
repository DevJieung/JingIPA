#!/usr/bin/env python3
"""Capture the battle VFX layer in real GL at both mobile sizes and assemble review media.

    python3 tools/3d/vfx_review.py                       # 1280x800 and 1000x625, both squads
    python3 tools/3d/vfx_review.py --res 1280x800 --squad a --frames 24
    python3 tools/3d/vfx_review.py --display-base 220    # first Xvfb display number to try

Outputs under --out-root (default build/motion-overhaul/vfx/<res>/):
  <prefix>_NN.png      consecutive frames from tests/3d/vfx_visual_preview.tscn
  <prefix>.gif         the sequence as an animation (real battlefield framing)
  <prefix>_zoom.gif    2x crop of the battlefield centre, where the fighting happens
  <prefix>_contact.jpg contact sheet of zoomed frames
  <prefix>.mp4         when ffmpeg is available
  render.log           Godot output; any ERROR / SCRIPT ERROR fails the run
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from godot_env import ROOT, GODOT, ensure_xvfb, xvfb  # noqa: E402

BATTLEFIELD = (0, 70, 992, 800)   # ArenaScreen.BATTLEFIELD at the 1280x800 design size


def zoom_box(size: tuple[int, int]) -> tuple[int, int, int, int]:
    """A battlefield-centre crop (half the field) scaled to the actual window."""
    sx = size[0] / 1280.0
    sy = size[1] / 800.0
    cx = (BATTLEFIELD[0] + BATTLEFIELD[2]) * 0.5 * sx
    cy = (BATTLEFIELD[1] + BATTLEFIELD[3]) * 0.5 * sy
    w = 560 * sx
    h = 360 * sy
    return (int(cx - w / 2), int(cy - h / 2), int(cx + w / 2), int(cy + h / 2))


def assemble(out: Path, prefix: str, duration_ms: int) -> None:
    files = sorted(out.glob(f"{prefix}_[0-9][0-9].png"))
    if not files:
        return
    frames = [Image.open(path).convert("RGB") for path in files]
    frames[0].save(out / f"{prefix}.gif", save_all=True, append_images=frames[1:], duration=duration_ms, loop=0)
    box = zoom_box(frames[0].size)
    zoomed = [im.crop(box).resize(((box[2] - box[0]) * 2, (box[3] - box[1]) * 2), Image.LANCZOS) for im in frames]
    zoomed[0].save(out / f"{prefix}_zoom.gif", save_all=True, append_images=zoomed[1:], duration=duration_ms, loop=0)
    columns = 4
    rows = (len(zoomed) + columns - 1) // columns
    tw, th = zoomed[0].size
    tw, th = tw // 2, th // 2
    sheet = Image.new("RGB", (tw * columns, th * rows), (10, 20, 30))
    for n, im in enumerate(zoomed):
        sheet.paste(im.resize((tw, th), Image.LANCZOS), ((n % columns) * tw, (n // columns) * th))
    sheet.save(out / f"{prefix}_contact.jpg", quality=90)
    if shutil.which("ffmpeg"):
        pattern = str(out / f"{prefix}_%02d.png")
        fps = max(1, round(1000 / duration_ms))
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(fps), "-i", pattern,
                        "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2", "-pix_fmt", "yuv420p", str(out / f"{prefix}.mp4")],
                       check=False)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--res", action="append", help="WxH; repeatable (default 1280x800 and 1000x625)")
    parser.add_argument("--squad", default="all", choices=["a", "b", "all"])
    parser.add_argument("--frames", type=int, default=36)
    parser.add_argument("--theme", type=int, default=0)
    parser.add_argument("--quick", action="store_true")
    parser.add_argument("--out-root", default=str(ROOT / "build/motion-overhaul/vfx"))
    parser.add_argument("--display-base", type=int, default=220)
    args = parser.parse_args()
    ensure_xvfb()
    failed = False
    for index, res in enumerate(args.res or ["1280x800", "1000x625"]):
        out = Path(args.out_root) / res
        out.mkdir(parents=True, exist_ok=True)
        for stale in out.glob("*.png"):
            stale.unlink()
        command = [str(GODOT), "--path", str(ROOT), "--resolution", res, "res://tests/3d/vfx_visual_preview.tscn", "--",
                   "--out", str(out), "--squad", args.squad, "--frames", str(args.frames), "--theme", str(args.theme)]
        if args.quick:
            command.append("--quick")
        with xvfb(args.display_base + index, res) as env:
            result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=3600)
        log = result.stdout + "\n" + result.stderr
        (out / "render.log").write_text(log)
        verdict = "판정: 정상" in result.stdout
        errors = [line for line in log.splitlines() if "ERROR:" in line or "SCRIPT ERROR" in line]
        print(res, "exit", result.returncode, "verdict", verdict, "errors", len(errors))
        for line in errors[:10]:
            print("   ", line)
        report_path = out / "vfx-report.json"
        if report_path.exists():
            report = json.loads(report_path.read_text())
            for sequence in report.get("sequences", []):
                assemble(out, sequence["prefix"], int(1000 * sequence["tick"] * sequence["ticks_per_frame"]) if sequence["ticks_per_frame"] > 1 else 66)
            # Skill sequences are captured per skill; assemble each one.
            for skill in ["blast", "freeze", "ward"]:
                for squad in ["a", "b"]:
                    assemble(out, f"{squad}_skill_{skill}", 66)
            if report.get("events"):
                print("   ", json.dumps(report["events"], ensure_ascii=False))
        if result.returncode or not verdict or errors:
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
