#!/usr/bin/env python3
"""Boss scale review: run tests/3d/boss_scale_preview.tscn in real GL (Xvfb) at both
window sizes and assemble per-boss GIFs and contact sheets (spawn, walk, siege, death)
cropped around the boss.

    python3 tests/3d/boss_scale_review.py                      # 1280x800 + 1000x625
    python3 tests/3d/boss_scale_review.py --res 1280x800 --ids flame_dragon,titan_bloom
    python3 tests/3d/boss_scale_review.py --assemble-only

Outputs under build/walk-grounding/boss/<res>/: <id>_{spawn,walk,siege,die}_NN.png,
<id>.gif (whole frame, half size), <id>_siege.gif (2x crop at the altar),
<id>_contact.jpg, boss-report.json, render.log. Any ERROR / failed check fails the run.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from godot_env import ROOT, GODOT, ensure_xvfb, xvfb  # noqa: E402

FONT = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 15)
OUT_ROOT = ROOT / "build/walk-grounding/boss"
BOSSES = ["abyss_leviathan", "flame_dragon", "titan_bloom", "crystal_golem_king", "glacier_dragon"]


def labelled(frame: Image.Image, text: str) -> Image.Image:
    out = frame.copy()
    draw = ImageDraw.Draw(out)
    draw.rectangle((0, 0, out.width, 20), fill=(8, 18, 28))
    draw.text((5, 2), text, font=FONT, fill=(235, 243, 247))
    return out


def save_gif(frames, dest: Path, duration: int = 50) -> None:
    if frames:
        frames[0].save(dest, save_all=True, append_images=frames[1:], duration=duration, loop=0)


def contact(frames, dest: Path, columns: int) -> None:
    if not frames:
        return
    w, h = frames[0].size
    rows = (len(frames) + columns - 1) // columns
    sheet = Image.new("RGB", (w * columns, h * rows), (8, 18, 28))
    for n, frame in enumerate(frames):
        sheet.paste(frame, ((n % columns) * w, (n // columns) * h))
    sheet.save(dest, quality=90)


def run(res: str, display: int, ids: list[str] | None) -> bool:
    out = OUT_ROOT / res
    out.mkdir(parents=True, exist_ok=True)
    for stale in out.glob("*_[0-9][0-9].png"):
        stale.unlink()
    extra = ["--out", str(out)]
    if ids:
        extra += ["--ids", ",".join(ids)]
    command = [str(GODOT), "--path", str(ROOT), "--resolution", res, "res://tests/3d/boss_scale_preview.tscn", "--", *extra]
    with xvfb(display, res) as env:
        result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=3600)
    text = result.stdout + "\n" + result.stderr
    (out / "render.log").write_text(text)
    errors = [line for line in text.splitlines() if "ERROR:" in line or "SCRIPT ERROR" in line or line.startswith("!! ")]
    ok = result.returncode == 0 and "판정: 정상" in result.stdout and not errors
    print(f"boss {res}: exit {result.returncode}, errors {len(errors)}, {'ok' if ok else 'FAILED'}")
    for line in errors[:10]:
        print("   ", line)
    return ok


def assemble(res: str) -> None:
    out = OUT_ROOT / res
    report_path = out / "boss-report.json"
    if not report_path.exists():
        return
    report = json.loads(report_path.read_text())
    window = report["window"]
    scale = report.get("scale", 1.0)
    for boss, row in report["bosses"].items():
        frames = []
        for stage in ("spawn", "walk", "siege", "die"):
            files = sorted(out.glob(f"{boss}_{stage}_[0-9][0-9].png"))
            for path in files:
                image = Image.open(path).convert("RGB")
                frames.append(labelled(image.resize((image.width // 2, image.height // 2), Image.LANCZOS), f"{boss} x{scale:.1f}  {stage} {path.stem[-2:]}"))
        save_gif(frames, out / f"{boss}.gif", 66)
        contact(frames[::3], out / f"{boss}_contact.jpg", 6)
        foot = row.get("screen", {}).get("siege_foot")
        siege_files = sorted(out.glob(f"{boss}_siege_[0-9][0-9].png")) + sorted(out.glob(f"{boss}_die_[0-9][0-9].png"))
        if foot and siege_files:
            cx, cy = foot
            half_w, up, down = 190 * window[0] / 1280, 260 * window[1] / 800, 70 * window[1] / 800
            box = (int(cx - half_w), int(cy - up), int(cx + half_w), int(cy + down))
            crops = []
            for path in siege_files:
                crop = Image.open(path).convert("RGB").crop(box)
                crops.append(labelled(crop.resize((crop.width * 2, crop.height * 2), Image.LANCZOS), f"{boss}  altar  {path.stem.split('_')[-2]} {path.stem[-2:]}"))
            save_gif(crops, out / f"{boss}_siege.gif", 50)
            contact(crops[::4], out / f"{boss}_siege_contact.jpg", 5)
        print(f"  {boss}: frames {row.get('frames')}  siege distance {row.get('siege_distance', 0):.0f} logical  scale {row.get('scale')}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--res", action="append")
    parser.add_argument("--ids", help="comma separated boss ids")
    parser.add_argument("--display-base", type=int, default=210)
    parser.add_argument("--assemble-only", action="store_true")
    args = parser.parse_args()
    ensure_xvfb()
    ids = args.ids.split(",") if args.ids else None
    failed = False
    for n, res in enumerate(args.res or ["1280x800", "1000x625"]):
        if not args.assemble_only and not run(res, args.display_base + n, ids):
            failed = True
        assemble(res)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
