#!/usr/bin/env python3
"""Capture sword melee strikes, per-character gait and the hero info pop-up in real GL
at both mobile window sizes, then assemble review media.

    python3 tools/3d/melee_review.py                        # 1280x800 + 1000x625, everything
    python3 tools/3d/melee_review.py --res 1280x800 --only strike
    python3 tools/3d/melee_review.py --out-root build/melee-speed/before --current-range
    python3 tools/3d/melee_review.py --assemble-only --compare build/melee-speed/before   # before/after sheets

Outputs under <out-root>/<res>/:
  strike_NN.png            consecutive 33 ms frames of the pinned-monster strike scene
  strike.gif               the whole field;  strike_<id>.gif / strike_<id>_contact.jpg: 2x crops per sword hero
  gait_<id>_NN.png         the fast (pip) and slow (brasa) runner on the same lane under the joystick
  gait_<id>.gif            lane crop;  gait_side_by_side.gif / gait_contact.jpg: fast over slow
  hero_info_<id>_<lc>.png  the pop-up in ko / en;  hero_info_contact.jpg
  render.log, info-render.log, melee-report.json, hero-info-report.json
and <out-root>/stage/<id>_<speed>/gait_NN.png from the isolated stage
(tests/3d/native_character_visual_preview.tscn --gait-only), composed into stage_gait.gif.
Any ERROR / SCRIPT ERROR / failed check in a log fails the run.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from godot_env import ROOT, GODOT, ensure_xvfb, xvfb  # noqa: E402

DESIGN = (1280.0, 800.0)
FONT = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 16)
STAGE = [("pip", 5.1), ("brasa", 2.1), ("jokull", 3.4)]


def run_godot(scene: str, res: str, display: int, extra: list[str], log: Path) -> bool:
    command = [str(GODOT), "--path", str(ROOT), "--resolution", res, scene, "--", *extra]
    with xvfb(display, res) as env:
        result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=3600)
    text = result.stdout + "\n" + result.stderr
    log.write_text(text)
    errors = [line for line in text.splitlines() if "ERROR:" in line or "SCRIPT ERROR" in line or line.startswith("!! ")]
    verdict = ("판정: 정상" in result.stdout) or ("Actual native visual capture" in result.stdout) or scene.endswith("native_character_visual_preview.tscn")
    print(f"{scene.split('/')[-1]} {res}: exit {result.returncode}, verdict {verdict}, errors {len(errors)}")
    for line in errors[:12]:
        print("   ", line)
    return result.returncode == 0 and verdict and not errors


def scaled_box(center: tuple[float, float], size: tuple[float, float], window: tuple[int, int]) -> tuple[int, int, int, int]:
    sx = window[0] / DESIGN[0]
    sy = window[1] / DESIGN[1]
    return (int((center[0] - size[0] / 2) * sx), int((center[1] - size[1] / 2) * sy),
            int((center[0] + size[0] / 2) * sx), int((center[1] + size[1] / 2) * sy))


def save_gif(frames: list[Image.Image], dest: Path, duration: int) -> None:
    if not frames:
        return
    frames[0].save(dest, save_all=True, append_images=frames[1:], duration=duration, loop=0)


def contact(frames: list[Image.Image], dest: Path, columns: int, label: str = "") -> None:
    if not frames:
        return
    w, h = frames[0].size
    rows = (len(frames) + columns - 1) // columns
    sheet = Image.new("RGB", (w * columns, h * rows + (24 if label else 0)), (10, 20, 30))
    draw = ImageDraw.Draw(sheet)
    top = 0
    if label:
        draw.text((8, 3), label, font=FONT, fill=(235, 243, 247))
        top = 24
    for n, frame in enumerate(frames):
        sheet.paste(frame, ((n % columns) * w, top + (n // columns) * h))
        draw.text(((n % columns) * w + 4, top + (n // columns) * h + h - 20), f"{n:02d}", font=FONT, fill=(255, 230, 160))
    sheet.save(dest, quality=90)


def labelled(frame: Image.Image, text: str) -> Image.Image:
    out = frame.copy()
    draw = ImageDraw.Draw(out)
    draw.rectangle((0, 0, out.width, 22), fill=(10, 20, 30))
    draw.text((6, 3), text, font=FONT, fill=(235, 243, 247))
    return out


def assemble_strikes(out: Path, report: dict) -> None:
    files = sorted(out.glob("strike_[0-9][0-9].png"))
    if not files:
        return
    window = tuple(report["window"])
    frames = [Image.open(path).convert("RGB") for path in files]
    small = [frame.resize((frame.width // 2, frame.height // 2), Image.LANCZOS) for frame in frames]
    save_gif(small, out / "strike.gif", 33)
    for hid, row in report["heroes"].items():
        if not row.get("melee") or "screen" not in row:
            continue
        box = scaled_box((row["screen"][0], row["screen"][1] - 36), (300, 236), window)
        crops = [frame.crop(box) for frame in frames]
        zoom = [crop.resize((crop.width * 2, crop.height * 2), Image.LANCZOS) for crop in crops]
        text = f"{hid}  reach {row['reach_units']:.2f} u ({row['reach']:.0f})  tier {row['tier']}"
        save_gif([labelled(frame, text) for frame in zoom], out / f"strike_{hid}.gif", 33)
        contact(crops, out / f"strike_{hid}_contact.jpg", 10, text)


def assemble_gait(out: Path, report: dict) -> None:
    window = tuple(report["window"])
    lanes: dict[str, list[Image.Image]] = {}
    for hid, row in report.get("gait", {}).items():
        files = sorted(out.glob(f"gait_{hid}_[0-9][0-9].png"))
        if not files:
            continue
        x0 = min(row["from"][0], row["to"][0]) - 70
        x1 = max(row["from"][0], row["to"][0]) + 70
        center = ((x0 + x1) / 2, row["from"][1] - 30)
        size = (max(x1 - x0, 420), 200)
        box = scaled_box(center, size, window)
        crops = [Image.open(path).convert("RGB").crop(box) for path in files]
        text = f"{hid}  spd {row['spd']:.2f}  {row['units_per_s']:.2f} u/s  ({row['speed']:.0f} logical/s)"
        lanes[hid] = [labelled(crop, text) for crop in crops]
        save_gif(lanes[hid], out / f"gait_{hid}.gif", 33)
        contact(crops[::3], out / f"gait_{hid}_contact.jpg", 7, text)
    if len(lanes) >= 2:
        keys = list(lanes.keys())
        count = min(len(lanes[k]) for k in keys)
        width = max(lanes[k][0].width for k in keys)
        combined = []
        for n in range(count):
            height = sum(lanes[k][n].height for k in keys) + 4 * (len(keys) - 1)
            frame = Image.new("RGB", (width, height), (10, 20, 30))
            y = 0
            for k in keys:
                frame.paste(lanes[k][n], (0, y))
                y += lanes[k][n].height + 4
            combined.append(frame)
        save_gif(combined, out / "gait_side_by_side.gif", 33)
        contact(combined[::4], out / "gait_contact.jpg", 4)


def assemble_info(out: Path) -> None:
    files = sorted(out.glob("hero_info_*_ko.png")) + sorted(out.glob("hero_info_*_en.png"))
    if not files:
        return
    thumbs = []
    for path in files:
        image = Image.open(path).convert("RGB")
        image.thumbnail((640, 400))
        thumbs.append(labelled(image, path.stem))
    contact(thumbs, out / "hero_info_contact.jpg", 2)


def assemble_stage(root: Path) -> None:
    lanes = []
    for hid, speed in STAGE:
        folder = root / "stage" / f"{hid}_{speed:.1f}"
        files = sorted(folder.glob("gait_[0-9][0-9].png"))
        if not files:
            continue
        frames = []
        for path in files:
            pic = Image.open(path).convert("RGBA")
            back = Image.new("RGBA", pic.size, (15, 27, 40, 255))
            back.alpha_composite(pic)
            frames.append(labelled(back.convert("RGB").resize((pic.width // 2, pic.height // 2), Image.LANCZOS), f"{hid}  {speed:.1f} u/s"))
        save_gif(frames, folder / "gait.gif", 33)
        contact(frames[::3], folder / "gait_contact.jpg", 8)
        lanes.append(frames)
    if len(lanes) >= 2:
        count = min(len(lane) for lane in lanes)
        combined = []
        for n in range(count):
            width = sum(lane[n].width for lane in lanes) + 4 * (len(lanes) - 1)
            frame = Image.new("RGB", (width, lanes[0][n].height), (10, 20, 30))
            x = 0
            for lane in lanes:
                frame.paste(lane[n], (x, 0))
                x += lane[n].width + 4
            combined.append(frame)
        save_gif(combined, root / "stage" / "stage_gait.gif", 33)
        contact(combined[::3], root / "stage" / "stage_gait_contact.jpg", 4)


def compare(before: Path, after: Path, res: str) -> None:
    """Before/after sheets from two capture roots of the same scene (same seed, same frames):
    the first strike of each sword hero at 2x and the two gait lanes."""
    a_report = json.loads((after / res / "melee-report.json").read_text())
    b_dir, a_dir = before / res, after / res
    window = tuple(a_report["window"])
    rows = []
    strikes = {"jokull": [21, 22, 23, 24], "caden": [8, 9, 10, 11], "helga": [14, 15, 16, 17], "pip": [20, 21, 22, 23]}
    for hid, frames in strikes.items():
        row = a_report["heroes"].get(hid)
        if row is None or "screen" not in row:
            continue
        box = scaled_box((row["screen"][0], row["screen"][1] - 36), (300, 236), window)
        for tag, folder in (("before", b_dir), ("after", a_dir)):
            tiles = []
            for n in frames:
                path = folder / f"strike_{n:02d}.png"
                if not path.exists():
                    continue
                crop = Image.open(path).convert("RGB").crop(box)
                tiles.append(labelled(crop.resize((crop.width * 2, crop.height * 2), Image.LANCZOS), f"{tag}  {hid} {n:02d}"))
            if tiles:
                rows.append(tiles)
    if rows:
        w, h = rows[0][0].size
        cols = max(len(r) for r in rows)
        sheet = Image.new("RGB", (w * cols, h * len(rows)), (10, 20, 30))
        for y, tiles in enumerate(rows):
            for x, tile in enumerate(tiles):
                sheet.paste(tile, (x * w, y * h))
        sheet.save(after / f"compare_strike_before_after_{res}.jpg", quality=90)
    lanes = []
    for hid, row in a_report.get("gait", {}).items():
        x0 = min(row["from"][0], row["to"][0]) - 70
        x1 = max(row["from"][0], row["to"][0]) + 70
        box = scaled_box(((x0 + x1) / 2, row["from"][1] - 30), (max(x1 - x0, 420), 200), window)
        for tag, folder in (("before", b_dir), ("after", a_dir)):
            tiles = []
            for n in range(0, 42, 3):
                path = folder / f"gait_{hid}_{n:02d}.png"
                if path.exists():
                    tiles.append(labelled(Image.open(path).convert("RGB").crop(box), f"{tag}  {hid}  spd {row['spd']:.2f}  #{n:02d}"))
            if tiles:
                lanes.append(tiles)
    if lanes:
        w, h = lanes[0][0].size
        cols = 7
        rows_n = sum((len(t) + cols - 1) // cols for t in lanes)
        sheet = Image.new("RGB", (w * cols, h * rows_n), (10, 20, 30))
        y = 0
        for tiles in lanes:
            for i, tile in enumerate(tiles):
                sheet.paste(tile, ((i % cols) * w, (y + i // cols) * h))
            y += (len(tiles) + cols - 1) // cols
        sheet.save(after / f"compare_gait_before_after_{res}.jpg", quality=90)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--res", action="append", help="WxH; repeatable (default 1280x800 and 1000x625)")
    parser.add_argument("--only", choices=["strike", "gait", "info", "stage", "arena"], help="one capture group")
    parser.add_argument("--frames", type=int, default=72)
    parser.add_argument("--current-range", action="store_true", help="keep the file's sword reach instead of the planned 60-base reach")
    parser.add_argument("--out-root", default=str(ROOT / "build/melee-speed"))
    parser.add_argument("--display-base", type=int, default=160)
    parser.add_argument("--assemble-only", action="store_true")
    parser.add_argument("--compare", help="an earlier capture root of the same scene; writes compare_*_before_after_<res>.jpg into --out-root")
    args = parser.parse_args()
    ensure_xvfb()
    root = Path(args.out_root)
    failed = False
    resolutions = args.res or ["1280x800", "1000x625"]
    for index, res in enumerate(resolutions):
        out = root / res
        out.mkdir(parents=True, exist_ok=True)
        display = args.display_base + index * 2
        if args.only in (None, "strike", "gait", "arena") and not args.assemble_only:
            for stale in list(out.glob("strike_*.png")) + list(out.glob("gait_*.png")):
                stale.unlink()
            extra = ["--out", str(out), "--frames", str(args.frames)]
            if not args.current_range:
                extra.append("--planned-range")
            if args.only == "strike":
                extra.append("--strike-only")
            if args.only == "gait":
                extra.append("--gait-only")
            if not run_godot("res://tests/3d/melee_visual_preview.tscn", res, display, extra, out / "render.log"):
                failed = True
        if args.only in (None, "info") and not args.assemble_only:
            if not run_godot("res://tests/3d/hero_info_visual_preview.tscn", res, display + 1, ["--out", str(out)], out / "info-render.log"):
                failed = True
        report_path = out / "melee-report.json"
        if report_path.exists():
            report = json.loads(report_path.read_text())
            assemble_strikes(out, report)
            assemble_gait(out, report)
            if report.get("events"):
                print("   ", json.dumps(report["events"], ensure_ascii=False))
        assemble_info(out)
        if args.compare and (Path(args.compare) / res / "strike_00.png").exists() and report_path.exists():
            compare(Path(args.compare), root, res)
    if args.only in (None, "stage") and not args.assemble_only:
        for n, (hid, speed) in enumerate(STAGE):
            folder = root / "stage" / f"{hid}_{speed:.1f}"
            folder.mkdir(parents=True, exist_ok=True)
            for stale in folder.glob("gait_*.png"):
                stale.unlink()
            extra = ["--id", hid, "--out", str(folder), "--gait-only", "--speed", str(speed)]
            if not run_godot("res://tests/3d/native_character_visual_preview.tscn", "1280x800", args.display_base + 10 + n, extra, folder / "render.log"):
                failed = True
    assemble_stage(root)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
