#!/usr/bin/env python3
"""Flying-monster review: run tests/3d/flyer_visual_preview.tscn in real GL at both review
sizes and assemble, per flyer, GIFs, an MP4 and contact sheets cropped around the body
(spawn descent, lane walk beside a walker and a kerb hero, hits, crystal siege, death).

    python3 tests/3d/flyer_review.py --out-root build/flyers/before          # current tree
    python3 tests/3d/flyer_review.py --out-root build/flyers/after --before build/flyers/before
    python3 tests/3d/flyer_review.py --out-root build/flyers/after --res 1280x800 --ids rapid_ray
    python3 tests/3d/flyer_review.py --out-root build/flyers/after --assemble-only

Godot draws into an off-screen picture of the requested size on the login session's GPU
display when it is there (REVIEW_DISPLAY=xvfb forces software GL), always --disable-vsync.

Outputs under <out-root>/<res>/: <id>_{spawn,walk,siege,die}_NN.png, <id>.gif (whole frame,
half size), <id>_focus.gif / <id>_focus.mp4 (2x crop following the body), <id>_focus_contact.jpg,
<id>_keyframes.jpg (descent, beside the walker, the hit, the siege strike, the fall),
flyers_sheet.jpg (the three flyers' key frames) and, with --before, <id>_before_after.jpg.
flyers-report.json carries per-frame screen positions, hit flash and the fly-height meta;
render.log the Godot output. Any ERROR / failed check fails the run.
"""
from __future__ import annotations

import argparse
import contextlib
import json
import os
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from godot_env import ROOT, GODOT, xvfb  # noqa: E402

FONT = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 15)
SMALL = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 12)
FLYERS = ["rapid_ray", "jelly_seer", "runestone_idol"]
STAGES = ["spawn", "walk", "siege", "die"]
# Focus crop around the flyer's ground point, in 1280x800 design pixels (then scaled).
HALF_W, UP, DOWN = 150, 250, 70


def gpu_display(res: str, base: int):
    """The login session's GPU X server when it is there, else a software Xvfb."""
    auth = Path(f"/run/user/{os.getuid()}/gdm/Xauthority")
    if os.environ.get("REVIEW_DISPLAY", "auto") != "xvfb" and auth.exists():
        env = dict(os.environ, DISPLAY=":1", XAUTHORITY=str(auth), STELLARDEFENSE_NO_SAVE="1")
        probe = subprocess.run(["xdpyinfo", "-queryExtensions"], env=env, capture_output=True, text=True)
        if probe.returncode == 0 and "NV-GLX" in probe.stdout:
            return contextlib.nullcontext(env)
    return xvfb(base, res)


def labelled(frame: Image.Image, text: str, size=FONT) -> Image.Image:
    out = frame.copy()
    draw = ImageDraw.Draw(out)
    draw.rectangle((0, 0, out.width, 18), fill=(8, 18, 28))
    draw.text((4, 1), text, font=size, fill=(235, 243, 247))
    return out


def save_gif(frames, dest: Path, duration: int = 50) -> None:
    if frames:
        frames[0].save(dest, save_all=True, append_images=frames[1:], duration=duration, loop=0)


