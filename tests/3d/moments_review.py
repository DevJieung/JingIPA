#!/usr/bin/env python3
"""Capture the run-level battle moments in real GL and assemble review media.

    python3 tests/3d/moments_review.py                         # dark + bright field, both sizes
    python3 tests/3d/moments_review.py --theme 29 --res 1280x800 --moment revive
    python3 tests/3d/moments_review.py --theme 0 --next-theme 18 --moment stage --speed 3

The moments (tests/3d/vfx_visual_preview.tscn --moments): a fresh run's first battlefield
(its reveal under the first card and the first rite, then running as the battle starts),
the escort of a fallen stage boss fleeing in step with its haze (scatter), the crystal's revival
(arena_revive: in battle, taken back from the defeat screen, resumed from a save inside
the untouchable window, and carried over a stage change), a stage clear (arena_stage_clear
with the scattering escort), the next battlefield's reveal under and after its card
(arena_stage, with leftovers planted before the change to prove none survive), and the
final boss: its entrance (arena_boss_warning / arena_boss with final), its fall
(arena_stage_clear with final) and the still that the result panel freezes.
The default fields are a dark and the brightest floor of the fifty: the volcano crater
(18, CIE L* 45, ground_wash 0) and the calm lake (0, L* 65, ground_wash 0.90).
The reveal is filmed on the battlefield that opens after the clear (theme + 29, or
--next-theme): the bright glacier crevasse after 18, the dark world-tree roots after 0.
Other fields worth a look: the dark water of the deep trench (8) and the bright stone of
the broken wall (34), where the old per-biome brightness rule was wrong.

Godot runs on the login session's GPU X display when there is one (a 96x60 window; the
game is drawn into an off-screen viewport of the requested size), otherwise on Xvfb
software GL (slow). MOMENTS_DISPLAY=xvfb forces the fallback.

Outputs under --out-root/<theme>/<res>/ (default build/vfx-stage):
  <prefix>_NNN.png     frames (60 Hz ticks for the fast parts, 30 Hz for the tails)
  <prefix>_sheet.jpg   contact sheet of the whole screen
  <prefix>_focus.jpg   contact sheet cropped around the crystal / gate at screen pixels
  <prefix>.mp4         real-time film;  <prefix>_focus.gif  the crop as a GIF
  scatter_bodies.jpg   one row per followed escort at 3x nearest, every other tick: the halt,
                       the run from the crystal and the thinning (scatterkill_* is the same
                       crowd dying the ordinary way, for comparison)
  first_card.png       a fresh run's first battlefield under its card (first_field.png: the 3D
                       picture alone; first_rite.png: the first rite over it); first_NNN is the
                       reveal running as the first battle starts
  stage_card.png       the paused first frame of a new battlefield under its card
  stage_field.png      the same frame's 3D picture without the 2D overlay
  resume_stage_card.png  a stage change while the revival's aegis is still running
  final_result.png     the won run frozen under the result panel; final_rest_field.png is
                       its 3D picture alone, final_settle.png the same after a hitch,
                       final_retry_card.png the first card of the next run (nothing left)
  render.log, vfx-report.json   (render-<moment>.log, vfx-report-<moment>.json for a
                       single-moment run, so the full run's are not replaced)
"""
from __future__ import annotations

import argparse
import contextlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from godot_env import ROOT, GODOT, xvfb  # noqa: E402

SCENE = "res://tests/3d/vfx_visual_preview.tscn"
DESIGN = (1280, 800)
BAD = ("SCRIPT ERROR", "ERROR:", "Parse Error")
# The engine's own shutdown report, printed after the run has finished and been judged
# (seen now and then when a sound is still playing at quit). Shown as a note, not a failure.
AT_EXIT = ("resources still in use at exit",)
# Sequence prefixes each --moment writes (stale files of the others are kept).
PREFIXES = {"first": ("first",), "revive": ("revive", "resume"), "clear": ("clear", "stage"), "stage": ("stage",),
            "final": ("final",), "scatter": ("scatter_",), "scatterkill": ("scatterkill",)}


def display_env(res: str):
    """(context manager yielding env, film) - the GPU display with a film, or Xvfb with a window."""
    auth = Path(f"/run/user/{os.getuid()}/gdm/Xauthority")
    if os.environ.get("MOMENTS_DISPLAY", "auto") != "xvfb" and auth.exists():
        env = dict(os.environ, DISPLAY=":1", XAUTHORITY=str(auth), STELLARDEFENSE_NO_SAVE="1")
        probe = subprocess.run(["xdpyinfo", "-queryExtensions"], env=env, capture_output=True, text=True)
        if probe.returncode == 0 and "NV-GLX" in probe.stdout:
            return contextlib.nullcontext(env), True
    return xvfb(240, res), False


