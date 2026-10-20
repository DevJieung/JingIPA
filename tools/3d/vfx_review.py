#!/usr/bin/env python3
"""Capture the battle VFX layer in real GL at both mobile sizes and assemble review media.

    python3 tools/3d/vfx_review.py                       # 1280x800 and 1000x625, both squads
    python3 tools/3d/vfx_review.py --res 1280x800 --squad a --frames 24
    python3 tools/3d/vfx_review.py --skills-only --theme 20 --out-root build/blast-vfx/after/wood
    python3 tools/3d/vfx_review.py --display-base 220    # first Xvfb display number to try
    python3 tools/3d/vfx_review.py --hitfeel --theme 20 --out-root build/vfx-hitfeel/after/spring_grove
    python3 tools/3d/vfx_review.py --hitfeel --scene zone --gpu auto|xvfb|:1   # one staged scene

--gpu (default auto): the login session's X server renders on the NVIDIA GPU (:1) when it is
up; the game is then drawn into an off-screen viewport of the window size (--film) behind a
96x60 window, with vsync off. `xvfb` forces the software path.

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

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from godot_env import ROOT, GODOT, ensure_xvfb, xvfb  # noqa: E402

BATTLEFIELD = (0, 70, 992, 800)   # ArenaScreen.BATTLEFIELD at the 1280x800 design size


def zoom_box(size: tuple[int, int], focus: list | None = None) -> tuple[int, int, int, int]:
    """A battlefield-centre crop (half the field) scaled to the actual window, or the
    sequence's own focus rectangle (design pixels x, y, w, h) when the harness gave one."""
    sx = size[0] / 1280.0
    sy = size[1] / 800.0
    if focus:
        x, y, w, h = focus
        # Keep a 14:9-ish frame around the focus so the crops of a run line up.
        w = max(w, 300)
        h = max(h, 200)
        cx, cy = (x + focus[2] * 0.5) * sx, (y + focus[3] * 0.5) * sy
        w, h = w * sx, h * sy
        x0 = int(min(max(cx - w / 2, 0), size[0] - w))
        y0 = int(min(max(cy - h / 2, 0), size[1] - h))
        return (x0, y0, int(x0 + w), int(y0 + h))
    cx = (BATTLEFIELD[0] + BATTLEFIELD[2]) * 0.5 * sx
    cy = (BATTLEFIELD[1] + BATTLEFIELD[3]) * 0.5 * sy
    w = 560 * sx
    h = 360 * sy
    return (int(cx - w / 2), int(cy - h / 2), int(cx + w / 2), int(cy + h / 2))


def assemble(out: Path, prefix: str, duration_ms: int, focus: list | None = None) -> None:
    files = sorted(out.glob(f"{prefix}_[0-9][0-9].png"))
    if not files:
        return
    frames = [Image.open(path).convert("RGB") for path in files]
    frames[0].save(out / f"{prefix}.gif", save_all=True, append_images=frames[1:], duration=duration_ms, loop=0)
    box = zoom_box(frames[0].size, focus)
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


def is_marker(rgb: np.ndarray, seen: tuple[float, float, float]) -> np.ndarray:
    """The magenta clear colour of the marker pass as the harness measured it on screen."""
    close = np.ones(rgb.shape[:2], bool)
    for channel in range(3):
        close &= np.abs(rgb[..., channel].astype(np.float32) / 255.0 - seen[channel]) < 0.03
    return close


def body_sheets(out: Path, sequence: dict, marker_seen: tuple[float, float, float] = (1.0, 0.0, 1.0)) -> None:
    """Per-body strips of a death / boss sequence: one row per body, every frame a column,
    cropped to the body's screen rectangle at 3x nearest so single pixels stay honest."""
    prefix = sequence["prefix"]
    files = sorted(out.glob(f"{prefix}_[0-9][0-9].png"))
    if not files:
        return
    frames = [Image.open(path).convert("RGB") for path in files]
    rects = sequence["rects"]
    labels = sequence.get("labels", [])
    zoom = 3 if max(r[2] for r in rects) <= 220 else 2
    step = 1 if len(frames) <= 30 else 2
    picked = list(range(0, len(frames), step))
    width = sum(1 for _ in picked) * max(r[2] for r in rects) * zoom
    height = sum(r[3] for r in rects) * zoom
    sheet = Image.new("RGB", (width, height), (10, 20, 30))
    y = 0
    for row, (x0, y0, w, h) in enumerate(rects):
        for column, n in enumerate(picked):
            tile = frames[n].crop((x0, y0, x0 + w, y0 + h)).resize((w * zoom, h * zoom), Image.NEAREST)
            sheet.paste(tile, (column * max(r[2] for r in rects) * zoom, y))
        y += h * zoom
    sheet.save(out / f"{prefix}_bodies.png")
    # One GIF per body at 3x, every frame (33 ms ticks shown at 66 ms).
    for row, (x0, y0, w, h) in enumerate(rects):
        tiles = [im.crop((x0, y0, x0 + w, y0 + h)).resize((w * zoom, h * zoom), Image.NEAREST) for im in frames]
        name = labels[row] if row < len(labels) else str(row)
        tiles[0].save(out / f"{prefix}_{name}.gif", save_all=True, append_images=tiles[1:], duration=66, loop=0)
    if prefix.startswith("marker"):
        # Whole-battlefield scan: the marker colour must not appear anywhere while bodies die.
        box = (0, int(70 * frames[0].size[1] / 800.0), int(992 * frames[0].size[0] / 1280.0), frames[0].size[1])
        counts = [int(is_marker(np.asarray(im.crop(box)), marker_seen).sum()) for im in frames]
        worst = max(counts)
        print(f"    {prefix}: clear-colour pixels (whole battlefield) max {worst} at frame {counts.index(worst)}")
    if "alpha_holes" in sequence:
        holes = sequence["alpha_holes"]
        print(f"    {prefix}: viewport alpha<1 pixels under the bodies: total {sum(holes)}, worst {max(holes)}"
              f" at frame {holes.index(max(holes))}, frames with a leak anywhere {sequence.get('leaky_frames')}")


