#!/usr/bin/env python3
"""마스터를 **몸통 / 팔** 로 가른다 — ART.md 4번.

어깨에서 아래로 비스듬한 선 하나를 긋고, 그 바깥쪽의 **어깨와 이어진 덩어리**만 팔로 친다.
★ 이어짐을 안 보면 모자챙 끝·자락 끝처럼 선 바깥에 있을 뿐인 조각이 딸려 온다.
  화염마도사에서 실제로 모자챙이 팔에 붙어 따라 돌았다.

★ 팔 조각은 **마스터 캔버스 좌표 그대로** 저장한다. 잘라서 저장하면 rig 가 어깨를
  못 찾는다 — rig 는 마스터 좌표로 셈한다.

    python3 tools/anim/cut_arm.py build/frost_queen/master.png \
        --shoulder 55,31 --cut 54@28,58@54 --out build/frost_queen
"""
from __future__ import annotations

import argparse
import json
import math
import os

import numpy as np
from PIL import Image


def parse_cut(s: str):
    """'54@28,58@54' → (x0,y0),(x1,y1) 를 지나는 자르는 선."""
    (a, b) = s.split(",")
    x0, y0 = (float(v) for v in a.split("@"))
    x1, y1 = (float(v) for v in b.split("@"))
    if y1 == y0:
        raise SystemExit("자르는 선의 두 y 가 같다")
    return (x0, y0), (x1, y1)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("master")
    ap.add_argument("--shoulder", required=True, help="x,y (마스터 좌표)")
    ap.add_argument("--cut", required=True, help="x@y,x@y — 몸통 옆선을 따라가는 선")
    ap.add_argument("--yrange", default="", help="y0,y1 — 이 사이만 자른다 (기본: 어깨~선 아래끝)")
    ap.add_argument("--side", default="right", choices=["right", "left"],
                    help="팔이 선의 어느 쪽인가")
    ap.add_argument("--tip", default="",
                    help="손끝 x,y. 안 주면 어깨에서 가장 먼 팔 픽셀 — ★ 자락이 길게 "
                         "드리운 팔에서는 그게 **자락 끝**을 집으므로 눈으로 찍어 줘라")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    img = np.array(Image.open(a.master).convert("RGBA"))
    al = img[:, :, 3] > 0
    h, w = al.shape
    sx, sy = (float(v) for v in a.shoulder.split(","))
    (cx0, cy0), (cx1, cy1) = parse_cut(a.cut)
    y0, y1 = (int(cy0), int(cy1)) if not a.yrange else (
        int(a.yrange.split(",")[0]), int(a.yrange.split(",")[1]))

    def cut_x(y: float) -> float:
        return cx0 + (y - cy0) * (cx1 - cx0) / (cy1 - cy0)

    arm = np.zeros_like(al)
    for y in range(max(0, y0), min(h, y1 + 1)):
        xc = int(round(cut_x(y)))
        rng = range(max(0, xc), w) if a.side == "right" else range(0, min(w, xc + 1))
        for x in rng:
            if al[y, x]:
                arm[y, x] = True

    # 어깨에서 물을 부어 **이어진 것만** 남긴다.
    seed = None
    for dy in range(0, y1 - y0 + 1):
        y = int(sy) + dy
        if not (0 <= y < h):
            continue
        xc = int(round(cut_x(y)))
        for dx in range(0, 8):
            x = xc + (dx if a.side == "right" else -dx)
            if 0 <= x < w and arm[y, x]:
                seed = (y, x)
                break
        if seed:
            break
    if not seed:
        raise SystemExit("!! 어깨에서 팔을 못 찾았다 — --shoulder / --cut 을 다시 봐라")

    keep = np.zeros_like(arm)
    st = [seed]
    keep[seed] = True
    while st:
        y, x = st.pop()
        for ny, nx in ((y-1, x), (y+1, x), (y, x-1), (y, x+1),
                       (y-1, x-1), (y-1, x+1), (y+1, x-1), (y+1, x+1)):
            if 0 <= ny < h and 0 <= nx < w and arm[ny, nx] and not keep[ny, nx]:
                keep[ny, nx] = True
                st.append((ny, nx))
    dropped = int(arm.sum() - keep.sum())
    arm = keep

    # ★ 자른 뒤 몸통에 **떨어져 나온 조각**이 남는다. 자르는 선은 곧은 직선인데 팔의
    #   위쪽 테두리는 그렇지 않아서, 선 위쪽에 손 외곽선 몇 픽셀이 늘 남는다.
    #   그대로 두면 손은 날아갔는데 그 자리에 점 몇 개가 **붙박이 유령**으로 남는다.
    #   몸통은 원래 하나로 이어져 있으므로, 남은 조각 중 **팔에 붙은 것**은 팔로 옮긴다.
    torso_m = al & ~arm
    seen = np.zeros_like(torso_m)
    parts = []
    for y0, x0 in zip(*np.nonzero(torso_m)):
        if seen[y0, x0]:
            continue
        st = [(y0, x0)]
        seen[y0, x0] = True
        pts = [(y0, x0)]
        while st:
            y, x = st.pop()
            for ny, nx in ((y-1, x), (y+1, x), (y, x-1), (y, x+1),
                           (y-1, x-1), (y-1, x+1), (y+1, x-1), (y+1, x+1)):
                if 0 <= ny < h and 0 <= nx < w and torso_m[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    st.append((ny, nx))
                    pts.append((ny, nx))
        parts.append(pts)
    parts.sort(key=len, reverse=True)
    moved = 0
    for pts in parts[1:]:
        blob = np.zeros_like(torso_m)
        for y, x in pts:
            blob[y, x] = True
        p8 = np.pad(blob, 1)
        touch = (p8[:-2, 1:-1] | p8[2:, 1:-1] | p8[1:-1, :-2] | p8[1:-1, 2:]
                 | p8[:-2, :-2] | p8[:-2, 2:] | p8[2:, :-2] | p8[2:, 2:])
        if (touch & arm).any():
            arm |= blob
            moved += len(pts)
        else:
            print(f"!! 몸통에 팔과 안 닿은 조각 {len(pts)}px 이 떠 있다 — 눈으로 봐라")
    if moved:
        print(f"자르고 남은 조각 {moved}px 을 팔로 옮겼다")

    torso = img.copy()
    torso[arm] = (0, 0, 0, 0)
    only = np.zeros_like(img)
    only[arm] = img[arm]

    os.makedirs(a.out, exist_ok=True)
    Image.fromarray(torso).save(os.path.join(a.out, "part_torso.png"))
    Image.fromarray(only).save(os.path.join(a.out, "part_arm.png"))

    # 손끝 — 어깨에서 **가장 먼** 팔 픽셀. 길이(L0)와 자연 각(A0)이 여기서 나온다.
    if a.tip:
        tip = tuple(float(v) for v in a.tip.split(","))
    else:
        ys, xs = np.nonzero(arm)
        d = np.hypot(xs - sx, ys - sy)
        k = int(np.argmax(d))
        tip = (float(xs[k]), float(ys[k]))
    rig = dict(shoulder=[sx, sy], tip=list(tip),
               L0=float(math.hypot(tip[0] - sx, tip[1] - sy)),
               A0=float(math.atan2(tip[1] - sy, tip[0] - sx)),
               arm_px=int(arm.sum()), torso_px=int((torso[:, :, 3] > 0).sum()))
    with open(os.path.join(a.out, "rig.json"), "w", encoding="utf-8") as f:
        json.dump(rig, f, ensure_ascii=False, indent=2)

    print(f"팔 {rig['arm_px']}px  몸통 {rig['torso_px']}px  "
          f"선 바깥이지만 안 이어져 버린 조각 {dropped}px")
    print(f"어깨 ({sx:.0f},{sy:.0f}) → 손끝 ({tip[0]:.0f},{tip[1]:.0f})  "
          f"길이 {rig['L0']:.1f}px  각 {math.degrees(rig['A0']):.0f}도")
    print(f"  → {a.out}/part_torso.png · part_arm.png · rig.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