def frames_of(out: Path, prefix: str) -> list[Path]:
    return sorted(out.glob(f"{prefix}_[0-9][0-9][0-9].png"))


def crop_box(size: tuple[int, int], centre: list[int], half: tuple[int, int]) -> tuple[int, int, int, int]:
    """A box around a design-canvas point, in the pixels of a frame of `size`."""
    sx = size[0] / DESIGN[0]
    sy = size[1] / DESIGN[1]
    cx, cy = centre[0] * sx, centre[1] * sy
    w, h = half[0] * sx, half[1] * sy
    x0 = int(max(0, min(size[0] - 2 * w, cx - w)))
    y0 = int(max(0, min(size[1] - 2 * h, cy - h)))
    return (x0, y0, int(x0 + 2 * w), int(y0 + 2 * h))


def sheet(images: list[Image.Image], labels: list[str], columns: int, path: Path, tile_w: int) -> None:
    from PIL import ImageDraw
    if not images:
        return
    w, h = images[0].size
    th = round(h * tile_w / w)
    rows = (len(images) + columns - 1) // columns
    out = Image.new("RGB", (tile_w * columns, th * rows), (8, 15, 25))
    draw = ImageDraw.Draw(out)
    for n, im in enumerate(images):
        x, y = (n % columns) * tile_w, (n // columns) * th
        out.paste(im.resize((tile_w, th), Image.LANCZOS), (x, y))
        draw.rectangle((x, y, x + 74, y + 13), fill=(0, 0, 0))
        draw.text((x + 3, y + 1), labels[n], fill=(255, 255, 255))
    out.save(path, quality=90)


def body_strips(out: Path, seq: dict, files: list[Path], step: float) -> None:
    """One row per followed body: its rectangle at 3x nearest, every other tick from the
    event on, so the halt, the run and the thinning can be read frame by frame."""
    from PIL import ImageDraw
    first = int(seq.get("event_frame", 0))
    picks = list(range(max(0, first - 1), len(files), 2))[:34]
    frames = [Image.open(files[n]).convert("RGB") for n in picks]
    sx = frames[0].size[0] / DESIGN[0]
    zoom = 3
    rows = []
    for body in seq["bodies"]:
        x, y, w, h = body["rect"]
        box = (int(x * sx), int(y * sx), int((x + w) * sx), int((y + h) * sx))
        tiles = [im.crop(box).resize(((box[2] - box[0]) * zoom, (box[3] - box[1]) * zoom), Image.NEAREST) for im in frames]
        rows.append((body, tiles))
    cell_w = max(t[1][0].size[0] for t in rows)
    total_h = sum(t[1][0].size[1] + 16 for t in rows)
    sheet_image = Image.new("RGB", (cell_w * len(picks), total_h), (8, 15, 25))
    draw = ImageDraw.Draw(sheet_image)
    y = 0
    for body, tiles in rows:
        draw.text((4, y + 2), f"{body['label']}  wave arrives +{body['wait']:.2f}s", fill=(255, 255, 255))
        for column, tile in enumerate(tiles):
            sheet_image.paste(tile, (column * cell_w, y + 16))
            t = (picks[column] - first + 1) * step
            mark = (255, 220, 120) if abs(t - body["wait"]) <= step else (150, 170, 190)
            draw.text((column * cell_w + 3, y + 18), f"{t:+.2f}", fill=mark)
        y += tiles[0].size[1] + 16
    sheet_image.save(out / f"{seq['prefix']}_bodies.jpg", quality=92)


def assemble(out: Path, seq: dict, every: int, focus_half: tuple[int, int]) -> None:
    prefix = seq["prefix"]
    files = frames_of(out, prefix)
    if not files:
        return
    step = seq["tick"] * seq["ticks_per_frame"]        # seconds of real time per frame
    start = float(seq.get("starts_at", 0.0)) - float(seq.get("event_frame", 0)) * step
    picks = list(range(0, len(files), max(1, every)))
    images = [Image.open(files[n]).convert("RGB") for n in picks]
    labels = [f"{n:03d} {start + n * step:+.2f}s" for n in picks]
    sheet(images, labels, 5, out / f"{prefix}_sheet.jpg", 512)
    for key in ("crystal", "gate", "boss"):
        if key not in seq:
            continue
        box = crop_box(images[0].size, seq[key], focus_half)
        crops = [im.crop(box) for im in images]
        name = f"{prefix}_focus.jpg" if key != "boss" else f"{prefix}_boss.jpg"
        sheet(crops, labels, 5, out / name, max(320, box[2] - box[0]))
        if key != "boss":
            every_gif = max(1, round(1 / 30 / step))
            gif = [Image.open(f).convert("RGB").crop(box) for f in files[::every_gif]]
            gif[0].save(out / f"{prefix}_focus.gif", save_all=True, append_images=gif[1:],
                        duration=round(1000 * step * every_gif), loop=0)
    for n, gate in enumerate(seq.get("gates", [])):
        box = crop_box(images[0].size, gate, (150, 130))
        sheet([im.crop(box) for im in images], labels, 6, out / f"{prefix}_gate{n}.jpg", max(240, box[2] - box[0]))
    if seq.get("bodies"):
        body_strips(out, seq, files, step)
    if shutil.which("ffmpeg"):
        fps = max(1, round(1 / step))
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(fps), "-i", str(out / f"{prefix}_%03d.png"),
                        "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2", "-pix_fmt", "yuv420p", "-crf", "17",
                        str(out / f"{prefix}.mp4")], check=False)


