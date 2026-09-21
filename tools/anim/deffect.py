#!/usr/bin/env python3
"""마스터에서 **뻗은 손 위의 이펙트**만 떼어낸다 — ART.md 3번.

★ 색으로는 못 가른다. 화염마도사에서 불꽃 (214,55,22) 와 붉은 옷 (206,55,23) 은 사실상
  같은 색이었다. 서리여왕도 마찬가지다 — 얼음 조각과 옅은 얼음빛 옷깃이 같은 파랑이다.
  가르는 것은 **이어짐**이다. 이펙트 한가운데에서 **밝은 픽셀만 타고** 물을 부으면
  어두운 소매·옷주름에서 끊긴다.

★ 문턱을 하나로 못 박지 않는다. 낮은 문턱부터 올려 가며, 번진 자리가 상자를 넘거나
  그림을 너무 많이 먹으면 다음 문턱으로 간다. **조용히 옷을 지우느니 눈에 띄게 실패한다.**

★ **막대 모양 이펙트는 물로 못 뗀다** (`--line`). 궁수의 메긴 살이 그랬다 —
  살대는 손에서 활까지 **이어져 있고**, 색이 손등(216,187,143)과 **똑같다.**
  이어짐으로도 색으로도 못 가른다. 대신 그것은 **양 끝을 아는 곧은 막대**이므로
  선으로 뗀다. 창·광선도 같다.
  ⚠ 물 붓기가 살대에서 끊긴 진짜 이유도 적어 둔다: 살대의 밝은 마디(232,220,182)가
    `warm` 의 `(r-b)>=70` 에 걸려 **이펙트가 아닌 것으로 판정**됐다. 한 줄짜리 이펙트는
    마디 하나만 막혀도 통째로 끊긴다.

    python3 tools/anim/deffect.py 원본.png 결과.png --box 0.5,0.0,1.0,0.5 --hue cool
    python3 tools/anim/deffect.py 원본.png 결과.png --line 20,44,88,44,3;26,45,14,34,3
"""
from __future__ import annotations

import argparse

import numpy as np
from PIL import Image

# 이펙트 색깔 갈래. 문턱을 올려도 **옷 쪽으로는 안 새게** 하는 최소한의 색 조건이다.
HUE = {
    "warm": lambda r, g, b: (g >= 40) & ((r - b) >= 70),    # 불 · 용암
    "cool": lambda r, g, b: (g >= 90) & ((b - r) >= 25),    # 얼음 · 물
    "any":  lambda r, g, b: np.ones(r.shape, bool),
}


