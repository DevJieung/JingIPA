#!/usr/bin/env python3
"""스프라이트 파이프라인의 그림 규칙 한 곳.

`sprite_pipeline.md` §1(에셋 규격·속성 팔레트)과 `sprite_design.md`(§2 재질당 3톤 ·
§3 1도트 검은 테두리 · §5 눈 두 점)를 **코드로 옮긴 유일한 자리**다.

★ 팔레트를 두 곳에 적지 마라. 원화(Step 1)와 시트(Step 3)가 다른 팔레트를 쓰면
  "원화는 파란데 시트는 하늘색인" 캐릭터가 나오고, 그 어긋남은 눈으로만 잡힌다.
  `sprite_pipeline.md` 의 `sprite_post.py` 가 갖고 있던 PALETTE/SKIN/quantize 가
  전부 여기로 올라왔다.
"""

from __future__ import annotations

from PIL import Image

# --------------------------------------------------------------------------
# 속성 램프 — sprite_pipeline.md §1
#   유닛별로 색을 자유 생성하면 백 탄 규모에서 통일감이 무너진다. 다섯 속성은
#   램프를 못 박고, 캐릭터가 쓰는 색은 여기에 공용 8색을 더한 **열다섯**뿐이다.
#
# ★★ **램프가 일곱이고 공용이 여덟이다 — 이 비율을 뒤집지 마라.**
#   예전에는 램프 5 · 공용 12 였고, 그래서 팔레트의 **71%가 무채·갈색**이었다.
#   dominant 양자화는 넓은 쪽으로 끌어당기므로 여든 명이 통째로 갈회색이 됐다
#   (실측: 원본 밝기 0.243 · 채도 0.711 → 마스터 0.078 · **0.000**).
#   지금은 7:8 이라 속성 색이 제 몫을 갖는다.
# ★ 램프의 제일 어두운 칸은 V≈0.30 이다 — **더 내리지 마라.** 깊은 그늘은 검정
#   테두리와 공용의 어두운 둘이 이미 지고 있어서, 램프까지 검정 쪽으로 내리면
#   속성 색이 쓸 수 있는 칸이 다시 둘로 줄어든다.
# --------------------------------------------------------------------------
# ★★★ **램프는 「밝기 사다리」가 아니라 그 가문이 쓰는 색 일곱이다.**
#   설계서 §1.1 이 가문마다 핵심 색을 둘씩 못 박았고(물=잉크빛 남색+은 · 불=진홍+주황 ·
#   얼음=백청+흰색 · 전기=연두+보라 · 무=무채색+홀로그램), 로스터 쉰 줄의 옷 묘사가
#   그 둘을 그대로 쓴다. 램프가 그중 **하나만** 담고 있으면 나머지 하나를 입은 캐릭터가
#   통째로 공용 무채색으로 빨려 들어간다.
#
#   실측으로 그렇게 됐다: 림네(물)의 옷이 「bright cerulean」인데 옛 물 램프는
#   청록(민트) 일곱뿐이라, 파랑이 갈 칸이 없어서 **회색**이 됐다 —
#   게임 일러스트 채도 0.807 → 마스터 0.141. 화면에서는 편성 판의 파란 아이가
#   전투 화면에서 회색 아이로 서는 것이다.
#
# ★ 그래서 램프마다 **두 색을 다 담는다.** 밝기 순서가 아니어도 된다 — 이 표는
#   `quantize` 가 쓰는 **색 집합**이지 셰이딩 사다리가 아니다.
# ★ **물과 얼음은 여전히 갈라져야 한다**(CLAUDE.md 18-6). 물은 남색↔청록이고
#   얼음은 백청↔흰색이다 — 물은 아래쪽이 깊고 얼음은 위쪽이 얕다.
# ★ **전기는 이제 연두가 있다.** CLAUDE.md 18-6 이 「전기 램프는 노랑에서 주황을
#   건너뛰고 보라로」라고 적어 두었는데 옛 표는 **보라 일곱**뿐이었다 — 지침과
#   표가 어긋나 있었다.
# ★ 램프의 제일 어두운 칸은 V≈0.30 이다 — **더 내리지 마라.** 깊은 그늘은 검정
#   테두리와 공용의 어두운 둘이 이미 지고 있어서, 램프까지 검정 쪽으로 내리면
#   속성 색이 쓸 수 있는 칸이 다시 둘로 줄어든다.
PALETTE = {
    # 진홍 → 주황 (심장의 가문)
    "fire":  ["#5c1a10", "#a32218", "#c04a1c", "#e0702a", "#f5943f", "#ffbf62", "#ffe6a8"],
    # 연두 → 보라 (분기의 가문). 앞 셋이 연두, 뒤 넷이 보라다.
    "elec":  ["#4a5c12", "#8fbf1c", "#c8ee2e", "#3a2a80", "#6d5ae0", "#a996ff", "#eae2ff"],
    # 백청 → 흰색 (결정의 가문). 물보다 **얕고 밝다** — 그것이 둘을 가른다.
    "ice":   ["#24568c", "#3f8fc9", "#6fb8e6", "#8fd0ef", "#b8e6f8", "#dff4ff", "#f4fcff"],
    # 잉크빛 남색 → 청록 (조수의 가문). 얼음보다 **깊다**.
    "water": ["#0d2b4a", "#12507a", "#1a86b0", "#1f8f78", "#35c0a8", "#6fdcc4", "#bff0e4"],
    # 무채색 + 홀로그램 (이름 없는 가문). 앞 다섯이 무채·놋쇠, 뒤 둘이 홀로그램이다.
    # ★ 무상성에 **속성 색**을 주는 것이 아니다(CLAUDE.md 4-4-0-1) — 홀로그램은
    #   설계서가 이 가문에 준 결이고, 무엇보다 옛 표는 순회색에 가까워서 이 가문
    #   열 명이 **공용 무채 셋과 같은 자리**를 놓고 다퉜다.
    "none":  ["#33302a", "#524d43", "#756f60", "#a89db2", "#dad3c3", "#e07ad8", "#5fd8e8"],
}

