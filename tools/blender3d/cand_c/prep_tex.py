#!/usr/bin/env python3
"""후보 C 준비 — **원화에서 가져올 것 두 가지**를 미리 뽑아 둔다.

  1) `colors.json` — 부위마다의 대표색(원화 픽셀에서 실측). 갈래 (2) 「부위별 색 추출」.
  2) `proj.png`    — UV 투영에 쓸 텍스처. 갈래 (1) 「원화 텍스처 투영」.

★ Blender 4.0.2 의 내장 파이썬에는 PIL 이 없다. 그래서 **PIL 이 필요한 일은 전부
  여기(시스템 파이썬)에서 미리** 끝내고, Blender 쪽은 JSON 과 PNG 만 읽는다.

★ `proj.png` 은 그냥 원화가 아니다. 셋을 손봤다:
   - 알파 상자로 **바짝 자른다**. 안 자르면 투영 사각형과 그림 사각형이 어긋나
     캐릭터 옆에 빈 여백이 붙는다.
   - 투명한 곳을 **가장 가까운 불투명 색으로 메운다**(dilate). 안 메우면 알파 0 인
     자리의 RGB(거의 흰색)가 새어 나와 실루엣 둘레에 흰 테가 돈다 —
     `cut_white` 가 배경을 지우면서 남긴 값이라 그림에는 안 보이지만 텍스처로 쓰면 보인다.
   - 세로로 뒤집는다. Blender 의 UV 는 v=0 이 **아래**다.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
SRC = ROOT / "build/b3d/jokull/1_turnaround/jokull_hi.png"
OUT = ROOT / "build/b3d/cand_c"

#: 원화에서 색을 길어 올릴 자리 (사람이 눈으로 찍은 상자다 — 962x1009 픽셀 좌표).
#: ★ 상자를 잘못 찍으면 그 부위가 통째로 다른 색이 된다. 뽑은 뒤 반드시 눈으로 본다.
BOXES = {
    "fur":     (200,  40, 600, 300),   # 후드·털
    "beard":   (450, 200, 610, 330),
    "skin":    (470, 120, 560, 190),
    "plate":   (400, 300, 640, 500),   # 파란 판금
    "cloak":   (640, 180, 760, 650),   # 검푸른 망토
    "belt":    (410, 505, 650, 560),
    "tabard":  (490, 560, 660, 700),   # 청록 겉옷
    "blade":   (560, 700, 930, 880),
    "boot":    (200, 890, 350, 1000),
    "glove":   (770, 330, 900, 440),
}


def dominant(arr: np.ndarray, k: int = 6) -> list[tuple[str, float]]:
    """8단위로 뭉갠 뒤 많이 나온 색 순서. (원화가 업스케일이라 고유색이 7만 개다)"""
    q = (arr[:, :3] // 8 * 8).astype(np.uint8)
    keys, counts = np.unique(q.reshape(-1, 3), axis=0, return_counts=True)
    order = np.argsort(-counts)
    tot = counts.sum()
    return [("#%02x%02x%02x" % tuple(int(v) for v in keys[i]),
             round(float(counts[i] / tot), 4)) for i in order[:k]]


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    im = Image.open(SRC).convert("RGBA")
    a = np.array(im)
    op = a[:, :, 3] > 128

    # ---- 1) 부위별 대표색
    rep = {}
    for name, (x0, y0, x1, y1) in BOXES.items():
        sub = a[y0:y1, x0:x1]
        m = sub[:, :, 3] > 200
        px = sub[m]
        if len(px) == 0:
            rep[name] = {"n": 0, "top": []}
            continue
        rep[name] = {"n": int(len(px)), "top": dominant(px)}

    # ---- 2) 투영 텍스처
    ys, xs = np.where(op)
    bb = (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)
    crop = a[bb[1]:bb[3], bb[0]:bb[2]].copy()
    rgb = crop[:, :, :3].astype(np.int16)
    mask = crop[:, :, 3] > 128
    # 투명한 곳을 이웃의 불투명 색으로 번지게 한다 (네 방향 · 몇 번 돌린다)
    for _ in range(48):
        if mask.all():
            break
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            src = np.roll(mask, (dy, dx), (0, 1))
            srgb = np.roll(rgb, (dy, dx), (0, 1))
            fill = src & ~mask
            rgb[fill] = srgb[fill]
            mask = mask | fill
    tex = np.dstack([rgb.astype(np.uint8),
                     np.full(rgb.shape[:2], 255, np.uint8)])
    Image.fromarray(tex, "RGBA").save(OUT / "proj.png")

    meta = {
        "src": str(SRC), "src_size": list(im.size),
        "alpha_bbox": list(bb),
        "proj_png": str(OUT / "proj.png"),
        "proj_size": [int(bb[2] - bb[0]), int(bb[3] - bb[1])],
        "regions": rep,
    }
    (OUT / "colors.json").write_text(json.dumps(meta, ensure_ascii=False, indent=1))
    print(f"원화 {im.size} · 알파 상자 {bb} · 투영 텍스처 {meta['proj_size']}")
    for k, v in rep.items():
        print(f"  {k:8s} " + "  ".join(f"{h}:{p}" for h, p in v["top"][:4]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