def probe_sheet(out: Path, probe: dict) -> None:
    """The frozen-body probe states side by side at 4x nearest, labelled with their statistics.
    One sheet per probed body: probe_states.png, or probe_states_<id>.png when the preview probed
    several (their files are probe_<id>_*.png)."""
    x0, y0, w, h = probe["rect"]
    zoom = 4
    rows = probe["rows"]
    prefix = probe.get("prefix", "probe")
    files = []
    for row in rows:
        state = row["state"]
        name = {"natural_q1.00": f"{prefix}_natural_q100"}.get(state)
        if name is None and state.startswith("game_q"):
            name = f"{prefix}_game_q%03d" % round(float(state[6:]) * 100)
        if name is None:
            name = f"{prefix}_" + state
        files.append((row, out / f"{name}.png"))
    files = [(row, path) for row, path in files if path.exists()]
    columns = 6
    lines = (len(files) + columns - 1) // columns
    from PIL import ImageDraw
    sheet = Image.new("RGB", (columns * w * zoom, lines * (h * zoom + 34)), (10, 20, 30))
    draw = ImageDraw.Draw(sheet)
    for n, (row, path) in enumerate(files):
        tile = Image.open(path).convert("RGB").crop((x0, y0, x0 + w, y0 + h)).resize((w * zoom, h * zoom), Image.NEAREST)
        px, py = (n % columns) * w * zoom, (n // columns) * (h * zoom + 34)
        sheet.paste(tile, (px, py + 34))
        draw.text((px + 4, py + 2), row["state"], fill=(255, 255, 255))
        draw.text((px + 4, py + 16), f"changed {row['changed']} marker {row['marker']} dark {row['dark']}", fill=(200, 220, 240))
    sheet.save(out / ("probe_states.png" if prefix == "probe" else f"probe_states_{probe.get('id', prefix)}.png"))
    for row in rows:
        print(f"    {prefix}", json.dumps(row, ensure_ascii=False))


def gpu_display(wanted: str, xvfb_display: int, res: str) -> dict:
    """The X display to render on. `auto` takes the login session's GPU server (:1, see
    docs/VFX_LIGHTING.md) when its NV-GLX extension answers, otherwise Xvfb; `xvfb` forces
    the software path; anything else is used as the display name."""
    import contextlib
    import os
    if wanted != "xvfb":
        display = ":1" if wanted == "auto" else wanted
        auth = Path(f"/run/user/{os.getuid()}/gdm/Xauthority")
        env = dict(os.environ, DISPLAY=display, STELLARDEFENSE_NO_SAVE="1")
        if auth.exists():
            env["XAUTHORITY"] = str(auth)
        probe = subprocess.run(["xdpyinfo", "-queryExtensions"], env=env, capture_output=True, text=True)
        if probe.returncode == 0 and "NV-GLX" in probe.stdout:
            print(f"{res}: rendering on {display} (GPU)")
            return {"gpu": True, "context": contextlib.nullcontext(env)}
        if wanted != "auto":
            raise SystemExit(f"display {display} is not a GPU X server")
    ensure_xvfb()
    return {"gpu": False, "context": xvfb(xvfb_display, res)}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--res", action="append", help="WxH; repeatable (default 1280x800 and 1000x625)")
    parser.add_argument("--squad", default="all", choices=["a", "b", "all"])
    parser.add_argument("--frames", type=int, default=36)
    parser.add_argument("--theme", type=int, default=0)
    parser.add_argument("--quick", action="store_true")
    parser.add_argument("--skills-only", action="store_true", help="guardian skills, the boss gate and events only")
    parser.add_argument("--gate-only", action="store_true", help="only the boss gate warning and arrival")
    parser.add_argument("--probe", action="store_true", help="also fire the blast on empty ground (no bodies)")
    parser.add_argument("--death-only", action="store_true", help="deaths at every tick, plain and marker passes")
    parser.add_argument("--dissolve-probe", action="store_true", help="one body frozen at fixed material states")
    parser.add_argument("--boss-melee", action="store_true", help="the 2x boss between two sword guardians")
    parser.add_argument("--probe-id", default="", help="monster id(s) for --dissolve-probe, comma list (default jelly_seer,ember_imp)")
    parser.add_argument("--no-body-fit", action="store_true", help="--boss-melee as it was before effects followed the body's scale")
    parser.add_argument("--hitfeel", action="store_true", help="staged hit-feel scenes: zones per element, blast, freeze, hits, kills, melee, flying hit, level-up, perf")
    parser.add_argument("--scene", default="all", help="--hitfeel: one scene (zone|blast|freeze|hit|kill|melee|fly|levelup|perf)")
    parser.add_argument("--gpu", default="auto", help="auto (GPU X display when present), xvfb, or an X display such as :1")
    parser.add_argument("--out-root", default=str(ROOT / "build/motion-overhaul/vfx"))
    parser.add_argument("--display-base", type=int, default=220)
    args = parser.parse_args()
    failed = False
    for index, res in enumerate(args.res or ["1280x800", "1000x625"]):
        out = Path(args.out_root) / res
        out.mkdir(parents=True, exist_ok=True)
        for stale in out.glob("*.png"):
            stale.unlink()
        display = gpu_display(args.gpu, args.display_base + index, res)
        command = [str(GODOT), "--path", str(ROOT), "--resolution", res, "res://tests/3d/vfx_visual_preview.tscn", "--",
                   "--out", str(out), "--squad", args.squad, "--frames", str(args.frames), "--theme", str(args.theme)]
        if display["gpu"]:
            # Off-screen picture at the window size behind a tiny window; no monitor, so no vsync.
            command[1:1] = ["--disable-vsync"]
            command += ["--film", res]
        if args.hitfeel:
            command += ["--hitfeel", "--scene", args.scene]
        if args.quick:
            command.append("--quick")
        if args.skills_only:
            command.append("--skills-only")
        if args.gate_only:
            command.append("--gate-only")
        if args.probe:
            command.append("--probe")
        for flag, on in (("--death-only", args.death_only), ("--dissolve-probe", args.dissolve_probe),
                         ("--boss-melee", args.boss_melee)):
            if on:
                command.append(flag)
        if args.probe_id:
            command += ["--probe-id", args.probe_id]
        if args.no_body_fit:
            command.append("--no-body-fit")
        if display["gpu"]:
            # One capture on the GPU display at a time (shared with every GPU review).
            lock = ROOT / "build/casual-overhaul/gpu.lock"
            lock.parent.mkdir(parents=True, exist_ok=True)
            command = ["flock", str(lock), *command]
        with display["context"] as env:
            result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=3600)
        log = result.stdout + "\n" + result.stderr
        (out / "render.log").write_text(log)
        verdict = "판정: 정상" in result.stdout
        # "resources still in use at exit" is Godot's exit-time bookkeeping (the kill scene
        # leaves the field's BGM stream referenced by the audio autoload); not a render error.
        errors = [line for line in log.splitlines() if ("ERROR:" in line or "SCRIPT ERROR" in line)
                  and "still in use at exit" not in line]
        print(res, "exit", result.returncode, "verdict", verdict, "errors", len(errors))
        for line in errors[:10]:
            print("   ", line)
        report_path = out / "vfx-report.json"
        if report_path.exists():
            report = json.loads(report_path.read_text())
            # Single-tick sequences play at half speed (66 ms per 33 ms tick) so impacts can be read.
            for sequence in report.get("sequences", []):
                assemble(out, sequence["prefix"], int(1000 * sequence["tick"] * sequence["ticks_per_frame"]) if sequence["ticks_per_frame"] > 1 else 66,
                         sequence.get("focus"))
                if sequence.get("rects"):
                    body_sheets(out, sequence, tuple(report.get("marker_seen", (1.0, 0.0, 1.0))))
            for probe in report.get("probes") or ([report["probe"]] if report.get("probe") else []):
                probe_sheet(out, probe)
            if report.get("events"):
                print("   ", json.dumps(report["events"], ensure_ascii=False))
            if report.get("hitfeel"):
                print("    hitfeel", json.dumps(report["hitfeel"], ensure_ascii=False))
        if result.returncode or not verdict or errors:
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