# 공용 살결·쇠·가죽 **8색**.
# ★ 맨 앞이 순검정이다 — sprite_design.md §3 의 「1도트 검은 테두리」가 실루엣의
#   절반을 지므로, 팔레트에 검정이 없으면 테두리가 회색으로 뭉개진다.
#   `qc` 의 `outline_ratio` 가 가장자리의 60% 를 검정으로 요구한다.
# ★★ **나머지 일곱에는 순회색(S=0)이 하나도 없다.** 예전에는 열둘 중 **다섯**이
#   순회색이었고(`#1a1a1a` `#4a4a4a` `#8a8a8a` `#c8c8c8` 과 검정), 그것이
#   **채도의 배수구**였다 — 속성 색이 조금이라도 옅은 픽셀은 전부 그리로 빨려 들어갔다.
#   실측: 원본 채도 중앙 0.711 이 마스터에서 **0.000** 이 됐다(픽셀 절반 넘게가 무채색).
#   지금은 무채 셋도 보라·따뜻한 쪽으로 살짝 틀어 두어 배수구가 안 된다.
# ★ 순백(#ffffff)은 **일부러 뺐다.** sprite_design.md §8 의 `no pure white` 는
#   화풍이 아니라 기술 규칙이다 — 크로마키를 뺀 뒤에도 흰 픽셀은 배경 잔여물과
#   구별이 안 된다. 제일 밝은 곳은 #f1ece0 에서 멈춘다.
SKIN = ["#000000",
        "#2b1a12", "#7a5136", "#b9835a", "#eec49a",
        "#3a3740", "#8d8a95", "#ccc8d4"]

CHROMA = (255, 0, 255)      # 마젠타. Step 2 입력의 배경이자 Step 3 의 키
TOL = 60                    # 크로마 판정 여유

# 프레임 규격 — sprite_pipeline.md §1
FPS = 12
FRAMES = {"idle": 8, "walk": 8, "attack": 12, "hit": 4, "death": 8}
LOOPING = {"idle", "walk"}
SIZE = {"normal": 64, "hero": 96, "boss": 128}


