#!/usr/bin/env python3
"""Capture the real cold start (MindMorph logo -> loading cover -> title) and review it.

    python3 tools/startup_splash_review.py [--display auto|gpu|xvfb] [--res 1280x800 ...]

For each resolution it runs tests/startup_splash_preview.tscn on a real display, then checks:
  - the logo fades in to full and back out, and every pixel outside the logo is the boot green
    (#235D48) on every logo frame (no stray pixel, no edge seam on wide phones);
  - the loading cover follows; its progress and bar never go back and reach 1.0; Main does not
    take input under it (the preview's own failures);
  - the cover ends on black before it lifts, and the revealed title is not blank;
  - the window aspect comes back.
Writes per resolution playback.gif, sequence.png and frames.json, and build/startup-splash/report.json.
--display auto uses the NVIDIA X session (:1, serialised by build/casual-overhaul/gpu.lock)
when it exists, otherwise a private Xvfb (software GL: slow but works anywhere).
"""
from __future__ import annotations

import argparse
import contextlib
import fcntl
import json
import os
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from godot_env import ROOT, GODOT, xvfb

GREEN = np.array([35, 93, 72], dtype=np.uint8)
RESOLUTIONS = ["1280x800", "1000x625", "1280x720", "1600x720"]


def gpu_env() -> dict[str, str] | None:
    auth = Path(f"/run/user/{os.getuid()}/gdm/Xauthority")
    if not auth.exists():
        return None
    env = dict(os.environ, DISPLAY=":1", XAUTHORITY=str(auth), STELLARDEFENSE_NO_SAVE="1")
    probe = subprocess.run(["xdpyinfo", "-queryExtensions"], env=env, capture_output=True, text=True)
    return env if probe.returncode == 0 and "NV-GLX" in probe.stdout else None