def contact(frames, dest: Path, columns: int) -> None:
    if not frames:
        return
    w = max(f.width for f in frames)
    h = max(f.height for f in frames)
    rows = (len(frames) + columns - 1) // columns
    sheet = Image.new("RGB", (w * columns, h * rows), (8, 18, 28))
    for n, frame in enumerate(frames):
        sheet.paste(frame, ((n % columns) * w, (n // columns) * h))
    sheet.save(dest, quality=90)


def run(res: str, display: int, ids: list[str] | None, out: Path, walk_every: int) -> bool:
    out.mkdir(parents=True, exist_ok=True)
    for stale in out.glob("*_[0-9][0-9].png"):
        stale.unlink()
    extra = ["--out", str(out), "--film", res, "--walk-every", str(walk_every)]
    if ids:
        extra += ["--ids", ",".join(ids)]
    command = [str(GODOT), "--path", str(ROOT), "--resolution", "96x60", "--disable-vsync",
               "res://tests/3d/flyer_visual_preview.tscn", "--", *extra]
    log_path = out / "render.log"
    with gpu_display(res, display) as env:
        env = dict(env, STELLARDEFENSE_NO_SAVE="1")
        with log_path.open("w") as stream:
            result = subprocess.run(command, env=env, stdout=stream, stderr=subprocess.STDOUT, text=True, timeout=3600)
    text = log_path.read_text()
    errors = [line for line in text.splitlines()
              if ("ERROR:" in line and "still in use at exit" not in line) or "SCRIPT ERROR" in line or line.startswith("!! ")]
    ok = result.returncode == 0 and "판정: 정상" in text and not errors
    print(f"flyers {res}: exit {result.returncode}, errors {len(errors)}, {'ok' if ok else 'FAILED'}")
    for line in errors[:12]:
        print("   ", line)
    if not ok:
        print("\n".join(text.splitlines()[-30:]))
    return ok


class Flyer:
    """One flyer's frames of one resolution, with the report rows that describe them."""

    def __init__(self, out: Path, fid: str, record: dict, picture: list[int]):
        self.out, self.id, self.record = out, fid, record
        self.scale = picture[0] / 1280.0
        self.rows = {(r["stage"], r["index"]): r for r in record.get("rows", [])}
        self.frames: list[tuple[str, int, Path]] = []
        for stage in STAGES:
            for path in sorted(out.glob(f"{fid}_{stage}_[0-9][0-9].png")):
                self.frames.append((stage, int(path.stem[-2:]), path))

    def row(self, stage: str, index: int) -> dict:
        return self.rows.get((stage, index), {})

    def label(self, stage: str, index: int) -> str:
        flyer = self.row(stage, index).get("flyer", {})
        text = f"{self.id}  {stage} {index:02d}"
        if flyer:
            text += f"  h {flyer.get('fly_height', 0.0):.2f}u"
            if flyer.get("flash", 0.0) > 0.05:
                text += f"  HIT {flyer['flash']:.2f}"
            if flyer.get("siege_t", -1.0) >= 0.0:
                text += f"  siege {flyer['siege_t']:.2f}"
            if flyer.get("dying"):
                text += "  dying"
        return text

    def centre(self, stage: str, index: int) -> tuple[float, float] | None:
        flyer = self.row(stage, index).get("flyer", {})
        if not flyer:
            return None
        x, y = flyer["foot"]
        return x * self.scale, y * self.scale

    def focus(self, stage: str, index: int, path: Path, zoom: int = 2) -> Image.Image:
        image = Image.open(path).convert("RGB")
        centre = self.centre(stage, index) or self.last_centre
        self.last_centre = centre
        cx, cy = centre
        s = self.scale
        box = (int(cx - HALF_W * s), int(cy - UP * s), int(cx + HALF_W * s), int(cy + DOWN * s))
        crop = image.crop(box)
        crop = crop.resize((crop.width * zoom, crop.height * zoom), Image.LANCZOS)
        return labelled(crop, self.label(stage, index), SMALL)

    last_centre = (640.0, 420.0)

    def find(self, stage: str, index: int) -> Path | None:
        for st, n, path in self.frames:
            if st == stage and n == index:
                return path
        return None

    def key_frames(self) -> list[tuple[str, int, str]]:
        """(stage, index, caption): descent, beside the walker, the hit, the strike, the fall."""
        keys: list[tuple[str, int, str]] = []
        counts = {st: sum(1 for s, _, _ in self.frames if s == st) for st in STAGES}
        for n in (0, 4, 8, 13):
            if n < counts["spawn"]:
                keys.append(("spawn", n, "descent"))
        for n in (1, 6, 12):
            if n < counts["walk"]:
                keys.append(("walk", n, "lane"))
        hit = next(((st, n) for st, n, _ in self.frames if st in ("walk", "siege")
                    and self.row(st, n).get("flyer", {}).get("flash", 0.0) >= 0.5), None)
        if hit:
            keys.append((hit[0], hit[1], "hit"))
        # The strike lands when siege_t wraps: the frame with the highest phase before a drop.
        siege = [(n, self.row("siege", n).get("flyer", {}).get("siege_t", -1.0)) for st, n, _ in self.frames if st == "siege"]
        strike = None
        for (n, t), (m, u) in zip(siege, siege[1:]):
            if u < t and t > 0.8:
                strike = n
                break
        if strike is not None:
            for n in (strike - 9, strike - 3, strike, min(strike + 2, counts["siege"] - 1)):
                if 0 <= n < counts["siege"]:
                    keys.append(("siege", n, "siege"))
        elif counts["siege"]:
            keys.append(("siege", counts["siege"] // 2, "siege"))
        for n in (0, 5, 10, 15, counts["die"] - 1):
            if 0 <= n < counts["die"]:
                keys.append(("die", n, "fall"))
        return keys


def assemble(out: Path, before: Path | None) -> None:
    report_path = out / "flyers-report.json"
    if not report_path.exists():
        return
    report = json.loads(report_path.read_text())
    picture = report.get("picture", [1280, 800])
    sheet_rows: list[list[Image.Image]] = []
    for fid, record in report["flyers"].items():
        flyer = Flyer(out, fid, record, picture)
        if not flyer.frames:
            continue
        whole = []
        focus = []
        for stage, n, path in flyer.frames:
            image = Image.open(path).convert("RGB")
            whole.append(labelled(image.resize((image.width // 2, image.height // 2), Image.LANCZOS), flyer.label(stage, n)))
            focus.append(flyer.focus(stage, n, path))
        save_gif(whole, out / f"{fid}.gif", 66)
        save_gif(focus, out / f"{fid}_focus.gif", 50)
        contact(focus[::3], out / f"{fid}_focus_contact.jpg", 6)
        folder = out / f"{fid}_focus_frames"
        folder.mkdir(exist_ok=True)
        for stale in folder.glob("*.png"):
            stale.unlink()
        for index, frame in enumerate(focus):
            even = frame.crop((0, 0, frame.width - frame.width % 2, frame.height - frame.height % 2))
            even.save(folder / f"{index:04d}.png")
        result = subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", "20", "-i", str(folder / "%04d.png"),
                                 "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "20", str(out / f"{fid}_focus.mp4")],
                                capture_output=True, text=True)
        if result.returncode:
            print("ffmpeg:", result.stderr.strip()[-400:])
        keys = flyer.key_frames()
        key_frames = []
        for stage, n, caption in keys:
            path = flyer.find(stage, n)
            if path:
                key_frames.append(labelled(flyer.focus(stage, n, path), f"{caption}: {flyer.label(stage, n)}", SMALL))
        contact(key_frames, out / f"{fid}_keyframes.jpg", 4)
        picks = [k for k in keys if k[2] in ("descent", "lane", "hit", "siege", "fall")]
        chosen = []
        for caption in ("descent", "lane", "hit", "siege", "fall"):
            group = [k for k in picks if k[2] == caption]
            if group:
                pick = group[len(group) // 2] if caption != "siege" else group[-2] if len(group) >= 2 else group[0]
                chosen.append(pick)
        row_images = []
        for stage, n, caption in chosen:
            path = flyer.find(stage, n)
            if path:
                row_images.append(labelled(flyer.focus(stage, n, path), f"{caption}: {flyer.label(stage, n)}", SMALL))
        sheet_rows.append(row_images)
        if before is not None:
            old_report = before / "flyers-report.json"
            if old_report.exists():
                old = json.loads(old_report.read_text())
                if fid in old["flyers"]:
                    other = Flyer(before, fid, old["flyers"][fid], old.get("picture", picture))
                    pairs = []
                    for stage, n, caption in chosen:
                        a = other.find(stage, n)
                        b = flyer.find(stage, n)
                        if a and b:
                            pairs.append(labelled(other.focus(stage, n, a), f"BEFORE {caption}: {other.label(stage, n)}", SMALL))
                            pairs.append(labelled(flyer.focus(stage, n, b), f"AFTER {caption}: {flyer.label(stage, n)}", SMALL))
                    contact(pairs, out / f"{fid}_before_after.jpg", 2)
        heights = record.get("fly_height", {})
        print(f"  {fid}: frames {record.get('frames')}  fly_height {heights}  siege distance {record.get('siege_distance', 0):.0f} logical")
    if sheet_rows:
        columns = max(len(r) for r in sheet_rows)
        flat = []
        for row in sheet_rows:
            flat += row + [Image.new("RGB", row[0].size, (8, 18, 28))] * (columns - len(row))
        contact(flat, out / "flyers_sheet.jpg", columns)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out-root", default="build/flyers/after")
    parser.add_argument("--before", help="earlier capture root for before/after sheets")
    parser.add_argument("--res", action="append")
    parser.add_argument("--ids", help="comma separated flyer ids")
    parser.add_argument("--walk-every", type=int, default=3)
    parser.add_argument("--display-base", type=int, default=230)
    parser.add_argument("--assemble-only", action="store_true")
    args = parser.parse_args()
    root = ROOT / args.out_root
    before = ROOT / args.before if args.before else None
    ids = args.ids.split(",") if args.ids else None
    failed = False
    for n, res in enumerate(args.res or ["1280x800", "1000x625"]):
        out = root / res
        if not args.assemble_only and not run(res, args.display_base + n, ids, out, args.walk_every):
            failed = True
        assemble(out, before / res if before else None)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