#: ★★ 도트로 줄이기 **전에** 밝기를 올리는 값 (감마 · 1.0 이면 안 올린다).
#:
#: 까닭: 1024px 일러스트와 96px 도트는 **같은 밝기로 읽히지 않는다.** 일러스트에서
#: 「검은 외투에 스민 푸른 반사」는 수백 픽셀이 지지만, 96px 에서 그 몫은 서너 칸이라
#: 양자화가 통째로 검정으로 접는다. 실측(원본 → 마스터, 감마 없이):
#:   V<0.2 인 픽셀이 45.5% → 55.8% · 54.3% → 62.4% · 44.5% → 57.4%
#: 그러니 이 값은 「밝게 보정」이 아니라 **줄이면서 잃는 몫을 미리 갚는 것**이다.
#:
#: ★ 여기서 올려도 **실루엣은 안 흔들린다** — 1도트 검은 테두리는 줄인 **뒤에**
#:   `add_outline` 이 순검정으로 다시 두르기 때문이다(`refine` 의 차례). 그래서
#:   올리는 자리가 반드시 줄이기 전이어야 한다. 뒤로 옮기면 테두리까지 같이 떠서
#:   sprite_design.md §3 이 「실루엣의 절반」이라 부른 그것이 회색이 된다.
LIFT_GAMMA = 0.72          # V' = V ** 0.72
LIFT_SAT = 1.12            # 채도도 조금 — 양자화가 채도를 먼저 깎는다


def lift(img: "Image.Image", gamma: float | None = None,
         sat: float | None = None) -> "Image.Image":
    """팔레트에 앉히기 **전에** 밝기·채도를 올린다 (위 LIFT_GAMMA 머리말).

    ★ 알파는 한 톨도 안 건드린다 — 배경 떼기가 이미 끝난 뒤라, 여기서 알파를
      만지면 `cut_white` 가 살려 둔 가장자리가 다시 흔들린다.
    """
    import numpy as np
    # ★ 기본값을 인자에 박지 마라 — 파이썬은 def 시점에 묶으므로, 값을 갈아 끼우고
    #   훑어보려 하면 **다섯 줄이 전부 같은 숫자로** 나온다(실제로 그랬다).
    gamma = LIFT_GAMMA if gamma is None else gamma
    sat = LIFT_SAT if sat is None else sat
    if gamma == 1.0 and sat == 1.0:
        return img
    a = np.asarray(img.convert("RGBA")).astype(np.float32) / 255.0
    rgb, al = a[..., :3], a[..., 3:]
    mx = rgb.max(axis=-1, keepdims=True)
    mn = rgb.min(axis=-1, keepdims=True)
    v2 = np.power(np.clip(mx, 0, 1), gamma)
    # 채도를 키우면서 밝기를 v2 로 옮긴다 (HSV 를 다 풀지 않고 같은 결과)
    chroma = (mx - mn) * sat
    chroma = np.minimum(chroma, v2)               # 검정 밑으로 안 내려가게
    scale = np.divide(chroma, np.maximum(mx - mn, 1e-6))
    out = (rgb - mn) * scale + (v2 - chroma)
    out = np.clip(out, 0.0, 1.0)
    return Image.fromarray((np.concatenate([out, al], axis=-1) * 255)
                           .round().astype("uint8"), "RGBA")


def hex2rgb(h: str) -> tuple[int, int, int]:
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def palette_for(elem: str) -> list[str]:
    """그 속성이 쓸 수 있는 색 전부 (램프 5 + 공용 12 = 17색)."""
    if elem not in PALETTE:
        raise KeyError(f"모르는 속성: {elem} (가능: {', '.join(PALETTE)})")
    return PALETTE[elem] + SKIN


