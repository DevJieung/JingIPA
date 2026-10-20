#!/usr/bin/env python3
"""Build the jewel-box sprites (F10/F11) into art/ui/box/.

    python3 tools/box/build_box_art.py              # render all five tiers and install
    python3 tools/box/build_box_art.py --preview    # closed boxes only, contact sheet
    python3 tools/box/build_box_art.py --keep-src   # keep the raw renders in build/box-art/src

Steps: Blender renders the layers (tools/box/box_art.py), then this script
  1. scales every layer by --scale (default 0.8: a 1024 render -> about 370 px box),
  2. builds seam.png, the light that leaks through the seam, from full_lit - full_dark
     (a sharp core plus a wide bloom, stored unpremultiplied so it can be drawn additive),
  3. crops each layer to its own alpha bounds and records the offset,
  4. writes art/ui/box/box_layout.gd (the table the game reads: anchors, offsets, sizes)
     and art/ui/box/manifest.json (provenance), plus .import files (mipmaps on, lossy 0.9).

Why a .gd table and not JSON: export_presets.cfg only ships *.json from core/locales and
a few anim folders, so a JSON layout here would be missing from the APK.
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "art/ui/box"
SRC = ROOT / "build/box-art/src"
ANGLES = [0, 6, 18, 40, 70, 100, 118]

IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://{path}"

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


def run_blender(tiers: str, res: int, samples: int, preview: bool) -> None:
    if SRC.exists():
        shutil.rmtree(SRC)
    SRC.mkdir(parents=True)
    cmd = ["blender", "-b", "--factory-startup", "-P", str(ROOT / "tools/box/box_art.py"), "--",
           "--out", str(SRC), "--tiers", tiers, "--res", str(res), "--samples", str(samples)]
    if preview:
        cmd.append("--preview")
    t0 = time.time()
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0 or "Traceback" in p.stdout + p.stderr:
        sys.stdout.write(p.stdout[-4000:])
        sys.stderr.write(p.stderr[-4000:])
        raise SystemExit("Blender failed")
    print(f"blender: {time.time() - t0:.1f}s")


def load(path: Path, scale: float) -> Image.Image:
    im = Image.open(path).convert("RGBA")
    if scale != 1.0:
        im = im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS)
    return im


def seam_glow(lit: Image.Image, dark: Image.Image) -> Image.Image:
    a = np.asarray(lit).astype(np.float32)
    b = np.asarray(dark).astype(np.float32)
    diff = np.clip(a[..., :3] - b[..., :3], 0, 255)
    base = Image.fromarray(diff.astype(np.uint8))
    core = np.asarray(base.filter(ImageFilter.GaussianBlur(1.2))).astype(np.float32) * 2.2
    bloom = np.asarray(base.filter(ImageFilter.GaussianBlur(9))).astype(np.float32) * 7.0
    wide = np.asarray(base.filter(ImageFilter.GaussianBlur(22))).astype(np.float32) * 6.0
    rgb = np.clip(core + bloom + wide, 0, 255)
    alpha = rgb.max(axis=2)
    safe = np.maximum(alpha, 1.0)[..., None]
    straight = np.clip(rgb / safe * 255.0, 0, 255)
    out = np.dstack([straight, alpha]).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def crop(im: Image.Image, pad: int = 3):
    alpha = np.asarray(im)[..., 3]
    ys, xs = np.nonzero(alpha > 1)
    if len(xs) == 0:
        return im.crop((0, 0, 1, 1)), (0, 0)
    x0, x1 = max(0, xs.min() - pad), min(im.width, xs.max() + 1 + pad)
    y0, y1 = max(0, ys.min() - pad), min(im.height, ys.max() + 1 + pad)
    return im.crop((x0, y0, x1, y1)), (int(x0), int(y0))


def gd_value(v) -> str:
    if isinstance(v, dict):
        return "{" + ", ".join(f'"{k}": {gd_value(x)}' for k, x in v.items()) + "}"
    if isinstance(v, (list, tuple)):
        if len(v) == 2 and all(isinstance(x, (int, float)) for x in v):
            return f"Vector2({v[0]:g}, {v[1]:g})"
        return "[" + ", ".join(gd_value(x) for x in v) + "]"
    if isinstance(v, str):
        return f'"{v}"'
    if isinstance(v, float):
        return f"{v:.4f}"
    return str(v)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--tiers", default="1,2,3,4,5")
    ap.add_argument("--res", type=int, default=1024)
    ap.add_argument("--samples", type=int, default=64)
    ap.add_argument("--scale", type=float, default=0.8)
    ap.add_argument("--preview", action="store_true")
    ap.add_argument("--keep-src", action="store_true")
    ap.add_argument("--skip-render", action="store_true", help="reuse build/box-art/src")
    args = ap.parse_args()
    if not args.skip_render:
        run_blender(args.tiers, args.res, args.samples, args.preview)
    render = json.loads((SRC / "render.json").read_text())
    if args.preview:
        tiles = [load(SRC / f"tier{t}/closed.png", args.scale) for t in sorted(map(int, render["tiers"]))]
        sheet = Image.new("RGBA", (sum(t.width for t in tiles), tiles[0].height), (12, 22, 33, 255))
        x = 0
        for t in tiles:
            sheet.alpha_composite(t, (x, 0))
            x += t.width
        dest = ROOT / "build/box-art/preview.png"
        sheet.save(dest)
        print(dest)
        return 0
    OUT.mkdir(parents=True, exist_ok=True)
    layout: dict = {}
    manifest = {
        "generator": "Blender 4.0.2 EEVEE, procedural models (tools/box/box_art.py), post: tools/box/build_box_art.py",
        "why_not_image_gen": "2026-10-19: another project held 11.3 GB of the GPU; task rules say use a 3D render or code drawing instead",
        "render_res": args.res, "scale": args.scale, "samples": args.samples, "angles": ANGLES, "tiers": {},
    }
    s = args.scale
    for tier_s, info in sorted(render["tiers"].items(), key=lambda kv: int(kv[0])):
        tier = int(tier_s)
        src = SRC / f"tier{tier}"
        dst = OUT / f"tier{tier}"
        dst.mkdir(parents=True, exist_ok=True)
        layers = {"body": load(src / "body.png", s), "closed": load(src / "closed.png", s)}
        for a in ANGLES:
            layers[f"lid_{a:03d}"] = load(src / f"lid_{a:03d}.png", s)
        layers["seam"] = seam_glow(load(src / "full_lit.png", s), load(src / "full_dark.png", s))
        entry = {
            "anchor": [round(info["anchor"][0] * s, 1), round(info["anchor"][1] * s, 1)],
            "mouth": [round(info["mouth"][0] * s, 1), round(info["mouth"][1] * s, 1)],
            "top": [round(info["top"][0] * s, 1), round(info["top"][1] * s, 1)],
            "layers": {},
        }
        for name, im in layers.items():
            cropped, off = crop(im)
            rel = f"tier{tier}/{name}.png"
            cropped.save(OUT / rel, optimize=True)
            (OUT / (rel + ".import")).write_text(IMPORT.format(path=f"art/ui/box/{rel}"))
            entry["layers"][name] = {"offset": list(off), "size": [cropped.width, cropped.height]}
        # The body's own bounds: the width the screen fits the box into.
        b = entry["layers"]["closed"]
        entry["bounds"] = [b["offset"][0], b["offset"][1], b["size"][0], b["size"][1]]
        layout[tier] = entry
        manifest["tiers"][str(tier)] = {"files": sorted(f"art/ui/box/tier{tier}/{n}.png" for n in layers),
                                        "light": info.get("light")}
        print(f"tier {tier}: closed {b['size']} anchor {entry['anchor']}")
    lines = [
        "## Generated by tools/box/build_box_art.py — do not edit by hand.",
        "## Per tier: where each layer sits on the shared render canvas (px), the box's",
        "## base centre (`anchor`), the middle of its open mouth (`mouth`), its top (`top`)",
        "## and the closed box's bounds. Lid layers are keyed by hinge angle in degrees.",
        "extends RefCounted",
        "",
        f"const ANGLES := {gd_value(ANGLES)}",
        "const TIERS := {",
    ]
    for tier, entry in layout.items():
        lines.append(f"\t{tier}: {{")
        for key in ("anchor", "mouth", "top", "bounds"):
            val = entry[key]
            if key == "bounds":
                lines.append(f"\t\t\"bounds\": Rect2({val[0]}, {val[1]}, {val[2]}, {val[3]}),")
            else:
                lines.append(f"\t\t\"{key}\": {gd_value(val)},")
        lines.append("\t\t\"layers\": {")
        for name, lay in entry["layers"].items():
            lines.append(f"\t\t\t\"{name}\": Rect2({lay['offset'][0]}, {lay['offset'][1]}, {lay['size'][0]}, {lay['size'][1]}),")
        lines.append("\t\t},")
        lines.append("\t},")
    lines.append("}")
    (OUT / "box_layout.gd").write_text("\n".join(lines) + "\n")
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=1, ensure_ascii=False) + "\n")
    if not args.keep_src:
        pass  # sources stay in build/ (ignored by git) for contact sheets; nothing to clean
    print(f"wrote {OUT}/box_layout.gd")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
