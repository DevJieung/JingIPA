#!/usr/bin/env python3
"""Walk-grounding review: run the grounding probe (real GL, Xvfb) for representative heroes,
Limne and monster body shapes, then assemble side-by-side before/after GIFs, contact sheets
and a numeric summary.

    python3 tests/3d/grounding_review.py --state before --root-y hero=0.07,monster=0.14
    python3 tests/3d/grounding_review.py --state after                  # world defaults
    python3 tests/3d/grounding_review.py --assemble-only                # before | after media
    python3 tests/3d/grounding_review.py --state after --only limne_3.4

Outputs under build/walk-grounding/<state>/<subject>/: side_NN.png, game_NN.png,
grounding.json, render.log; and under build/walk-grounding/: <subject>_side.gif,
<subject>_game.gif (2x crop), <subject>_contact.jpg, summary.json, summary.md.
Any ERROR / SCRIPT ERROR / failed check in a log fails the run.
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
# (label, kind, id, speed in world units/s): spd 0.60 / 1.00 / 1.50 heroes, Limne, monsters at PATH_SPEED.
SUBJECTS = [
    ("triton_2.0", "hero", "triton", 2.04),
    ("echo_3.4", "hero", "echo", 3.4),
    ("jokull_3.4", "hero", "jokull", 3.4),
    ("brasa_2.1", "hero", "brasa", 2.11),
    ("pip_5.1", "hero", "pip", 5.1),
    ("limne_3.4", "hero", "limne", 3.4),
    ("ember_imp", "monster", "ember_imp", 1.64),
    ("blaze_fox", "monster", "blaze_fox", 1.64),
    ("stone_golem", "monster", "stone_golem", 1.64),
]
OUT_ROOT = ROOT / "build/walk-grounding"


def run_probe(kind: str, cid: str, speed: float, out: Path, display: int, root_y: float | None, frames: int) -> bool:
    out.mkdir(parents=True, exist_ok=True)
    for stale in list(out.glob("side_*.png")) + list(out.glob("game_*.png")):
        stale.unlink()
    extra = ["--out", str(out), "--speed", str(speed), "--frames", str(frames)]
    extra += ["--monster", cid] if kind == "monster" else ["--id", cid]
    if root_y is not None:
        extra += ["--root-y", str(root_y)]
    command = [str(GODOT), "--path", str(ROOT), "--resolution", "640x400", "res://tests/3d/grounding_probe.tscn", "--", *extra]
    with xvfb(display, "640x400") as env:
        result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=1800)
    text = result.stdout + "\n" + result.stderr
    (out / "render.log").write_text(text)
    errors = [line for line in text.splitlines() if "ERROR:" in line or "SCRIPT ERROR" in line or line.startswith("!! ")]
    ok = result.returncode == 0 and "판정: 정상" in result.stdout and not errors
    summary = [line for line in result.stdout.splitlines() if line.startswith("GROUNDING")]
    print(f"{cid} {speed}: exit {result.returncode}, errors {len(errors)}, {'ok' if ok else 'FAILED'}")
    for line in summary + errors[:8]:
        print("   ", line)
    return ok


def labelled(frame: Image.Image, text: str) -> Image.Image:
    out = frame.copy()
    draw = ImageDraw.Draw(out)
    draw.rectangle((0, 0, out.width, 20), fill=(8, 18, 28))
    draw.text((5, 2), text, font=FONT, fill=(235, 243, 247))
    return out


def save_gif(frames: list[Image.Image], dest: Path, duration: int = 33) -> None:
    if frames:
        frames[0].save(dest, save_all=True, append_images=frames[1:], duration=duration, loop=0)


def contact(frames: list[Image.Image], dest: Path, columns: int) -> None:
    if not frames:
        return
    w, h = frames[0].size
    rows = (len(frames) + columns - 1) // columns
    sheet = Image.new("RGB", (w * columns, h * rows), (8, 18, 28))
    for n, frame in enumerate(frames):
        sheet.paste(frame, ((n % columns) * w, (n // columns) * h))
    sheet.save(dest, quality=90)


def load_frames(folder: Path, prefix: str) -> list[Image.Image]:
    return [Image.open(p).convert("RGB") for p in sorted(folder.glob(f"{prefix}_[0-9][0-9].png"))]


def game_crop(frame: Image.Image) -> Image.Image:
    # The game camera follows the model; the actor sits near the frame centre at 49 px/u.
    box = (320 - 90, 200 - 115, 320 + 90, 200 + 55)
    crop = frame.crop(box)
    return crop.resize((crop.width * 2, crop.height * 2), Image.LANCZOS)


def assemble(subject: str, states: list[str]) -> dict:
    numbers = {}
    side_lanes, game_lanes = [], []
    for state in states:
        folder = OUT_ROOT / state / subject
        report = folder / "grounding.json"
        if not report.exists():
            continue
        data = json.loads(report.read_text())
        numbers[state] = {k: data[k] for k in ("lowest_foot_mean", "both_off_ratio", "strike_gap_mean", "slide_ratio",
                                                 "slide_along_ratio", "vertical_amplitude", "ground_gap_mean", "root_y",
                                                 "contact_frames") if k in data}
        numbers[state]["cadence"] = data.get("cadence_cycles_per_s")
        side = load_frames(folder, "side")
        game = [game_crop(f) for f in load_frames(folder, "game")]
        text = f"{state}  {subject}  root {data['root_y']:.3f}  gap {data['ground_gap_mean']:.3f}u  off {data['both_off_ratio']*100:.0f}%  slide {data['slide_ratio']*100:.0f}%"
        side_lanes.append([labelled(f, text) for f in side])
        game_lanes.append([labelled(f, text) for f in game])
    for lanes, tag, columns in ((side_lanes, "side", 6), (game_lanes, "game", 8)):
        if not lanes:
            continue
        count = min(len(lane) for lane in lanes)
        combined = []
        for n in range(count):
            width = lanes[0][n].width
            height = sum(lane[n].height for lane in lanes) + 4 * (len(lanes) - 1)
            frame = Image.new("RGB", (width, height), (8, 18, 28))
            y = 0
            for lane in lanes:
                frame.paste(lane[n], (0, y))
                y += lane[n].height + 4
            combined.append(frame)
        save_gif(combined, OUT_ROOT / f"{subject}_{tag}.gif")
        thumbs = [f.resize((f.width // 2, f.height // 2), Image.LANCZOS) for f in combined[::2]]
        contact(thumbs, OUT_ROOT / f"{subject}_{tag}_contact.jpg", columns)
    return numbers


def write_summary(all_numbers: dict) -> None:
    (OUT_ROOT / "summary.json").write_text(json.dumps(all_numbers, indent=2) + "\n")
    lines = ["| subject | state | root y | gap to soil (u) | lowest foot (u) | both feet off | strike gap (u) | slide (|v| / along) | body amp (u) | cadence c/s |",
             "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |"]
    for subject, states in all_numbers.items():
        for state, n in states.items():
            cadence = f"{n['cadence']:.2f}" if n.get("cadence") else "-"
            lines.append(f"| {subject} | {state} | {n['root_y']:.3f} | {n['ground_gap_mean']:.3f} | {n['lowest_foot_mean']:.3f} | "
                         f"{n['both_off_ratio']*100:.0f}% | {n['strike_gap_mean']:.3f} | {n['slide_ratio']*100:.0f}% / {n['slide_along_ratio']*100:+.0f}% | "
                         f"{n['vertical_amplitude']:.3f} | {cadence} |")
    (OUT_ROOT / "summary.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--state", default="after", help="capture folder name (before / after)")
    parser.add_argument("--root-y", default="", help="hero=Y,monster=Y overrides (default: world constants)")
    parser.add_argument("--only", action="append", help="subject label(s) to run")
    parser.add_argument("--frames", type=int, default=48)
    parser.add_argument("--display-base", type=int, default=170)
    parser.add_argument("--assemble-only", action="store_true")
    parser.add_argument("--states", default="before,after", help="states to put side by side")
    args = parser.parse_args()
    ensure_xvfb()
    OUT_ROOT.mkdir(parents=True, exist_ok=True)
    overrides = {}
    for item in filter(None, args.root_y.split(",")):
        key, value = item.split("=")
        overrides[key.strip()] = float(value)
    failed = False
    if not args.assemble_only:
        for n, (label, kind, cid, speed) in enumerate(SUBJECTS):
            if args.only and label not in args.only:
                continue
            out = OUT_ROOT / args.state / label
            if not run_probe(kind, cid, speed, out, args.display_base + n, overrides.get(kind), args.frames):
                failed = True
    states = args.states.split(",")
    all_numbers = {}
    for label, _kind, _cid, _speed in SUBJECTS:
        if args.only and label not in args.only and not args.assemble_only:
            continue
        numbers = assemble(label, states)
        if numbers:
            all_numbers[label] = numbers
    write_summary(all_numbers)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