def flood(mask: np.ndarray, sy: int, sx: int) -> np.ndarray:
    h, w = mask.shape
    out = np.zeros_like(mask)
    st = [(sy, sx)]
    out[sy, sx] = True
    while st:
        y, x = st.pop()
        for ny, nx in ((y-1, x), (y+1, x), (y, x-1), (y, x+1),
                       (y-1, x-1), (y-1, x+1), (y+1, x-1), (y+1, x+1)):
            if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not out[ny, nx]:
                out[ny, nx] = True
                st.append((ny, nx))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--box", default="0.5,0.0,1.0,0.55",
                    help="이펙트가 있는 자리 x0,y0,x1,y1 (그림 크기 대비 0~1)")
    ap.add_argument("--hue", default="cool", choices=list(HUE))
    ap.add_argument("--max-frac", type=float, default=0.30,
                    help="그림의 이만큼을 넘게 먹으면 문턱을 올린다")
    ap.add_argument("--line", default="",
                    help="막대 이펙트를 **선**으로 뗀다. x0,y0,x1,y1,굵기 를 ';' 로 여럿. "
                         "★ 물 붓기(--box)와 함께 쓰지 않는다 — 이건 다른 방법이다")
    ap.add_argument("--lo", type=float, default=0.62,
                    help="문턱을 심지 밝기의 이 배부터 올려 본다(기본 0.62). ★ **가늘고 긴 "
                         "이펙트**는 낮춰야 한다 — 궁수의 살대는 한 줄이라 밝기가 103~232 로 "
                         "출렁이는데 0.62(=124)에서 시작하면 어두운 마디에서 끊겨 일곱 픽셀만 "
                         "떼고 끝난다. 덩어리 이펙트(불덩이·얼음조각)는 안 건드려도 된다")
    ap.add_argument("--seed", default="",
                    help="이펙트 심지 x,y 를 직접 찍는다. ★ **가늘고 긴 이펙트**(궁수의 "
                         "메긴 살)에서는 「상자 안 가장 밝은 3% 의 무게중심」이 살대가 아니라 "
                         "빈 곳에 떨어진다 — 활과 살이 둘 다 밝아서 중심이 그 사이로 간다. "
                         "그러면 어느 문턱에서도 안 갈린다. probe.py 로 찍어서 넣어라")
    ap.add_argument("--keep-floating", action="store_true",
                    help="떠 있는 조각을 이펙트로 안 친다. ★ 몸에서 떨어진 **소품 조각**이 "
                         "있는 그림(활 윗고자 · 화살통에서 삐져나온 살 · 어깨 너머 망토)에 "
                         "쓴다. 안 쓰면 그것들이 조용히 같이 지워진다")
    a = ap.parse_args()

    img = np.array(Image.open(a.src).convert("RGBA")).astype(int)
    rgb, al = img[:, :, :3], img[:, :, 3]
    h, w = al.shape
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    hue_ok = HUE[a.hue](r, g, b)
    val = rgb.max(2)
    body_px = int((al > 0).sum())

    if a.line:
        picked = np.zeros((h, w), bool)
        yy, xx = np.mgrid[0:h, 0:w]
        for seg in a.line.split(";"):
            x0, y0, x1, y1, tw = (float(v) for v in seg.split(","))
            vx, vy = x1 - x0, y1 - y0
            L2 = vx * vx + vy * vy or 1e-6
            u = np.clip(((xx - x0) * vx + (yy - y0) * vy) / L2, 0.0, 1.0)
            d2 = (xx - (x0 + vx * u)) ** 2 + (yy - (y0 + vy * u)) ** 2
            picked |= (d2 <= (tw * 0.5) ** 2) & (al > 0)
            print(f"선 ({x0:.0f},{y0:.0f})~({x1:.0f},{y1:.0f}) 굵기 {tw:.0f}")
        if not picked.any():
            raise SystemExit("!! 선 위에 불투명 픽셀이 없다 — 좌표를 다시 봐라")
        return finish(img, picked, al, rgb, body_px, a, floating_ok=True)

    fx0, fy0, fx1, fy1 = (float(v) for v in a.box.split(","))
    box = np.zeros((h, w), bool)
    box[int(fy0 * h):int(fy1 * h), int(fx0 * w):int(fx1 * w)] = True

    # 씨앗 — 상자 안에서 **가장 밝은 쪽 위 3%**. 이펙트의 심지다.
    inbox = (al > 0) & box & hue_ok
    if not inbox.any():
        raise SystemExit(f"!! 상자 {a.box} 안에 {a.hue} 픽셀이 없다 — 상자를 다시 잡아라")
    cut = float(np.percentile(val[inbox], 97))
    seed = inbox & (val >= cut)
    ys, xs = np.nonzero(seed)
    if a.seed:
        cx, cy = (int(v) for v in a.seed.split(","))
        if not inbox[cy, cx]:
            raise SystemExit(f"!! 찍은 씨앗 ({cx},{cy}) 이 상자 안의 {a.hue} 픽셀이 아니다")
        cut = float(val[cy, cx])
    else:
        cy, cx = int(round(ys.mean())), int(round(xs.mean()))
    print(f"씨앗 중심 ({cx},{cy})  심지 {int(seed.sum())}px  밝기문턱 {cut:.0f}")

    picked = None
    lo = int(cut * a.lo)
    for thr in range(lo, int(cut) + 1, max(3, (int(cut) - lo) // 7 or 1)):
        hot = (al > 0) & hue_ok & (val >= thr)
        if not hot[cy, cx]:
            continue
        m = flood(hot, cy, cx)
        my, mx = np.nonzero(m)
        spill = int((m & ~box).sum())
        frac = m.sum() / max(1, body_px)
        print(f"  문턱 {thr:3d}: {int(m.sum()):5d}px ({frac:5.1%})  "
              f"y {my.min()}~{my.max()} x {mx.min()}~{mx.max()}  상자밖 {spill}px")
        if frac <= a.max_frac and spill <= m.sum() * 0.08:
            picked = m
            break
    if picked is None:
        raise SystemExit("!! 어느 문턱에서도 이펙트가 안 갈렸다 — 상자나 --hue 를 다시 봐라")

    return finish(img, picked, al, rgb, body_px, a, floating_ok=a.keep_floating)


def finish(img, picked, al, rgb, body_px, a, floating_ok: bool):
    # 테두리 한 겹까지 같이 떼어낸다 — 이펙트 둘레의 어두운 외곽선이 남으면 **유령**이 된다.
    grow = picked.copy()
    for _ in range(2):
        p = np.pad(grow, 1)
        nb = p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]
        grow |= nb & ~grow & (al > 0) & (rgb.max(2) < 95)   # 어두운 테두리만
    out = img.copy()
    out[grow] = (0, 0, 0, 0)

    # ★ **떠 있는 조각은 전부 이펙트다** (ART.md 3). 물을 붓고 남은 것 중 **가장 큰
    #   덩어리(=몸)** 만 남긴다. 이펙트가 손에서 떨어져 떠 있으면(서리여왕의 얼음
    #   조각과 그 둘레의 성엣가지 여섯 점이 그랬다) 물 붓기만으로는 하나도 못 뗀다.
    #   ⚠ 몸에서 떨어진 **소품**이 있는 그림에는 쓰면 안 된다 — 같이 지워진다.
    if floating_ok:
        Image.fromarray(out.astype(np.uint8)).save(a.dst)
        print(f"뗀 넓이 {int(grow.sum())}px ({grow.sum()/max(1,body_px):.1%})  "
              f"(떠 있는 조각은 그대로 뒀다)  →  {a.dst}")
        return 0

    rest = out[:, :, 3] > 0
    seen = np.zeros_like(rest)
    biggest, drops = None, []
    for y0, x0 in zip(*np.nonzero(rest)):
        if seen[y0, x0]:
            continue
        m = flood(rest & ~seen, y0, x0)
        seen |= m
        if biggest is None or m.sum() > biggest.sum():
            if biggest is not None:
                drops.append(biggest)
            biggest = m
        else:
            drops.append(m)
    if drops:
        floating = np.zeros_like(rest)
        for m in drops:
            floating |= m
        print(f"떠 있던 조각 {len(drops)}개 {int(floating.sum())}px 도 이펙트로 친다")
        out[floating] = (0, 0, 0, 0)
        grow = grow | floating

    Image.fromarray(out.astype(np.uint8)).save(a.dst)
    print(f"뗀 넓이 {int(grow.sum())}px ({grow.sum()/max(1,body_px):.1%})  →  {a.dst}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