# --------------------------------------------------------------------------
# 배경 빼기
#
# ★★ 두 벌이 있다 — **numpy 가 실제로 도는 것**이고, 픽셀 루프는 「자」다.
#   규칙은 루프(`_dekey_ref` · `_dekey_hard_ref`)에 한 픽셀씩 적혀 있고, numpy 판은 그것을
#   통째로 한 번에 계산한 것뿐이다. `selfcheck()` 가 둘이 **바이트까지 같은가**를 잰다 —
#   규칙을 고칠 일이 생기면 루프를 먼저 고치고 numpy 를 따라 고친 뒤 selfcheck 를 돌려라
#   (`python3 tools/sprite/pixels.py build/sprite/krea/clips/*/f_00*.png`).
#   ☆ 왜 numpy 인가: Wan 클립은 512x512 x 33장이라 루프로도 견딜 만했는데(클립당 4초),
#     H3 클립은 768x768 x 124장이라 같은 루프가 클립당 **30초** 다 — 쉰 명 백 장이면
#     한 시간이 크로마키에만 든다. 실측(2026-09-06, 512x512 Wan 프레임 60장):
#     루프 6.7초 · numpy 0.96초 · **다른 픽셀 0**.
# --------------------------------------------------------------------------
def _key_mask(a) -> "object":
    """`_dekey_ref` 의 한 픽셀 규칙을 배열로 — (H,W,4) uint8 → 지울 자리 bool.

    ★ 갈래의 차례(`mx == r` 먼저, 다음 `g`, 나머지 `b`)와 셈의 차례를 루프와 **똑같이**
      둔다. float64 에서 같은 차례로 셈하면 같은 비트가 나오므로 selfcheck 가 통과한다.
    """
    import numpy as np
    f = a.astype(np.float64)
    r, g, b, al = f[..., 0], f[..., 1], f[..., 2], f[..., 3]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    d = mx - mn
    sat = d / np.where(mx > 0, mx, 1.0)
    sd = np.where(d > 0, d, 1.0)                  # d == 0 은 sat == 0 이라 어차피 안 지운다
    is_r = mx == r
    is_g = (~is_r) & (mx == g)
    h = np.where(is_r, 60 * np.mod((g - b) / sd, 6),
                 np.where(is_g, 60 * ((b - r) / sd + 2), 60 * ((r - g) / sd + 4)))
    near = np.abs(np.mod(h - 300 + 180, 360) - 180) <= 22
    return (al > 0) & (mx > 0) & (sat >= 0.34) & (mx >= 60) & near


def dekey(img: Image.Image, tol: int = TOL) -> Image.Image:
    """마젠타 배경을 투명으로 — **색상(hue)으로** 가른다. (규칙은 `_dekey_ref` 머리말)"""
    import numpy as np
    a = np.asarray(img.convert("RGBA")).copy()
    a[_key_mask(a)] = 0
    return Image.fromarray(a, "RGBA")


def dekey_hard(img: Image.Image) -> Image.Image:
    """가장자리에 남은 **섞인** 마젠타를 한 번 더 턴다. (규칙은 `_dekey_hard_ref` 머리말)"""
    import numpy as np
    a = np.asarray(img.convert("RGBA")).copy()
    i = a.astype(np.int16)
    r, g, b, al = i[..., 0], i[..., 1], i[..., 2], i[..., 3]
    a[(al > 0) & (r > 110) & (b > 110) & (g < np.minimum(r, b) - 45)] = 0
    return Image.fromarray(a, "RGBA")


def keyed_ratio(before: Image.Image, after: Image.Image) -> float:
    """크로마키가 지운 비율. 0.92 를 넘으면 캐릭터까지 지운 것이다."""
    import numpy as np
    n = before.width * before.height
    left = int((np.asarray(after.convert("RGBA"))[..., 3] > 0).sum())
    return 1.0 - left / max(1, n)


def _dekey_ref(img: Image.Image, tol: int = TOL) -> Image.Image:
    """★ 자 — `dekey` 의 규칙을 한 픽셀씩 적은 것. 실제로 도는 것은 numpy 판이다.

    ★ 순색과의 거리로 재면 안 된다. 처음에는 `|r-255|<60 · g<60 · |b-255|<60` 으로
      쟀는데, Wan 을 지나온 배경은 순색 그대로 안 나온다 — 밝기가 흔들리고 가장자리에
      그라디언트가 낀다. (150, 20, 145) 같은 어두운 자주는 그 잣대를 못 넘고 **배경으로
      남는다.**
    ★ 색상은 밝기가 흔들려도 안 움직인다. 마젠타는 300도이고, 이 다섯 명 중 가장
      가까운 것이 전기 속성의 보라(250~260도)라 **±22도**면 옷을 안 먹는다.
    ★ 채도 문턱이 있어야 한다. 회색은 색상이 뜻이 없어서, 없으면 회색 갑옷이 통째로
      배경으로 읽힌다.
    """
    img = img.convert("RGBA")
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            mx, mn = max(r, g, b), min(r, g, b)
            if mx == 0:
                continue
            sat = (mx - mn) / mx
            if sat < 0.34 or mx < 60:
                continue                          # 회색·검정은 배경이 아니다
            # 색상 (0~360). 마젠타는 300도.
            d = mx - mn
            if mx == r:
                h = 60 * (((g - b) / d) % 6)
            elif mx == g:
                h = 60 * ((b - r) / d + 2)
            else:
                h = 60 * ((r - g) / d + 4)
            if abs(((h - 300 + 180) % 360) - 180) <= 22:
                px[x, y] = (0, 0, 0, 0)
    return img