def run(theme: int, res: str, args: argparse.Namespace) -> bool:
    out = Path(args.out_root) / f"theme{theme:02d}" / (res if args.speed == 1 else f"{res}_x{args.speed}")
    out.mkdir(parents=True, exist_ok=True)
    for stale in list(out.glob("*.png")) + list(out.glob("*.jpg")) + list(out.glob("*.gif")) + list(out.glob("*.mp4")):
        if args.moment == "all" or stale.name.startswith(PREFIXES[args.moment]):
            stale.unlink()
    context, film = display_env(res)
    command = [str(GODOT), "--path", str(ROOT), "--disable-vsync"]
    command += ["--resolution", "96x60"] if film else ["--resolution", res]
    moment = "scatter" if args.moment == "scatterkill" else args.moment
    command += [SCENE, "--", "--out", str(out), "--theme", str(theme), "--moments", "--moment", moment,
                "--speed", str(args.speed)]
    if args.moment == "scatterkill":
        command.append("--scatter-as-kill")
    # The harness always writes vfx-report.json: a single-moment run must not replace the
    # full run's report, so that one is set aside while it runs.
    report_path = out / "vfx-report.json"
    kept = out / "vfx-report.full.json"
    single = args.moment != "all"
    if single and report_path.exists():
        report_path.replace(kept)
    if film:
        command += ["--film", res]
    if args.next_theme >= 0:
        command += ["--next-theme", str(args.next_theme)]
    with context as env:
        result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=3600)
    log = result.stdout + "\n" + result.stderr
    # A single-moment run keeps its own log and report next to the full run's.
    tag = "" if args.moment == "all" else f"-{args.moment}"
    (out / f"render{tag}.log").write_text(log)
    verdict = "판정: 정상" in result.stdout
    flagged = [line for line in log.splitlines() if any(bad in line for bad in BAD)]
    errors = [line for line in flagged if not any(note in line for note in AT_EXIT)]
    summary = next((line for line in result.stdout.splitlines() if "건 · 실패" in line), "")
    print(f"theme {theme} {res} x{args.speed}: exit {result.returncode} verdict {verdict} errors {len(errors)}"
          f" ({'GPU film' if film else 'Xvfb window'})  {summary}")
    for line in [l for l in log.splitlines() if l.startswith("!! ")][:12] + errors[:12]:
        print("   ", line)
    if len(flagged) > len(errors):
        print("    note: the engine reported resources still in use at exit (after the verdict)")
    report = {}
    if report_path.exists():
        report = json.loads(report_path.read_text())
        if single:
            report_path.replace(out / f"vfx-report{tag}.json")
    if single and kept.exists():
        kept.replace(report_path)
    for seq in report.get("sequences", []):
        fine = seq["ticks_per_frame"] == 1
        assemble(out, seq, args.every or (4 if fine else 3), (230, 190))
    return result.returncode == 0 and verdict and not errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--res", action="append", help="WxH; repeatable (default 1280x800 and 1000x625)")
    parser.add_argument("--theme", action="append", type=int, help="battlefield index; repeatable (default 18 dark, 0 bright)")
    parser.add_argument("--next-theme", type=int, default=-1, help="battlefield that opens after the clear")
    parser.add_argument("--moment", default="all", choices=["all", "first", "revive", "clear", "stage", "scatter", "scatterkill", "final"],
                        help="scatterkill = the scatter crowd dying the ordinary way (the comparison)")
    parser.add_argument("--speed", type=int, default=1, choices=[1, 2, 3])
    parser.add_argument("--every", type=int, default=0, help="contact sheets keep every Nth frame")
    parser.add_argument("--out-root", default=str(ROOT / "build/vfx-stage"))
    args = parser.parse_args()
    ok = True
    for theme in args.theme or [18, 0]:
        for res in args.res or ["1280x800", "1000x625"]:
            ok = run(theme, res, args) and ok
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
