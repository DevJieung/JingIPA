#!/usr/bin/env python3
"""★★ **내부 선화** — 세 후보가 같이 지적한 숙제 10번의 답.

## 무엇이 문제였나
후처리 테두리(`pixels.add_outline`)는 **실루엣 바깥만** 두른다. 그래서 후드·수염·
곰가죽 갈기가 원화에서는 검은 선으로 갈리는데 3D 툰에서는 **흰 알 한 덩어리**로
뭉쳤다. 이것이 두 길의 가장 큰 품질 차이였다.

## 어떻게 풀었나 — 번호+깊이 한 장을 더 굽고, **번호가 바뀌는 자리**에 선을 긋는다
5단계가 프레임마다 두 장을 굽는다:
  * 색 한 장 (툰 3톤)
  * 번호+깊이 한 장 (`material_override` · `view_transform='Raw'`)
      R = 오브젝트 번호 · G·B = 카메라 깊이 16비트

그다음 여기서, 알파가 있는 픽셀 중 **4이웃에 다른 번호가 있는** 자리를 찾아
**둘 중 더 먼 쪽**을 어둡게 칠한다.

★ 왜 「더 먼 쪽」인가: 앞에 있는 덩어리(갈기·수염·칼날)는 대개 **밝고 좁다.**
  거기를 깎으면 형태가 그만큼 얇아진다. 뒤쪽을 어둡게 하면 앞 덩어리 둘레에
  **그림자**가 생겨 형태가 그대로 살면서 갈린다 — 도트 그림이 늘 쓰는 수다.
★ 왜 실루엣 바깥은 안 그리는가: 이웃이 투명하면 번호가 없으므로 애초에 안 걸린다.
  바깥은 `add_outline` 이 두른다(그쪽이 outline_ratio 1.00 을 낸다 — 후보 A 의 실측).

## 얼마나 벌었나 — `probe_lines.py` 가 잰 것 (요쿨 idle 0번 칸, 후처리까지 마친 뒤)
    「밝은(V>0.70) 픽셀의 연결 성분 중 **제일 큰 덩어리**」
      선 없음                2454 px  (덩어리 2개 — 후드·갈기·수염·소맷부리가 통째로 하나)
      Freestyle crease      1105 px  (덩어리 12개)
      **번호+깊이(이 파일)   217 px  (덩어리 29개)**
      공식 마스터96          1150 px  (덩어리 20개)
      공식 idle 0번 칸        693 px  (덩어리 16개)
    ★ 우리 쪽이 공식보다도 더 잘게 갈린다. 갈라 놓은 덩어리 수(34개)가 곧 선의 수라,
      「선을 넣고 싶은 곳마다 오브젝트를 나눈다」가 이 길의 손잡이다.

## 시도했다 버린 길 둘 (숫자는 `probe_freestyle.py` 가 잰 것)
  (a) **인버티드 헐** — 실루엣 바깥에도 검은 띠가 생겨 `add_outline` 과 겹쳐
      **2px 테두리**가 된다. 96px 에서 2px 는 얼굴을 절반 먹는다. 그리고 띠 굵기가
      면의 기울기에 따라 변해서 outline_ratio 가 1.00 에서 내려온다.
  (c) **Freestyle crease** — 실제로 켜서 쟀다. 계약서가 걱정한 **반투명은 0개**였고
      팔레트 이탈도 0이었다(그 걱정은 silhouette 선을 켰을 때의 것이다). 그런데
      **우리가 필요한 선을 안 그린다** — crease 는 「한 메시 안의 접힌 모서리」라,
      후드와 갈기처럼 **서로 다른 덩어리가 겹치는 자리**에는 선이 안 생긴다.
      실측: 제일 큰 밝은 덩어리 2454 → 1105 px 로 절반만 줄었고(우리 것은 217),
      렌더는 0.0285초 → 0.0668초로 **2.35배** 느려졌다.
"""
from __future__ import annotations

import numpy as np


#: 깊이 한 칸 = 4m / 65536 = 0.061mm. 이보다 가까이 붙은 두 덩어리 사이에는
#: 선을 안 긋는다 — 팔에 박아 넣은 팔꿈치 구, 소맷부리 띠처럼 **거의 같은 면**인
#: 것들이 그렇다. 없으면 선이 채운 픽셀의 22%까지 불어나 도트가 새까매진다(실측).
MIN_GAP_M = 0.055
_UNIT = 4.0 / 65536.0


def line_mask(idpx: np.ndarray, alpha: np.ndarray,
              noline: set[int] | None = None,
              min_gap: float = MIN_GAP_M) -> np.ndarray:
    """번호+깊이 그림에서 **선을 칠할 자리**를 돌려준다.

    idpx  : (H,W,3) uint8 — R 번호 · G·B 깊이
    alpha : (H,W) bool
    """
    noline = noline or set()
    ids = idpx[:, :, 0].astype(np.int32)
    depth = (idpx[:, :, 1].astype(np.int32) * 256 + idpx[:, :, 2].astype(np.int32))
    H, W = ids.shape
    mask = np.zeros((H, W), bool)

    def cmp(dy, dx):
        # 이웃을 (dy,dx) 만큼 밀어 겹친다. 가장자리는 알파를 꺼서 뺀다.
        a = np.zeros_like(alpha)
        i2 = np.zeros_like(ids)
        d2 = np.zeros_like(depth)
        ys = slice(max(0, dy), H + min(0, dy))
        xs = slice(max(0, dx), W + min(0, dx))
        yt = slice(max(0, -dy), H + min(0, -dy))
        xt = slice(max(0, -dx), W + min(0, -dx))
        a[ys, xs] = alpha[yt, xt]
        i2[ys, xs] = ids[yt, xt]
        d2[ys, xs] = depth[yt, xt]
        both = alpha & a
        diff = both & (ids != i2)
        for n in noline:                 # 눈처럼 이미 검은 것은 경계를 안 그린다
            diff &= (ids != n) & (i2 != n)
        # ★ 더 먼 쪽(깊이가 큰 쪽)을 칠한다. 단, **충분히 떨어져 있을 때만.**
        return diff & (depth - d2 > int(min_gap / _UNIT))

    for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        mask |= cmp(dy, dx)
    return mask


def apply_lines(color: np.ndarray, idpx: np.ndarray, line_rgb: tuple[int, int, int],
                noline: set[int] | None = None,
                min_gap: float = MIN_GAP_M) -> tuple[np.ndarray, int]:
    """색 그림에 선을 얹는다. 돌려주는 것은 (그림, 칠한 픽셀 수)."""
    alpha = color[:, :, 3] > 0
    m = line_mask(idpx, alpha, noline, min_gap)
    out = color.copy()
    out[m, 0], out[m, 1], out[m, 2] = line_rgb
    return out, int(m.sum())
