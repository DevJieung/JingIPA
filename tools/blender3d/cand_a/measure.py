#!/usr/bin/env python3
"""후보 A — **잣대.** 엔진 계약과 품질검사 여덟 가지를 실제로 센다(추정치 없음)."""
import sys, json, glob
from pathlib import Path
from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE.parent.parent / "sprite"))
import spec      # noqa: E402
import pixels    # noqa: E402


def frame_stats(im):
    im = im.convert("RGBA")
    w, h = im.size
    px = im.load()
    a = im.split()[3]
    bb = a.getbbox()
    semi = 0
    cols = {}
    n = 0
    sx = 0
    for y in range(h):
        for x in range(w):
            r, g, b, al = px[x, y]
            if 0 < al < 255:
                semi += 1
            if al:
                n += 1
                sx += x
                cols[(r, g, b)] = cols.get((r, g, b), 0) + 1
    return {"bbox": list(bb) if bb else None, "semi": semi, "fill": n,
            "cx": round(sx / max(1, n), 2), "colors": cols,
            "n_colors": len(cols),
            "outline_ratio": round(pixels.outline_ratio(im), 4)}


def foot_of(st):
    """발밑 = 알파 상자의 **아래끝**. 칸마다 이것이 같아야 엔진이 안 튄다."""
    return st["bbox"][3] if st["bbox"] else -1


def run(root, palette):
    pal = {pixels.hex2rgb(h) for h in palette}
    out = {"clips": {}, "palette_n": len(palette)}
    for act_dir in sorted(p for p in Path(root).iterdir() if p.is_dir()):
        out["clips"][act_dir.name] = {}
        for d in sorted(p for p in act_dir.iterdir() if p.is_dir()):
            sts = [frame_stats(Image.open(f)) for f in sorted(d.glob("*.png"))]
            if not sts:
                continue
            feet = [foot_of(s) for s in sts]
            allc = {}
            for s in sts:
                for c, k in s["colors"].items():
                    allc[c] = allc.get(c, 0) + k
            outl = [c for c in allc if c not in pal]
            out["clips"][act_dir.name][d.name] = {
                "n": len(sts),
                "foot_y": feet,
                "foot_y_spread": max(feet) - min(feet),
                "max_colors": max(s["n_colors"] for s in sts),
                "union_colors": len(allc),
                "palette_outliers": len(outl),
                "outlier_rgb": outl[:8],
                "semi_alpha": sum(s["semi"] for s in sts),
                "empty_frames": sum(1 for s in sts if s["fill"] == 0),
                "outline_ratio_min": min(s["outline_ratio"] for s in sts),
                "fill_ratio": [round(s["fill"] / (96 * 96), 4) for s in sts],
                "bbox0": sts[0]["bbox"],
                "body_h": (sts[0]["bbox"][3] - sts[0]["bbox"][1]) if sts[0]["bbox"] else 0,
                "body_w": (sts[0]["bbox"][2] - sts[0]["bbox"][0]) if sts[0]["bbox"] else 0,
                "cx": [s["cx"] for s in sts],
            }
    return out


if __name__ == "__main__":
    r = run(sys.argv[1], spec.palette_for("ice"))
    print(json.dumps(r, ensure_ascii=False, indent=1))