def _dekey_hard_ref(img: Image.Image) -> Image.Image:
    """★ 자 — `dekey_hard` 의 규칙. 보간 때문에 실루엣 둘레에 마젠타가 조금 섞인 픽셀이
    남는데, 그것은 채도가 낮아 `dekey` 의 문턱을 못 넘고 살아남아 **자주색 후광**이 된다."""
    img = img.convert("RGBA")
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            if r > 110 and b > 110 and g < min(r, b) - 45:
                px[x, y] = (0, 0, 0, 0)
    return img


def selfcheck(paths: list[str]) -> int:
    """루프(자)와 numpy(실제)가 같은 그림을 내는가. 다른 파일 수를 돌려준다."""
    import time
    import numpy as np
    bad, t_np, t_ref = 0, 0.0, 0.0
    for p in paths:
        im = Image.open(p).convert("RGBA")
        t = time.time(); a = np.asarray(dekey_hard(dekey(im))); t_np += time.time() - t
        t = time.time(); b = np.asarray(_dekey_hard_ref(_dekey_ref(im.copy()))); t_ref += time.time() - t
        if not np.array_equal(a, b):
            bad += 1
            print(f"!! 다르다: {p} — {int((a != b).any(axis=-1).sum())}픽셀")
    print(f"selfcheck {len(paths)}장 · 다른 것 {bad}장 · numpy {t_np:.2f}초 · 루프 {t_ref:.1f}초")
    return bad


def union_bbox(imgs: list[Image.Image]) -> tuple[int, int, int, int]:
    """전 프레임 **공통** 테두리 상자.

    ★ 프레임마다 따로 자르면 발 위치가 프레임마다 튀어서 게임 안에서 덜덜 떤다
      (sprite_pipeline.md §3 의 「공통 크롭이 핵심이다」). 여기가 그 한 곳이다.
    """
    boxes = [im.getbbox() for im in imgs if im.getbbox()]
    if not boxes:
        raise SystemExit("프레임이 전부 비었다 — 크로마키가 캐릭터까지 지웠다")
    return (min(b[0] for b in boxes), min(b[1] for b in boxes),
            max(b[2] for b in boxes), max(b[3] for b in boxes))


# --------------------------------------------------------------------------
# 팔레트 고정
# --------------------------------------------------------------------------
def quantize(img: Image.Image, colors: list[str]) -> Image.Image:
    """주어진 색만 쓰도록 못 박는다. 디더링 없음(§2-1 재질당 3톤)."""
    pal = Image.new("P", (1, 1))
    flat: list[int] = []
    for c in colors:
        flat += list(hex2rgb(c))
    flat += [0] * (768 - len(flat))
    pal.putpalette(flat)
    rgb = Image.new("RGB", img.size, (0, 0, 0))
    rgb.paste(img, mask=img.split()[3])
    q = rgb.quantize(palette=pal, dither=Image.Dither.NONE).convert("RGB")
    q.putalpha(img.split()[3])
    return q


def binarize_alpha(img: Image.Image, cut: int = 128) -> Image.Image:
    """알파를 0 아니면 255 로. 도트 그림에 반투명은 없다."""
    img = img.convert("RGBA")
    r, g, b, a = img.split()
    a = a.point(lambda v: 255 if v >= cut else 0)
    return Image.merge("RGBA", (r, g, b, a))