@contextlib.contextmanager
def display(kind: str):
    env = gpu_env() if kind in ("auto", "gpu") else None
    if kind == "gpu" and env is None:
        raise SystemExit("The NVIDIA X session (:1) is not available")
    if env is not None:
        lock_path = ROOT / "build/casual-overhaul/gpu.lock"
        lock_path.parent.mkdir(parents=True, exist_ok=True)
        with open(lock_path, "w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            yield env, ["--disable-vsync"]
        return
    with xvfb(102, "1920x1080") as env:
        yield env, []


def full_screen(item: dict) -> bool:
    """Logo and cover frames fill the device (EXPAND); from the lift on, the game's aspect is back."""
    return item["stage"] == "logo" or (item["stage"] == "loading" and item.get("phase") not in ("lift", "done"))


def letterbox(im: Image.Image, w: int, h: int) -> Image.Image:
    """What the device shows: a KEEP-aspect frame centred between black bars."""
    if im.size == (w, h):
        return im
    canvas = Image.new("RGB", (w, h), "black")
    canvas.paste(im, ((w - im.size[0]) // 2, (h - im.size[1]) // 2))
    return canvas


def review(folder: Path, res: str) -> dict:
    records = json.loads((folder / "frames.json").read_text())
    assert not records["failures"], records["failures"]
    frames = records["frames"]
    w, h = map(int, res.split("x"))
    logo = [item for item in frames if item["stage"] == "logo"]
    cover = [item for item in frames if item["stage"] == "loading"]
    title = [item for item in frames if item["stage"] == "title"]
    assert logo and cover and title, "logo, loading and title stages must all appear"
    alphas = [item["alpha"] for item in logo]
    assert min(alphas[:2]) < 0.01 and max(alphas) == 1.0 and alphas[-1] < 0.01, alphas
    peak = alphas.index(max(alphas))
    assert all(a <= b + 1e-6 for a, b in zip(alphas[:peak], alphas[1:peak + 1])), "logo fade-in goes back"
    assert all(a + 1e-6 >= b for a, b in zip(alphas[peak:], alphas[peak + 1:])), "logo fade-out goes back"
    progress = [item["progress"] for item in cover]
    shown = [item["shown"] for item in cover]
    assert all(a <= b + 1e-6 for a, b in zip(progress, progress[1:])), "progress goes back"
    assert all(a <= b + 1e-6 for a, b in zip(shown, shown[1:])), "bar goes back"
    assert max(progress) == 1.0 and max(shown) == 1.0, (max(progress), max(shown))
    checked = 0
    dipped = False
    shots = [item for item in frames if "file" in item]
    previews = []
    for item in shots:
        im = Image.open(folder / item["file"]).convert("RGB")
        pixels = np.asarray(im)
        if full_screen(item):
            assert im.size == (w, h), (res, item["frame"], im.size)
        else:
            # The game's own aspect again (16:10, letterboxed by black bars on other shapes).
            iw, ih = im.size
            assert iw <= w and ih <= h and abs(iw / ih - 1.6) < 0.01, (res, item["frame"], im.size)
        if item["stage"] == "logo":
            x, y, lw, lh = item["logo_rect"]
            vw, vh = item["viewport_size"]
            left, top = int(x * w / vw), int(y * h / vh)
            right, bottom = int((x + lw) * w / vw + 1), int((y + lh) * h / vh + 1)
            mask = np.ones((h, w), dtype=bool)
            mask[top:bottom, left:right] = False
            assert np.all(pixels[mask] == GREEN), f"Nonmatching logo margin: {res}/{item['file']}"
            if item["alpha"] == 0.0:
                assert np.all(pixels == GREEN), f"Logo fade-out leaves a pixel: {res}/{item['file']}"
            checked += int(mask.sum())
        elif item["stage"] == "loading" and item.get("phase") == "lift" and item["veil"] >= 0.999:
            assert pixels.max() <= 2, f"The cover does not reach black before it lifts: {res}/{item['file']}"
            dipped = True
        previews.append((item, letterbox(im, w, h).resize((480, round(h * 480 / w)), Image.Resampling.LANCZOS)))
    assert dipped, f"No frame caught the black dip between the cover and the title: {res}"
    final = np.asarray(Image.open(folder / "title.png").convert("RGB")).astype(int)
    assert final.std() > 12.0, f"The revealed title looks blank: {res}"
    # Playback and a contact sheet of the moments that matter.
    images = [p for _, p in previews]
    images[0].save(folder / "playback.gif", save_all=True, append_images=images[1:], duration=33, loop=0)
    picks: list[int] = []
    logo_shots = [i for i, (item, _) in enumerate(previews) if item["stage"] == "logo"]
    cover_shots = [i for i, (item, _) in enumerate(previews) if item["stage"] == "loading"]
    if logo_shots:
        peak_shot = max(logo_shots, key=lambda i: previews[i][0]["alpha"])
        picks += [logo_shots[0], peak_shot, logo_shots[-1]]
    if cover_shots:
        picks += [cover_shots[0], cover_shots[len(cover_shots) // 2], cover_shots[-1]]
    picks += [len(previews) - 1]
    picks = list(dict.fromkeys(picks))
    cw, ch = images[0].size
    cols = 4
    rows = (len(picks) + cols - 1) // cols
    sheet = Image.new("RGB", (cw * cols, (ch + 26) * rows), "#15221d")
    draw = ImageDraw.Draw(sheet)
    for n, index in enumerate(picks):
        item, image = previews[index]
        px, py = (n % cols) * cw, (n // cols) * (ch + 26)
        sheet.paste(image, (px, py))
        label = f"#{item['frame']} {item['stage']}"
        if item["stage"] == "logo":
            label += f" alpha {item['alpha']:.2f}"
        elif item["stage"] == "loading":
            label += f" {item['phase']} {item['shown'] * 100:.0f}%"
        draw.text((px + 10, py + ch + 5), label, fill="white")
    sheet.save(folder / "sequence.png")
    return {"frames": len(frames), "logo_frames": len(logo), "loading_frames": len(cover),
            "title_frame": title[0]["frame"], "exact_logo_margin_pixels": checked,
            "background": "#235d48", "title_reached": True, "aspect_restored": True}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--display", choices=["auto", "gpu", "xvfb"], default="auto")
    parser.add_argument("--res", nargs="*", default=RESOLUTIONS)
    parser.add_argument("--out", default=str(ROOT / "build/startup-splash"))
    args = parser.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    reports = {}
    with display(args.display) as (env, extra):
        for res in args.res:
            folder = out / res
            folder.mkdir(parents=True, exist_ok=True)
            for old in folder.glob("*.png"):
                old.unlink()
            result = subprocess.run(
                [str(GODOT), "--path", str(ROOT), "--resolution", res, "--fixed-fps", "60", *extra,
                 "res://tests/startup_splash_preview.tscn", "--", "--out", str(folder)],
                env=env, text=True, capture_output=True, timeout=600,
            )
            log = result.stdout + result.stderr
            (out / f"{res}.log").write_text(log)
            print(res, log[-1500:], flush=True)
            if result.returncode or "SCRIPT ERROR:" in log:
                raise SystemExit(result.returncode or 1)
            reports[res] = review(folder, res)
    reports["logo"] = "art/ui/mindmorph_logo.png"
    (out / "report.json").write_text(json.dumps(reports, indent=2) + "\n")
    print(json.dumps(reports, indent=2))


if __name__ == "__main__":
    main()
