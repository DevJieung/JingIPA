#!/usr/bin/env python3
"""★ 내부 선화가 실제로 얼마나 벌어 주는가를 **숫자로** 잰다 (숙제 10번의 근거).

    python3 tools/blender3d/mk/probe_lines.py

## 재는 자 둘
1. **뭉친 밝은 덩어리**(`blob`) — V>0.70 인 픽셀의 4이웃 연결 성분. 후드·갈기·수염·
   소맷부리가 갈리지 않으면 이 넷이 **한 덩어리**가 된다. 후보 B·C 가 「흰 알
   한 덩어리」라고 적은 것이 바로 이 값이다. 작을수록 좋다.
2. **경계 대비**(`step`) — 서로 다른 오브젝트가 맞닿은 픽셀쌍 중 밝기 차가 0.15
   이상인 비율. 1.0 에 가까울수록 「어디가 어디까지인지」가 화면에 있다는 뜻이다.

★ 두 자 모두 공식 파이프라인의 결과에도 그대로 대 본다 — 우리 쪽 숫자만 좋아지는
  자를 만들면 그 자는 아무것도 안 재는 것이다.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE.parent.parent / "sprite"))
import spec    # noqa: E402
import post    # noqa: E402


def _v(rgb):
    return rgb.max(axis=2) / 255.0


def blobs(im: Image.Image, thr: float = 0.70):
    """밝은 픽셀의 연결 성분. 돌려주는 것은 (제일 큰 덩어리 px, 8px 이상 덩어리 수)."""
    a = np.array(im.convert("RGBA"))
    mask = (a[:, :, 3] > 0) & (_v(a[:, :, :3].astype(float)) > thr)
    H, W = mask.shape
    lab = np.zeros((H, W), int)
    cur = 0
    sizes = []
    for y in range(H):
        for x in range(W):
            if not mask[y, x] or lab[y, x]:
                continue
            cur += 1
            st = [(y, x)]
            lab[y, x] = cur
            n = 0
            while st:
                cy, cx = st.pop()
                n += 1
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ny, nx = cy + dy, cx + dx
                    if 0 <= ny < H and 0 <= nx < W and mask[ny, nx] and not lab[ny, nx]:
                        lab[ny, nx] = cur
                        st.append((ny, nx))
            sizes.append(n)
    sizes.sort(reverse=True)
    return (sizes[0] if sizes else 0), sum(1 for s in sizes if s >= 8), int(mask.sum())


def edge_step(im: Image.Image, idpx: np.ndarray, thr: float = 0.15) -> tuple[int, float]:
    """오브젝트 경계 픽셀쌍 중 **밝기 차가 보이는** 비율."""
    a = np.array(im.convert("RGBA"))
    al = a[:, :, 3] > 0
    v = _v(a[:, :, :3].astype(float))
    ids = idpx[:, :, 0].astype(int)
    tot = 0
    ok = 0
    H, W = ids.shape
    for dy, dx in ((0, 1), (1, 0)):
        s1 = (slice(0, H - dy), slice(0, W - dx))
        s2 = (slice(dy, H), slice(dx, W))
        m = al[s1] & al[s2] & (ids[s1] != ids[s2])
        tot += int(m.sum())
        ok += int((m & (np.abs(v[s1] - v[s2]) >= thr)).sum())
    return tot, (ok / tot if tot else 0.0)


def main():
    p = spec.paths("jokull")
    pal = spec.palette_for("ice")
    rows = []
    for label, src in (("선 없음(5_raw)", p["root"] / "5_raw/idle/SE"),
                       ("선 있음(5_frames)", p["frames"] / "idle/SE")):
        f = sorted(src.glob("*.png"))[0]
        im = post.clean_one(f, pal, outline=True)
        big, n, bright = blobs(im)
        rows.append((label, big, n, bright))
    # 오브젝트 번호 그림은 5_raw 쪽에 없다 — 렌더가 남긴 것을 다시 만들 수 없으므로
    # 경계 대비는 **선 없는 원본**에 대해서만 잰다(선을 그으면 정의상 1.0 이 된다).
    print("%-22s %8s %8s %8s" % ("", "최대덩어리", "덩어리수", "밝은px"))
    for label, big, n, bright in rows:
        print("%-22s %8d %8d %8d" % (label, big, n, bright))
    for label, path in (("공식 마스터96", p["ref"] / "jokull_master96.png"),
                        ("공식 idle f0", spec.ROOT / "art/anim/jokull/jokull_idle.png")):
        im = Image.open(path).convert("RGBA")
        if im.width != im.height:
            im = im.crop((0, 0, im.height, im.height))
        big, n, bright = blobs(im)
        print("%-22s %8d %8d %8d" % (label, big, n, bright))


if __name__ == "__main__":
    main()