# --------------------------------------------------------------------------
# 시트 패킹 — sprite_pipeline.md §1 「가로 1행 PNG, 프레임 간격 0」
# --------------------------------------------------------------------------
def pack_sheet(frames: list[Image.Image], size: int) -> Image.Image:
    sheet = Image.new("RGBA", (size * len(frames), size), (0, 0, 0, 0))
    for i, im in enumerate(frames):
        sheet.paste(im, (i * size, 0))
    return sheet


def sheet_name(unit: str, anim: str, size: int, n: int) -> str:
    return f"unit_{unit}_{anim}_{size}x{size}_{n}.png"


def fit_bottom(img: Image.Image, size: int) -> Image.Image:
    """정사각 칸에 **하단 정렬**로 앉힌다 — 발이 언제나 칸 밑변에 붙는다."""
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    if img.width > size or img.height > size:
        s = min(size / img.width, size / img.height)
        img = img.resize((max(1, int(img.width * s)), max(1, int(img.height * s))),
                         Image.NEAREST)
    canvas.paste(img, ((size - img.width) // 2, size - img.height))
    return canvas

# --------------------------------------------------------------------------
# ★★ 1도트 검은 테두리 — sprite_design.md §3 이 「이 화풍의 절반」이라 부른 것
#
# 실측(SDXL + PixelArtRedmond 다섯 장): 실루엣 가장자리 픽셀 중 어두운 것이
# **0.0 ~ 5.5%** 였다. 즉 테두리가 **없다.** 팔레트에 검정을 넣어 둬도 소용이 없다 —
# 없는 것을 팔레트가 지어내지는 못한다.
#
# 그래서 정제 단계에서 **그린다.** 이것은 눈속임이 아니라 도트 그림의 표준 공정이고,
# `sprite_design.md` 가 크기와 무관하게 살린다고 못 박은 넷 중 하나다(§3-1).
#
# ★ 안쪽 픽셀을 어둡게 칠하지 말고 **밖으로 한 겹 키운다.** 안쪽을 칠하면 96px 짜리
#   그림에서 눈 두 점(§5)이나 손 같은 두세 픽셀짜리 것이 통째로 먹힌다.
# ★ 반드시 **격자 축소 뒤에** 그린다. 축소 전에 그리면 8배로 줄면서 그 한 겹이
#   평균에 섞여 다시 사라진다 — 처음에 잃은 것과 똑같은 까닭이다.
# --------------------------------------------------------------------------
def add_outline(img: Image.Image, color: str = "#000000") -> Image.Image:
    """알파 실루엣 바깥으로 한 도트 테두리를 두른다."""
    img = img.convert("RGBA")
    w, h = img.size
    src = img.load()
    out = img.copy()
    dst = out.load()
    rgb = hex2rgb(color)
    for y in range(h):
        for x in range(w):
            if src[x, y][3]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and src[nx, ny][3]:
                    dst[x, y] = rgb + (255,)
                    break
    return out


def outline_ratio(img: Image.Image, thr: float = 0.22) -> float:
    """실루엣 가장자리 중 어두운 픽셀의 비율. 테두리가 살아 있는지의 잣대다."""
    img = img.convert("RGBA")
    w, h = img.size
    px = img.load()
    edge = dark = 0
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if not a:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if not (0 <= nx < w and 0 <= ny < h) or px[nx, ny][3] == 0:
                    edge += 1
                    if max(r, g, b) / 255.0 < thr:
                        dark += 1
                    break
    return dark / max(1, edge)


# --------------------------------------------------------------------------
# ★★ 「발이 선 줄」 — 알파 **아래끝**이 아니라 **몸**의 아래끝이다
#
# 왜 아래끝으로는 못 재는가: 알파 아래끝은 캐릭터에 **붙어 있지 않은 것**까지 센다.
#   실측(루그, art/anim/lugh): 아이들 0번 칸에만 왼쪽 아래에 부스러기가 몇 점 떠 있고
#   (몸은 x 187~324 인데 그 점들은 x 135~176 · 512칸 기준), 그것이 아래끝을 몸보다
#   **11px 아래**로 끌어내렸다. 아래끝으로 칸을 맞추면 부스러기에 몸을 맞추는 셈이 된다.
#   같은 함정이 아래로 늘어진 이펙트·옷자락에도 있다.
#
# 그래서 **가장 큰 이어진 덩어리**(= 몸)의 아래끝을 쓴다. 부스러기와 떨어져 나온
# 이펙트는 저마다 작은 덩어리라 자동으로 빠진다 — `autorig` 가 손 위 이펙트를
# 「색이 아니라 이어짐」으로 떼어 낸 것과 같은 잣대다(CLAUDE.md 4-1-1).
#
# ★ 4-이웃으로 잇는다. `add_outline` 이 두르는 이웃과 같아야, 테두리를 두른 뒤에
#   재도 덩어리가 갈라지지 않는다.
# --------------------------------------------------------------------------
def _blobs(img: "Image.Image"):
    """알파를 4-이웃으로 이어 덩어리를 매긴다. (줄마다 [x0, x1, 뿌리라벨] · 라벨→넓이)"""
    img = img.convert("RGBA")
    w, h = img.size
    a = img.split()[3].load()

    parent: list[int] = []

    def find(x: int) -> int:
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(x: int, y: int) -> None:
        rx, ry = find(x), find(y)
        if rx != ry:
            parent[ry] = rx

    rows: list[list[list[int]]] = []          # 줄마다 [x0, x1, 라벨]
    prev: list[list[int]] = []
    for y in range(h):
        runs: list[list[int]] = []
        x = 0
        while x < w:
            if a[x, y]:
                x0 = x
                while x < w and a[x, y]:
                    x += 1
                runs.append([x0, x, -1])
            else:
                x += 1
        for r in runs:
            lab = -1
            for p in prev:
                if p[0] < r[1] and r[0] < p[1]:      # 윗줄 조각과 가로로 겹친다
                    if lab < 0:
                        lab = find(p[2])
                    else:
                        union(lab, p[2])
            if lab < 0:
                lab = len(parent)
                parent.append(lab)
            r[2] = lab
        rows.append(runs)
        prev = runs

    size: dict[int, int] = {}
    for runs in rows:
        for r in runs:
            r[2] = find(r[2])
            size[r[2]] = size.get(r[2], 0) + (r[1] - r[0])
    return rows, size


def body_bottom(img: "Image.Image") -> int:
    """알파에서 **가장 큰 이어진 덩어리**의 아래끝(그 줄의 인덱스). 비었으면 -1."""
    rows, size = _blobs(img)
    if not size:
        return -1
    body = max(size, key=lambda k: size[k])
    bot = -1
    for y, runs in enumerate(rows):
        if any(lab == body for _x0, _x1, lab in runs):
            bot = y
    return bot


# --------------------------------------------------------------------------
# ★★ 「발이 선 줄」 둘째 자 — 덩어리의 맨 아랫줄이 아니라 **발자리를 덮는** 맨 아랫줄
#
# `body_bottom` 은 부스러기(떨어진 조각)는 걸러 내지만, **몸에 붙은 채 발 밑으로 내려간
# 소품**은 못 거른다 — 후려치는 채찍 끝, 부츠에 걸린 카드, 늘어진 살. H3 시범(2026-09-06)
# 에서 스노리의 채찍이 발 밑으로 내려갔고, `foot_shift` 가 그 칸의 **몸을 71px 밀어
# 올렸다**(채찍 끝을 발로 읽었다). 니브의 아이들에서는 부츠 옆에 떨어지는 카드가 그랬다.
# ★ 「가늘면 소품」으로는 못 가른다 — 96칸에서 채찍 링크가 5~9px, 카드가 8px 이라
#   부츠 밑창(8~12px)과 너비가 같다. 실측으로 그 자는 둘 다 못 걸렀다.
#
# 가르는 것은 **자리**다. 이 게임의 영웅은 걷지도 뛰지도 않으므로 발은 언제나 아이들
# 0번 칸(= 마스터, 모든 칸의 기준점)이 둔 자리에 있고, 발 밑으로 내려간 소품은 그
# 발자리(두 발의 x 구간)를 **안 덮는다** — 카드는 부츠 옆에, 채찍은 앞쪽에 떨어진다.
# 몸이 통째로 가라앉으면(시그리드) 두 발이 같이 내려가 발자리를 그대로 덮으므로 잡힌다.
# ★ 출고된 쉰 명 백 장에서 이 자와 `body_bottom` 은 같다(`python3 tools/sprite/pixels.py --feet`).
# --------------------------------------------------------------------------
def feet_runs(img: "Image.Image") -> list[tuple[int, int]]:
    """가장 큰 덩어리의 **맨 아랫줄에 있는 조각들** [(x0, x1)…]. 아이들 0번 칸에서 재면 발자리다."""
    rows, size = _blobs(img)
    if not size:
        return []
    body = max(size, key=lambda k: size[k])
    for y in range(len(rows) - 1, -1, -1):
        runs = [(x0, x1) for x0, x1, lab in rows[y] if lab == body]
        if runs:
            return runs
    return []


#: 발자리를 덮는 줄이 발로 세려면 그 위로 몇 줄이 더 차 있어야 하는가 (부츠의 높이 하한)
SOLID = 3


def feet_line(img: "Image.Image", ref: list[tuple[int, int]] | None = None,
              cover: float = 0.5) -> int:
    """발이 선 줄. `ref`(아이들 0번 칸의 `feet_runs`)의 발자리 하나를 `cover` 만큼 덮는
    가장 큰 덩어리의 **맨 아랫줄**. `ref` 가 없으면 `body_bottom` 과 같다. 비었으면 -1.

    ★ 발 **하나**만 덮어도 된다 — 찌르기(estoque)처럼 앞발이 크게 나가는 칸에서는 뒷발만
      제자리에 남는데, 그 뒷발이 곧 땅의 높이다.
    """
    if not ref:
        return body_bottom(img)
    rows, size = _blobs(img)
    if not size:
        return -1
    body = max(size, key=lambda k: size[k])

    def covers(y: int, rx0: int, rx1: int) -> bool:
        need = max(1, int(round((rx1 - rx0) * cover)))
        got = sum(max(0, min(x1, rx1) - max(x0, rx0))
                  for x0, x1, lab in rows[y] if lab == body)
        return got >= need

    for y in range(len(rows) - 1, -1, -1):
        if not any(lab == body for _a, _b, lab in rows[y]):
            continue
        for rx0, rx1 in ref:
            # ★ 발자리를 덮는 줄이 **위로 SOLID 만큼 이어져야** 발이다. 채찍처럼 두세 픽셀
            #   두께의 것이 부츠 **바로 밑을 가로지르면** 한 줄은 발자리를 덮는데, 그 위
            #   두세 줄은 비어 있다 — 부츠는 밑창 위로 발목까지 차 있다.
            if all(covers(yy, rx0, rx1) for yy in range(y, max(-1, y - SOLID - 1), -1)):
                return y
    return body_bottom(img)


if __name__ == "__main__":
    import sys as _sys
    _paths = _sys.argv[1:]
    if _paths[:1] == ["--feet"]:
        # 출고된 시트에서 두 발 자(body_bottom · feet_line)가 갈리는 칸을 찍는다
        import glob as _glob
        _diff = 0
        for _idle in sorted(_glob.glob("art/anim/*/*_idle.png")):
            _ref_sh = Image.open(_idle).convert("RGBA")
            _c = _ref_sh.height
            _ref = feet_runs(_ref_sh.crop((0, 0, _c, _c)))
            for _p in (_idle, _idle.replace("_idle.png", "_attack.png")):
                _sh = Image.open(_p).convert("RGBA")
                for _i in range(_sh.width // _c):
                    _f = _sh.crop((_i * _c, 0, (_i + 1) * _c, _c))
                    _a, _b = body_bottom(_f), feet_line(_f, _ref)
                    if _a != _b:
                        _diff += 1
                        print(f"  {_p} 칸 {_i}: body_bottom {_a} · feet_line {_b}")
        print(f"--feet: 갈린 칸 {_diff}")
        raise SystemExit(0)
    if not _paths:
        raise SystemExit("쓰는 법: python3 tools/sprite/pixels.py <프레임 PNG…>   (dekey selfcheck) · --feet")
    raise SystemExit(1 if selfcheck(_paths) else 0)
