#!/usr/bin/env python3
"""Finish the chosen key-art painting for the loading cover (F8, D4 2026-10-19).

    python3 tools/brand/keyart.py build/feedback-2026-10-19/D4/gen/<chosen>.png [--write]

  - scales to 2688x1152 (21:9; Lanczos, light unsharp) — covers a 2400x1080 phone ~1:1
  - finds the Soul Stone (brightest cyan blob) and prints its UV for the cover's glow
  - writes a crop/safe-area board: what 16:10, 16:9, 20:9 and 4:3 screens show, with the
    wordmark band and the bar band of game/startup_loading.gd marked
  - --write: art/ui/stellar_keyart.png (+ lossy-WebP, mipmapped .import if missing)
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build/feedback-2026-10-19/D4/keyart"
DST = ROOT / "art/ui/stellar_keyart.png"
SIZE = (2688, 1152)
IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=1
compress/high_quality=false
compress/lossy_quality=0.9
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
"""


def stone_uv(im: Image.Image) -> tuple[float, float]:
    a = np.asarray(im).astype(np.float32) / 255.0
    h, w, _ = a.shape
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    cyan = np.clip(np.minimum(g, b) - r, 0, 1) * (g + b) * 0.5
    ys, xs = np.mgrid[0:h, 0:w]
    centre = (np.abs(xs - w / 2) < w * 0.18) & (ys < h * 0.75)
    wgt = np.where(centre, cyan, 0) ** 3
    return float((xs * wgt).sum() / wgt.sum() / w), float((ys * wgt).sum() / wgt.sum() / h)


def board(im: Image.Image, uv: tuple[float, float]) -> Path:
    """Logical canvases (EXPAND from 1280x800): what each screen shape shows of the cover-fit art."""
    shapes = {"16:10 1280x800": (1280, 800), "16:9 1422x800": (1422, 800), "20:9 1778x800": (1778, 800),
              "4:3 1280x960": (1280, 960)}
    tiles = []
    for name, (lw, lh) in shapes.items():
        k = max(lw / im.width, lh / im.height)
        dw, dh = im.width * k, im.height * k
        ox, oy = (lw - dw) * 0.5, (lh - dh) * 0.55
        canvas = Image.new("RGB", (lw, lh))
        canvas.paste(im.resize((round(dw), round(dh)), Image.LANCZOS), (round(ox), round(oy)))
        d = ImageDraw.Draw(canvas, "RGBA")
        # wordmark band and bar band (game/startup_loading.gd: lockup 34..224, bar at h-66)
        d.rectangle([lw / 2 - 360, 34, lw / 2 + 360, 224], outline=(255, 210, 90, 255), width=3)
        d.rectangle([lw / 2 - 310, lh - 92, lw / 2 + 310, lh - 50], outline=(90, 230, 255, 255), width=3)
        sx, sy = ox + uv[0] * dw, oy + uv[1] * dh
        d.ellipse([sx - 10, sy - 10, sx + 10, sy + 10], outline=(255, 80, 80, 255), width=3)
        d.text((12, lh - 30), name, fill=(255, 255, 255, 255))
        tiles.append(canvas.resize((round(lw * 0.5), round(lh * 0.5)), Image.LANCZOS))
    W = sum(t.width for t in tiles[:2]) + 30
    H = max(t.height for t in tiles[:2]) + max(t.height for t in tiles[2:]) + 30
    sheet = Image.new("RGB", (max(W, tiles[2].width + tiles[3].width + 30), H), (12, 18, 24))
    sheet.paste(tiles[0], (10, 10))
    sheet.paste(tiles[1], (20 + tiles[0].width, 10))
    sheet.paste(tiles[2], (10, 20 + tiles[0].height))
    sheet.paste(tiles[3], (20 + tiles[2].width, 20 + tiles[0].height))
    path = OUT / "keyart_safe_areas.png"
    sheet.save(path)
    return path


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    src = Image.open(args.src).convert("RGB")
    im = src.resize(SIZE, Image.LANCZOS) if src.size != SIZE else src
    if src.size != SIZE:
        im = im.filter(ImageFilter.UnsharpMask(radius=1.4, percent=35, threshold=2))
    uv = stone_uv(im)
    master = OUT / "keyart_master.png"
    im.save(master)
    info = {"source": str(Path(args.src).resolve().relative_to(ROOT)), "size": list(SIZE),
            "stone_uv": [round(uv[0], 4), round(uv[1], 4)], "board": str(board(im, uv).relative_to(ROOT))}
    if args.write:
        im.save(DST, optimize=True)
        imp = DST.with_suffix(".png.import")
        if not imp.exists():
            imp.write_text(IMPORT)
        info["written"] = str(DST.relative_to(ROOT))
        info["sha256"] = hashlib.sha256(DST.read_bytes()).hexdigest()
    print(json.dumps(info, indent=1))


if __name__ == "__main__":
    main()
