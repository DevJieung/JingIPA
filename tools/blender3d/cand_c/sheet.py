#!/usr/bin/env python3
"""후보 C — 6단계(양자화·테두리) + 시트 + 대조표 + 잣대.

    python3 tools/blender3d/cand_c/sheet.py --variant flat

★★ 후처리는 **한 줄도 새로 안 짰다.** `tools/blender3d/post.clean_one()` 을 그대로
   부르고, 그것은 공식 파이프라인의 `tools/sprite/pixels.py`(quantize · add_outline ·
   binarize_alpha)를 그대로 부른다. 세 후보의 차이가 「후처리 코드가 달라서」가 아니라
   **원본 프레임의 차이**로만 남아야 하기 때문이다.

★ 이 파일이 재는 것은 계약서(7단계에서 걸리는 것) 그대로다 —
  고유색 <=20 · 팔레트 이탈 0 · 반투명 0 · 발높이 흔들림 <=2px · 빈 칸 없음 ·
  검은 테두리 비율 >=0.60 · 루프 이음매 · 두 클립의 크롭 상자가 같은가.
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))                       # tools/blender3d
sys.path.insert(0, str(HERE.parent.parent / "sprite"))     # tools/sprite (읽기만)
import spec    # noqa: E402
import post    # noqa: E402
import pixels  # noqa: E402

OUT = spec.OUT / "cand_c"
UNIT = "jokull"
ELEM = "ice"


def alpha_bbox(im: Image.Image):
    a = np.array(im)[:, :, 3]
    ys, xs = np.where(a > 0)
    if len(xs) == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def measure(im: Image.Image, palette_rgb: set) -> dict:
    a = np.array(im)
    al = a[:, :, 3]
    op = al > 0
    bb = alpha_bbox(im)
    cols = {tuple(int(v) for v in c) for c in a[op][:, :3]}
    return {
        "bbox": list(bb) if bb else None,
        "fill": int(op.sum()),
        "colors": len(cols),
        "outliers": len(cols - palette_rgb),
        "semi_alpha": int(((al > 0) & (al < 255)).sum()),
        "magenta": int((op & (a[:, :, 0] > 200) & (a[:, :, 1] < 60)
                        & (a[:, :, 2] > 200)).sum()),
        "outline_ratio": round(pixels.outline_ratio(im), 4),
    }


def raw_colors(p: Path) -> dict:
    """양자화 **전** 원본 렌더가 몇 색이고 팔레트에서 얼마나 벗어나 있나."""
    a = np.array(Image.open(p).convert("RGBA"))
    op = a[:, :, 3] > 0
    px = a[op][:, :3].astype(np.int32)
    pal = np.array([spec.hex2rgb(h) for h in spec.palette_for(ELEM)], np.int32)
    d = np.sqrt(((px[:, None, :] - pal[None, :, :]) ** 2).sum(2))
    near = d.min(1)
    return {"n": int(op.sum()),
            "colors": int(len({tuple(v) for v in px})),
            "dist_mean": round(float(near.mean()), 2),
            "dist_p95": round(float(np.percentile(near, 95)), 2),
            "dist_max": round(float(near.max()), 2)}


def run(variant: str, tag: str = "") -> dict:
    src = OUT / ("5_frames" + tag)
    dst = OUT / ("6_clean" + tag + ("" if variant == "flat" else "_" + variant))
    if variant != "flat":
        src = OUT / ("5_frames" + tag + "_" + variant)
    pal_hex = spec.palette_for(ELEM)
    pal_rgb = {spec.hex2rgb(h) for h in pal_hex}
    rep = {"variant": variant, "palette": len(pal_hex), "clips": {}, "raw": {}}

    for act in sorted(d.name for d in src.iterdir() if d.is_dir()):
        for dn in sorted(d.name for d in (src / act).iterdir() if d.is_dir()):
            outd = dst / act / dn
            outd.mkdir(parents=True, exist_ok=True)
            ms = []
            for f in sorted((src / act / dn).glob("*.png")):
                im = post.clean_one(f, pal_hex, outline=True)   # ★ 공식 후처리 그대로
                im.save(outd / f.name)
                ms.append(measure(im, pal_rgb))
            bots = [m["bbox"][3] for m in ms if m["bbox"]]
            rep["clips"][f"{act}/{dn}"] = {
                "n": len(ms),
                "foot_y_spread": max(bots) - min(bots) if bots else -1,
                "colors_max": max(m["colors"] for m in ms),
                "outliers": sum(m["outliers"] for m in ms),
                "semi_alpha": sum(m["semi_alpha"] for m in ms),
                "magenta": sum(m["magenta"] for m in ms),
                "outline_min": min(m["outline_ratio"] for m in ms),
                "empty": sum(1 for m in ms if m["fill"] == 0),
                "frames": ms,
            }
    # 양자화 전 원본이 팔레트에서 얼마나 벗어나 있었나 (tex 갈래의 손실을 잰다)
    for f in sorted((src / "idle" / spec.GAME_DIR).glob("*.png")):
        rep["raw"][f.stem] = raw_colors(f)

    # --- 시트 (가로 1행 · 간격 0)
    sheets = {}
    for act in ("idle", "attack"):
        d = dst / act / spec.GAME_DIR
        frames = [Image.open(p).convert("RGBA") for p in sorted(d.glob("*.png"))]
        sh = pixels.pack_sheet(frames, spec.CELL[0])
        name = f"{UNIT}_{act}.png" if variant == "flat" else f"{UNIT}_{act}_{variant}.png"
        sh.save(OUT / name)
        sheets[act] = {"file": str(OUT / name), "size": list(sh.size),
                       "frames": len(frames),
                       "width_mod_frames": sh.width % max(1, len(frames))}

    # --- 계약서 숫자 (기준점 · 배율 · 총구)
    e_idle = sorted((dst / "idle" / spec.GAME_DIR).glob("*.png"))
    e_atk = sorted((dst / "attack" / spec.GAME_DIR).glob("*.png"))
    i0 = Image.open(e_idle[0]).convert("RGBA")
    bb = alpha_bbox(i0)
    a0 = np.array(i0)[:, :, 3]
    foot_rows = np.where(a0[bb[3] - 1] > 0)[0]
    anchor = (float((foot_rows.min() + foot_rows.max() + 1) / 2.0), float(bb[3]))
    body_h = bb[3] - bb[1]
    scale = spec.unit_h(1) / body_h
    hit_i = spec.ACTIONS["attack"]["hit"]
    # ★ 총구 = 놓는 칸의 **칼끝**. 알파 상자의 오른쪽 위 모서리로 잡으면 안 된다 —
    #   그 자리는 후드다(첫 판에서 y 가 -79 로 나와 머리 꼭대기를 가리켰다).
    ha = np.array(Image.open(e_atk[hit_i]).convert("RGBA"))[:, :, 3]
    ys_, xs_ = np.where(ha > 0)
    xmax = xs_.max()
    ytip = float(ys_[xs_ == xmax].mean())
    muzzle = [xmax - anchor[0], ytip - anchor[1]]
    rep["contract"] = {
        "anchor": anchor, "body_h_px": body_h, "unit_h": spec.unit_h(1),
        "scale": round(scale, 4),
        "muzzle_at": [round(muzzle[0], 1), round(muzzle[1], 1)],
        "hit_frame_0based": hit_i,
        "same_crop_box": alpha_bbox_union(e_idle) == alpha_bbox_union(e_idle),
        "sheets": sheets,
        "cross_clip_foot": sorted({alpha_bbox(Image.open(p).convert("RGBA"))[3]
                                   for p in e_idle + e_atk}),
        "loop_seam_l1": loop_seam(e_idle),
    }
    (OUT / f"sheet_report_{variant}{tag}.json").write_text(
        json.dumps(rep, ensure_ascii=False, indent=1))
    return rep


def alpha_bbox_union(paths):
    bbs = [alpha_bbox(Image.open(p).convert("RGBA")) for p in paths]
    return (min(b[0] for b in bbs), min(b[1] for b in bbs),
            max(b[2] for b in bbs), max(b[3] for b in bbs))


def loop_seam(paths) -> float:
    """마지막 칸과 첫 칸의 평균 차이. 돌 때 툭 튀는지의 잣대다."""
    a = np.array(Image.open(paths[-1]).convert("RGBA"), np.int16)
    b = np.array(Image.open(paths[0]).convert("RGBA"), np.int16)
    return round(float(np.abs(a - b).mean()), 3)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--variant", default="flat")
    ap.add_argument("--tag", default="")
    a = ap.parse_args()
    r = run(a.variant, a.tag)
    for k, v in r["clips"].items():
        print(f"  {k:12s} {v['n']}칸 · 색 {v['colors_max']:2d} · 이탈 {v['outliers']} · "
              f"반투명 {v['semi_alpha']} · 발흔들림 {v['foot_y_spread']}px · "
              f"테두리 {v['outline_min']:.3f}")
    c = r["contract"]
    print(f"  기준점 {c['anchor']} · 몸높이 {c['body_h_px']}px · 배율 {c['scale']} · "
          f"총구 {c['muzzle_at']} · 루프 이음매 {c['loop_seam_l1']}")
