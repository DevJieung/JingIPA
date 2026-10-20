#!/usr/bin/env python3
"""Build every launcher-icon file from one painted master (F9, D4 2026-10-19) + review board.

    python3 tools/brand/icon_build.py --master M.png --fg FG.png [--crop x,y,size] [--fg-scale 1.0]

Writes (file names kept, so export_presets.cfg / project.godot need no change):
  art/ui/launcher_main.png        1024x1024 RGB, no alpha (desktop icon, iOS source, Android legacy)
  art/ui/launcher_adaptive.png    1024x1024 RGBA foreground; motif inside the 66 dp safe circle
                                  (1024 * 66/108 = 626 px), glow may reach the 72 dp viewport
  art/ui/launcher_background.svg  radial night gradient sampled from the master's background
  art/ui/launcher_windows.ico     16..256 px (Steam/Windows; not referenced until the preset sets it)
  build/feedback-2026-10-19/D4/icon/store_icon_512.png, ios_1024_rgb.png, review boards.
The monochrome layer (art/ui/launcher_monochrome.svg) is drawn by tools/brand/soul_mark.py.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
UI = ROOT / "art/ui"
OUT = ROOT / "build/feedback-2026-10-19/D4/icon"


def sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def radial_bg_svg(inner: tuple, outer: tuple, path: Path) -> None:
    def hx(c):
        return "#%02x%02x%02x" % tuple(int(v) for v in c[:3])
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="432" height="432" viewBox="0 0 432 432">'
           '<defs><radialGradient id="g" cx="0.5" cy="0.46" r="0.62">'
           '<stop offset="0" stop-color="%s"/><stop offset="1" stop-color="%s"/></radialGradient></defs>'
           '<rect width="432" height="432" fill="url(#g)"/></svg>\n' % (hx(inner), hx(outer)))
    path.write_text(svg)


def render_bg(inner, outer, size: int) -> Image.Image:
    y, x = np.mgrid[0:size, 0:size].astype(np.float32) / size
    d = np.sqrt((x - 0.5) ** 2 + (y - 0.46) ** 2) / 0.62
    d = np.clip(d, 0, 1)[..., None]
    c = np.array(inner, np.float32) * (1 - d) + np.array(outer, np.float32) * d
    return Image.fromarray(c.astype(np.uint8), "RGB")


# ---------------------------------------------------------------- masks (size px, 0..1 alpha)
def mask_circle(s):
    y, x = np.mgrid[0:s, 0:s] + 0.5
    r = np.sqrt((x - s / 2) ** 2 + (y - s / 2) ** 2)
    return np.clip(s / 2 - r + 0.5, 0, 1)


def mask_superellipse(s, n=5.0):
    y, x = (np.mgrid[0:s * 4, 0:s * 4] + 0.5) / (s * 4) * 2 - 1
    m = (np.abs(x) ** n + np.abs(y) ** n) <= 1.0
    return np.array(Image.fromarray((m * 255).astype(np.uint8)).resize((s, s), Image.LANCZOS)) / 255.0


def mask_round(s, rr=0.20):
    im = Image.new("L", (s * 4, s * 4), 0)
    ImageDraw.Draw(im).rounded_rectangle([0, 0, s * 4 - 1, s * 4 - 1], radius=int(s * 4 * rr), fill=255)
    return np.array(im.resize((s, s), Image.LANCZOS)) / 255.0


def mask_teardrop(s):
    im = Image.new("L", (s * 4, s * 4), 0)
    d = ImageDraw.Draw(im)
    S = s * 4
    d.ellipse([0, 0, S - 1, S - 1], fill=255)
    d.rectangle([S // 2, S // 2, S - 1, S - 1], fill=255)
    return np.array(im.resize((s, s), Image.LANCZOS)) / 255.0


def apply_mask(rgb: Image.Image, m: np.ndarray) -> Image.Image:
    a = Image.fromarray((m * 255).astype(np.uint8), "L")
    out = rgb.convert("RGBA")
    out.putalpha(a)
    return out


def adaptive_view(fg: Image.Image, bg: Image.Image, px: int) -> Image.Image:
    """What a launcher shows: the central 72/108 of (bg + fg), at px."""
    S = fg.size[0]
    comp = bg.resize((S, S), Image.LANCZOS).convert("RGBA")
    comp.alpha_composite(fg)
    c = S * (1 - 72 / 108) / 2
    view = comp.crop((round(c), round(c), round(S - c), round(S - c)))
    return view.resize((px, px), Image.LANCZOS).convert("RGB")


def extend_edges(im: Image.Image, size: int, inner: int) -> Image.Image:
    """`im` scaled to `inner` px, centred on a `size` canvas whose margin continues the picture's
    edge colours (clamped, then blurred) so a launcher's parallax never shows a hard edge."""
    small = im.resize((inner, inner), Image.LANCZOS)
    pad = (size - inner) // 2
    a = np.asarray(small)
    ext = np.pad(a, ((pad, size - inner - pad), (pad, size - inner - pad), (0, 0)), mode="edge")
    ext_im = Image.fromarray(ext).filter(ImageFilter.GaussianBlur(28))
    ext_im = Image.blend(ext_im, Image.new("RGB", ext_im.size, (8, 14, 32)), 0.35)
    ext_im.paste(small, (pad, pad))
    return ext_im


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--master", required=True, help="full-bleed square painting (motif within the central 92 %)")
    ap.add_argument("--zoom", type=float, default=1.0, help="<1 shrinks the painting inside launcher_main (adds edge)")
    ap.add_argument("--write", action="store_true", help="write art/ui files (else build/ only)")
    args = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    master = Image.open(args.master).convert("RGB")
    main_1024 = master.resize((1024, 1024), Image.LANCZOS)
    if args.zoom < 1.0:
        main_1024 = extend_edges(master, 1024, round(1024 * args.zoom))
    arr = np.asarray(main_1024).astype(np.float32)
    edge = np.concatenate([arr[:40].reshape(-1, 3), arr[:, :40].reshape(-1, 3), arr[:, -40:].reshape(-1, 3)])
    outer = tuple(np.percentile(edge, 35, axis=0))
    inner = tuple(np.clip(np.array(outer) * 1.55 + np.array([4, 10, 18]), 0, 255))
    # Adaptive foreground: the whole painting exactly fills the 72 dp viewport (1024*72/108 = 683 px);
    # the margin beyond it (only seen while a launcher moves the layer) continues its edges.
    view = round(1024 * 72 / 108)
    adaptive = extend_edges(master, 1024, view).convert("RGBA")
    bg = render_bg(inner, outer, 1024)
    stats = dict(bg_inner=[round(v) for v in inner], bg_outer=[round(v) for v in outer], viewport_px=view,
                 safe_circle_px=round(1024 * 66 / 108))
    dst_main = (UI if args.write else OUT) / "launcher_main.png"
    dst_adapt = (UI if args.write else OUT) / "launcher_adaptive.png"
    dst_bg = (UI if args.write else OUT) / "launcher_background.svg"
    dst_ico = (UI if args.write else OUT) / "launcher_windows.ico"
    main_1024.save(dst_main, optimize=True)                 # RGB: no alpha channel at all
    adaptive.save(dst_adapt, optimize=True)
    radial_bg_svg(inner, outer, dst_bg)
    main_1024.save(dst_ico, sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    main_1024.save(OUT / "ios_1024_rgb.png")
    main_1024.resize((512, 512), Image.LANCZOS).save(OUT / "store_icon_512.png")
    stats["files"] = {str(p.relative_to(ROOT)): sha(p) for p in (dst_main, dst_adapt, dst_bg, dst_ico)}
    stats["main_mode"] = Image.open(dst_main).mode
    (OUT / "icon_build.json").write_text(json.dumps(stats, indent=1))
    board(main_1024, adaptive, bg)
    print(json.dumps(stats, indent=1))


def board(main_1024: Image.Image, fg: Image.Image, bg: Image.Image) -> None:
    W = 1720
    sheet = Image.new("RGB", (W, 1480), "#141f27")
    d = ImageDraw.Draw(sheet)
    y = 20
    d.text((20, y), "STELLAR DEFENSE launcher icon review (D4 2026-10-19)  -  sizes are real pixels", fill=(240, 220, 160))
    y += 30
    d.text((20, y), "Legacy / iOS source (1024 RGB): iOS squircle at 180, 120, 87, 60, 48 px", fill=(200, 210, 220))
    x = 20
    y += 20
    for px in (180, 120, 87, 60, 48):
        im = apply_mask(main_1024.resize((px, px), Image.LANCZOS), mask_superellipse(px, 5.0))
        sheet.paste(im, (x, y), im)
        x += px + 30
    y += 200
    d.text((20, y), "Android adaptive (background + foreground, 72 dp viewport): circle / squircle / rounded / teardrop at 192, 144, 96, 72, 48 px", fill=(200, 210, 220))
    y += 22
    for mname, mf in (("circle", mask_circle), ("squircle", lambda s: mask_superellipse(s, 4.0)),
                      ("rounded", mask_round), ("teardrop", mask_teardrop)):
        x = 20
        for px in (192, 144, 96, 72, 48):
            im = apply_mask(adaptive_view(fg, bg, px), mf(px))
            sheet.paste(im, (x, y), im)
            x += px + 26
        d.text((x + 10, y + 80), mname, fill=(160, 170, 180))
        y += 206
    # Home screen mock on two wallpapers at 48 dp xxhdpi (144 px) and mdpi (48 px).
    for wi, wall in enumerate(((35, 52, 70), (226, 214, 196))):
        wx, wy = 1000, 70 + wi * 640
        wpx = Image.new("RGB", (700, 600), wall)
        sheet.paste(wpx, (wx, wy))
        others = [(220, 80, 70), (70, 140, 230), (250, 190, 60), (90, 180, 120), (150, 90, 200)]
        cells = [(0, 0), (1, 0), (2, 0), (0, 1), (1, 1), (2, 1)]
        for n, (cx, cy) in enumerate(cells):
            px = 144
            ox, oy = wx + 40 + cx * 220, wy + 40 + cy * 210
            if n == 4:
                im = apply_mask(adaptive_view(fg, bg, px), mask_circle(px))
            else:
                col = others[n % len(others)]
                im = apply_mask(Image.new("RGB", (px, px), col), mask_circle(px))
            sheet.paste(im, (ox, oy), im)
        # 48 px row (mdpi) bottom
        for n in range(6):
            ox, oy = wx + 40 + n * 100, wy + 480
            px = 48
            if n == 2:
                im = apply_mask(adaptive_view(fg, bg, px), mask_circle(px))
            else:
                im = apply_mask(Image.new("RGB", (px, px), others[n % len(others)]), mask_circle(px))
            sheet.paste(im, (ox, oy), im)
    sheet.save(OUT / "icon_review_board.png")


if __name__ == "__main__":
    main()
