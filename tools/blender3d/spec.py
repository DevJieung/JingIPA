#!/usr/bin/env python3
"""0단계 — **규격 한 곳.** 이 아래 모든 단계가 여기만 본다.

이것은 **테스트용 파이프라인**이다. 지금 게임이 쓰는 공식 길(`tools/sprite/`,
Wan 2.2 I2V 영상 → 도트 시트)은 한 줄도 안 건드린다. 여기는 전혀 다른 길 —
**Blender 로우폴리 3D → 리깅 → 애니메이션 → 직교 툰 렌더 → 팔레트 양자화 → 시트** —
를 캐릭터 한 명으로 0→7 단계 끝까지 돌려 보고 **무엇이 낫고 무엇이 못한가**를 재는 자다.

★ 규격을 한 파일에 몰아 두는 까닭은 `tools/sprite/pixels.py` 와 같다. 셀 크기·팔레트·
  프레임 수가 두 곳에 적히는 순간, 한 곳만 고치는 날 시트와 JSON 이 조용히 어긋난다.

---
## 왜 이 숫자인가

**셀 96x96** — 사용자가 준 스펙의 예시는 64x64 였지만 **96 으로 올렸다.** 게임의
`core/anim.gd` 가 읽는 시트가 96x96 이고(`docs/SPRITE.md`), 결과를 그대로 게임에 꽂아
**같은 자로** 견줘 보는 것이 이 테스트의 요점이기 때문이다. 64 로 뽑으면 "새 파이프라인이
더 뭉갠다"가 파이프라인 탓인지 해상도 탓인지 갈리지 않는다.

**팔레트 15색.** 사용자 스펙은 「16~32색」이었는데 **15로 내렸다.** 0→7 을 한 번 돌려 보고
스펙을 고치라는 것이 사용자의 지시였고, 여기가 첫 번째로 고친 자리다. 까닭 둘:
  1. 공식 파이프라인의 **품질 검사 2번**이 「팔레트 이탈 0개」를 요구한다. 그 팔레트가
     `pixels.palette_for(elem)` 15색이라, 24색으로 뽑으면 **설계상 반드시 실패**한다.
     같은 검사를 통과하지 못하는 결과는 견줄 자격이 없다.
  2. 더 큰 까닭 — **정지 일러스트 50장과 몬스터 25장이 그 15색의 결**이다. 새 시트만
     다른 팔레트를 쓰면 편성 판의 아이와 전투 화면의 아이가 다른 사람이 된다.
  ★ 24색 표(`EXTRA`)는 「재 봐야 아는 것」이라 남겨 뒀는데 **한 번도 쓸 자리가 없었다** —
    요쿨·솔라나의 시트 여섯 장이 전부 고유색 12~15 이고 팔레트 이탈 0이다. 안 쓴다.
  ★ 뒤 9색에 **순회색을 넣지 않았다.** `pixels.py` 가 비싸게 배운 것이 그것이다 —
    순회색은 양자화의 배수구라, 조금이라도 옅은 속성 색을 전부 빨아들인다.

**8방향** — 게임은 좌우 뒤집기 한 방향만 쓴다(`Balance.art_aim`). 그런데도 8을 뽑는 까닭은
이것이 **3D 길에만 있는 이점**이라서다. 공짜로 나오는 것(0.36초)을 안 뽑으면 두 길을
견주는 뜻이 없다. 게임 반입에는 **`SE`(3/4)** 한 방향만 쓴다 — `E`(순수 옆모습)는
얼굴이 원리적으로 사라져서 버렸다(아래 `GAME_DIR`).

**직교 · Filter Size 0 · Film Transparent** — 스펙 그대로. 필터를 0 으로 두면 렌더가
**픽셀 격자에 딱 떨어져** 반투명 가장자리가 안 생긴다. 그 반투명이 남으면 팔레트
양자화가 가장자리를 회색으로 갈아 버려서 1도트 검은 테두리가 뭉갠다.

**월드 1유닛 = 정수 픽셀** — `ORTHO_SCALE / CELL[0]` 이 픽셀당 월드 크기다. 캐릭터를
제자리에서 돌릴 때 발이 1px 씩 떨리는 것이 이 파이프라인의 고전적 함정이라, 카메라를
격자에 못 박고 **캐릭터가 아니라 발밑 원점**을 기준으로 돌린다.
"""
from __future__ import annotations

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
OUT = ROOT / "build" / "b3d"

# ---------------------------------------------------------------- 셀과 프레임

CELL = (96, 96)                 # 시트 한 칸 (게임의 core/anim.gd 와 같다)
FPS = 12                        # 공식 파이프라인(pixels.FPS)과 같게 둔다

#: 동작 목록. 사용자 스펙: idle 4~6 · walk 8 · attack 6
#:   hit  = 「놓는 칸」(공식 파이프라인의 hit_frame). 탄이 이 칸에서 떠난다.
#:          ★★ **0부터 센다** — 3 이면 **네 번째** 칸이다.
#:          (스펙 수정 7) 처음에는 「놓는 칸」이라고만 적어 두었는데 세 번째인지 네 번째인지가
#:          안 갈렸다. `pack.py` 도 `fixture.py` 도 0-based 로 읽고 있으니 사실은 정해져
#:          있었는데 글로만 없었다. `hit_ms == sum(ms[0:hit])` 가 이 해석에 매여 있다.
#:   loop = 이어 도는가
#: ★ 게임은 `walk` 를 안 쓴다(영웅은 성역에 서서 쏜다). 그래도 뽑는 까닭은 **발을 땅에
#:   붙이는 능력을 재는 자**라서다 — 강체 블록 리그는 walk 에서만 무릎이 굽고, 거기서
#:   발밑 흔들림이 계약(2px)을 넘는지가 갈린다(후보 A 는 3px 로 못 넘겼다).
ACTIONS = {
    "idle":   {"frames": 6, "loop": True,  "hit": None},
    "walk":   {"frames": 8, "loop": True,  "hit": None},
    "attack": {"frames": 6, "loop": False, "hit": 3},
}

# ---------------------------------------------------------------- 방향

#: 방향 8개. yaw 는 캐릭터를 Z 축으로 돌리는 각(도).
#:   S = 화면 앞쪽(카메라를 본다) · E = 오른쪽 옆모습 · N = 뒷모습
#: ★ 게임에 반입하는 것은 한 방향뿐이다 — 나머지는 3D 길의 이점을 보이는 자료다.
DIRS = {
    "S":  0,   "SE": 45,  "E":  90,  "NE": 135,
    "N":  180, "NW": 225, "W":  270, "SW": 315,
}

#: ★★ **스펙 수정 1 — 게임 방향을 `E`(순수 옆모습)에서 `SE`(3/4)로 바꿨다.**
#:
#: 처음에는 「공식 파이프라인이 옆모습을 쓰니까」로 E 를 잡았는데, 첫 판을 돌려 보니
#: **원리적으로 안 되는 값**이었다. yaw 90도에서는 얼굴 면의 법선이 시선축과 나란해서
#: 화면에 남는 것이 **모서리 한 줄**뿐이다 — 얼굴 판을 아무리 키워도 안 보인다.
#: (후보 B 가 다섯 판을 「얼굴이 없다」로 날린 뒤에야 알아냈고, 결국 목만 카메라 쪽으로
#:  36도 트는 2D 스프라이트의 속임수로 우회했다.)
#:
#: ★ 2D 원화는 이 함정에 안 걸린다. 화가가 「옆모습」이라고 적어도 눈·코를 앞으로
#:   당겨 그리기 때문이다 — 실제로 이 게임의 일러스트 쉰 장이 전부 「3/4 옆면」이다.
#:   3D 는 그 거짓말을 못 한다. 그러니 **처음부터 3/4 로 세우는 것이 맞다.**
#: ★ 좌우 뒤집기와 안 싸운다. 엔진은 `Balance.art_aim` 으로 그림을 통째로 뒤집는데,
#:   SE 를 뒤집으면 SW 라 여전히 카메라 쪽을 보는 3/4 다.
GAME_DIR = "SE"

# ---------------------------------------------------------------- 카메라

#: 캐릭터 키(월드 유닛 = m).
#:
#: ★★ **스펙 수정 3 — 1.70 은 틀린 값이었다. 2.15 로 올린다.**
#: 처음에는 「4~5등신 도트 캐릭터니까 사람보다 짧게」로 1.70 을 잡았는데, 그러면
#: 96칸에 담기는 몸높이가 **68px** 밖에 안 된다. 공식 파이프라인의 시트는 **79px** 을 쓴다.
#: 후보 A 가 이 값을 그대로 믿어 73px 로 끝났고, 칸을 덜 쓰면 그만큼 `scale` 이 커져서
#: (1.3836) **엔진이 더 늘려 그린다 = 도트가 더 뭉갠다.**
#: 2.15m 로 지으면 몸높이 **88px · scale 1.1477** 이다.
#: ☆ `ORTHO_SCALE` 을 조여도 같은 곳에 닿지만 그러면 감는 칸의 칼이 칸을 뚫는다 —
#:   **카메라를 조이지 말고 모델을 키워라.**
CHAR_H = 2.15

#: 직교 카메라가 담는 세로 길이(m). 96px 에 2.40m → **픽셀당 0.025m · 1m = 40px.**
#: 캐릭터 2.15m 는 86px 이 되고 위로 10px 이 남는다.
#: ★ 이 값을 **조이지 마라.** 몸을 키우고 싶으면 `CHAR_H` 를 올려라 — 카메라를 조이면
#:   감는 칸의 무기가 칸 좌우를 뚫는다(실측: 순수 옆모습에서 0.98m 짜리 대검이 7px 넘쳤다).
ORTHO_SCALE = 2.40
PX_PER_M = CELL[1] / ORTHO_SCALE        # = 40.0

#: 카메라 내림각(도). 0 이면 순수 옆모습, 45 면 탑다운.
#: ★ 게임의 일러스트가 「3/4 옆면」이라 그 결에 맞춘다. 이 값은 **스펙의 손잡이**라
#:   5단계에서 0/20/35 를 나란히 렌더해 눈으로 고른다.
ELEV = 20.0
CAM_DIST = 12.0                 # 직교라 거리는 잘림면만 정한다

#: ★ **스펙 수정 5 — 「발 줄」은 규격이다.** 렌더가 발밑을 칸의 몇 번째 줄에 앉히는가.
#: 구현마다 제 이름으로 들고 있었고(86 · 90 · 91) 값이 다르면 **같은 캐릭터가 구현마다
#: 다른 배율로 나온다**(몸높이가 달라지므로 `scale = unit_h / body_h` 가 달라진다).
#: 96 이 아니라 91 인 까닭: 6단계의 `add_outline` 이 실루엣 **바깥**으로 한 줄을 더 두르므로
#: 칸 밑변에 딱 붙여 놓으면 그 한 줄이 잘린다. 아래로 5줄을 비워 둔다.
FOOT_BOTTOM = 91

#: ★ **스펙 수정 6 — 가장 높은 덩어리는 회전축(y=0) 위에 두어라.**
#: 화면 세로가 `y·sin(ELEV) + z·cos(ELEV)` 라, 실루엣 꼭대기의 y 가 회전축에서 벗어난
#: 만큼 **방향마다 키가 바뀐다.** 실측: 후드 중심 y=0.115m 이면 8방향 키 편차 3px(검사 11번
#: 실패), y=0.02m 로 옮기면 2px(겨우 통과). 남은 2px 은 래스터화의 ±1px 이다.
#: ☆ 한 픽셀만 나빠지면 빨간 줄이 나는 자리다. ELEV 를 15도로 낮추면 여유가 생긴다.
TOP_ON_AXIS = True

#: ★ **스펙 수정 4 — 총구는 「무기의 몇 할 지점」이다.**
#: 이 규칙이 없어서 후보 A 는 「+x 로 제일 먼 알파 픽셀」(=칼끝)로 잡았고 `(38, -12)` 라는
#: 못 쓸 값이 나왔다 — 세로가 -12 면 `ns_check` 의 띠(몸높이의 0.30~1.30배 위)를 벗어나
#: 게임에서 탄이 무릎께에서 나간다. 무기 뼈의 55% 지점을 화면에 투영하면 `(+37, -46)`.
#: ★★ 같이 지킬 것: **놓는 칸의 무기는 화면에서 수평이어야 한다.**
#:   화면 세로가 `y·sin(ELEV)+z·cos(ELEV)` 라 **앞으로 1m 뻗을 때마다 13.7px 내려간다.**
#:   아래로 베어 내리는 자세를 놓는 칸으로 삼으면 총구가 띠 아래로 새어 나간다.
#:   ☆ 이것은 **3D 에만 있는 함정**이다 — 2D 영상 길에는 깊이 항이 없다.
MUZ_T = 0.55

# ---------------------------------------------------------------- 팔레트

#: 앞 15색 — `tools/sprite/pixels.py` 에서 **그대로** 가져왔다 (속성 램프 7 + 공용 8).
RAMP = {
    "fire":  ["#5c1a10", "#a32218", "#c04a1c", "#e0702a", "#f5943f", "#ffbf62", "#ffe6a8"],
    "elec":  ["#4a5c12", "#8fbf1c", "#c8ee2e", "#3a2a80", "#6d5ae0", "#a996ff", "#eae2ff"],
    "ice":   ["#24568c", "#3f8fc9", "#6fb8e6", "#8fd0ef", "#b8e6f8", "#dff4ff", "#f4fcff"],
    "water": ["#0d2b4a", "#12507a", "#1a86b0", "#1f8f78", "#35c0a8", "#6fdcc4", "#bff0e4"],
    "none":  ["#33302a", "#524d43", "#756f60", "#a89db2", "#dad3c3", "#e07ad8", "#5fd8e8"],
}
COMMON = ["#000000",
          "#2b1a12", "#7a5136", "#b9835a", "#eec49a",     # 살결 네 톤
          "#3a3740", "#8d8a95", "#ccc8d4"]                # 쇠·천 세 톤

#: 뒤 9색 — **3D 툰 전용 값 사다리.** 2D 원화는 화가가 중간 톤을 알아서 줄이지만,
#: 3D 는 면마다 명/암이 갈리므로 가죽·쇠·금에 각각 사다리가 필요하다.
#: ★ 순회색(S=0)은 하나도 안 넣었다 — 양자화의 배수구가 되기 때문이다.
EXTRA = [
    "#1a1420",                                  # 아웃라인 바로 위, 가장 깊은 그늘
    "#3d2b1f", "#6b4a2c", "#9c7346",            # 가죽 3톤
    "#2e3b52", "#69809c", "#b9cbe0",            # 쇠 3톤 (푸른 기)
    "#7a2f3a",                                  # 붉은 천 (속성과 무관한 액센트)
    "#d8b25a",                                  # 놋쇠·금
]

#: 기본은 `game15` — 공식 파이프라인과 **같은 15색**이라 품질 검사 1·2를 그대로 통과한다.
#:
#: ★★ **스펙 수정 2 — 「16~32색」이던 것을 15색으로 확정한다.**
#: 0단계에서는 「3D 툰은 면마다 명/암이 갈려 중간 톤을 더 쓸 것」이라 걱정해 24색을
#: 준비해 뒀는데, **한 번도 쓸 자리가 없었다.** 재질당 3톤 + 램프 문턱 두 개가 그것을
#: 원천 봉쇄한다 — 요쿨·솔라나의 시트 여섯 장이 전부 고유색 12~15 이고 이탈 0이다.
#: `EXTRA` 9색은 **안 쓴다**(지워도 되지만, 왜 안 쓰는지가 기록으로 남는 편이 낫다).
PALETTE_MODE = "game15"         # game15 | ext24(안 쓴다)

#: ★ **스펙 수정 8 — 툰 램프의 문턱은 규격이다.**
#: `Diffuse → ShaderToRGB → ColorRamp(CONSTANT)` 의 세 단이 어디서 갈리는가.
#: 이 셋이 **밝기 히스토그램을 공식 시트와 맞추는 유일한 손잡이**다 —
#: (0, 0.34, 0.72) → (0, 0.40, 0.86) 으로 옮기면서 밝은 픽셀 비율이 0.487 → 0.431 로
#: 내려와 공식(0.364)에 가까워졌고, 밝기 중앙값이 **0.549 = 공식과 정확히 같아졌다.**
#: 해·채움광 세기와 한 벌이라 같이 둔다.
RAMP_STOPS = (0.0, 0.40, 0.86)
SUN_POWER = 3.14
FILL_POWER = 0.42

#: ★ EEVEE 렌더 설정 — 하나라도 빠지면 도트가 망가진다(전부 실측으로 확인했다).
#:   filter_size 0        반투명 픽셀이 정확히 0개가 된다 (1.5 일 때 472개)
#:   dither_intensity 0   안 끄면 같은 밴드가 ±1 로 흩어져 고유색이 24 → 57
#:   taa_render_samples 1 이것이 있어야 툰이 정확히 3톤이다 (없으면 9색)
#:   view_transform Standard  기본 AgX 면 넣은 색과 찍히는 색이 다르다
#:   film_transparent True
EEVEE = {"filter_size": 0.0, "dither_intensity": 0.0, "taa_render_samples": 1,
         "view_transform": "Standard", "film_transparent": True}


def palette_for(elem: str, mode: str | None = None) -> list[str]:
    """그 속성이 쓰는 색. `game15` 는 램프 7 + 공용 8, `ext24` 는 거기에 3D 전용 9."""
    if elem not in RAMP:
        raise KeyError(f"모르는 속성: {elem} (가능: {', '.join(RAMP)})")
    mode = mode or PALETTE_MODE
    pal = RAMP[elem] + COMMON
    if mode == "ext24":
        pal = pal + EXTRA
    elif mode != "game15":
        raise KeyError(f"모르는 팔레트 모드: {mode}")
    return pal


# ---------------------------------------------------------------- 게임 쪽 자

def unit_h(tier_index: int) -> int:
    """등급마다의 그림 높이. `tools/gen_art.py` 와 **같은 식**이어야 한다.

    ★ 여기가 어긋나면 편성 판(정지 그림)과 전투 화면(클립)의 키가 달라진다.
    """
    return 96 + tier_index * 5


TIERS = ["high", "pair", "twopair", "trips", "straight",
         "flush", "fullhouse", "quads", "sflush", "royal"]


def roster_unit(uid: str) -> dict:
    """`tools/roster.json` 에서 그 캐릭터를 찾아 등급 번호까지 붙여 돌려준다."""
    data = json.loads((ROOT / "tools/roster.json").read_text())
    for ti, t in enumerate(data["tiers"]):
        for u in t["units"]:
            if u["id"] == uid:
                return dict(u, tier=t["tier"], tier_i=ti, unit_h=unit_h(ti))
    raise KeyError(f"로스터에 없는 캐릭터: {uid}")


def hex2rgb(h: str) -> tuple[int, int, int]:
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def srgb_to_linear(c: float) -> float:
    """Blender 의 재질 색은 **선형**이다. hex 를 그대로 넣으면 밝게 뜬다.

    ★ 이 변환이 없으면 렌더 결과가 팔레트보다 한 톤 밝은 곳에 앉아서, 양자화가
      의도한 칸이 아니라 **한 칸 위**로 접는다 — 3톤이 2톤이 되는 자리다.
    """
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex2linear(h: str) -> tuple[float, float, float]:
    return tuple(srgb_to_linear(v / 255.0) for v in hex2rgb(h))


# ---------------------------------------------------------------- 아웃라인

#: 1도트 검은 테두리 — `sprite_design.md` §3 이 「실루엣의 절반」이라 부른 것.
#: 렌더 단계(인버티드 헐)와 후처리 단계 둘 다에서 만들 수 있어 5단계에서 견준다.
OUTLINE = "#000000"
OUTLINE_PX = 1


# ---------------------------------------------------------------- 경로

def paths(uid: str) -> dict:
    """이 캐릭터의 산출물 자리. 단계마다 여기만 본다."""
    d = OUT / uid
    return {
        "root":    d,
        "ref":     d / "1_turnaround",     # 1단계 턴어라운드
        "blend":   d / "2_model",          # 2·3·4단계 .blend
        "frames":  d / "5_frames",         # 5단계 렌더 낱장
        "clean":   d / "6_clean",          # 6단계 양자화·정리
        "sheet":   d / "7_sheet",          # 7단계 시트 + JSON
        "qc":      d / "qc",               # 품질 검사 결과
    }


def write_palette_png(elem: str, path: Path, sw: int = 24,
                      mode: str | None = None) -> Path:
    """팔레트를 PNG 로 굽는다 (0단계 산출물). 한 칸 sw px, 8칸씩."""
    from PIL import Image, ImageDraw
    pal = palette_for(elem, mode)
    cols = 8
    rows = (len(pal) + cols - 1) // cols
    img = Image.new("RGB", (cols * sw, rows * sw), (24, 24, 28))
    dr = ImageDraw.Draw(img)
    for i, h in enumerate(pal):
        x, y = (i % cols) * sw, (i // cols) * sw
        dr.rectangle([x, y, x + sw - 1, y + sw - 1], fill=hex2rgb(h))
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)
    return path


def dump(uid: str, elem: str, mode: str | None = None) -> dict:
    """스펙을 JSON 으로 (다른 단계·문서가 읽는다)."""
    return {
        "cell": {"w": CELL[0], "h": CELL[1]},
        "fps": FPS,
        "actions": ACTIONS,
        "dirs": DIRS,
        "game_dir": GAME_DIR,
        "camera": {"ortho_scale": ORTHO_SCALE, "px_per_m": PX_PER_M,
                   "elev_deg": ELEV, "char_h_m": CHAR_H, "dist": CAM_DIST},
        "palette": palette_for(elem, mode),
        "palette_mode": mode or PALETTE_MODE,
        "outline": {"color": OUTLINE, "px": OUTLINE_PX},
        "unit": uid, "elem": elem,
    }


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(description="0단계 — 스펙과 팔레트 PNG")
    ap.add_argument("--unit", default="jokull")
    ap.add_argument("--palette", default=PALETTE_MODE, choices=["game15", "ext24"])
    a = ap.parse_args()
    u = roster_unit(a.unit)
    elem = u["elem"]
    p = paths(a.unit)
    p["root"].mkdir(parents=True, exist_ok=True)
    png = write_palette_png(elem, p["root"] / f"palette_{a.palette}.png", mode=a.palette)
    js = p["root"] / "spec.json"
    js.write_text(json.dumps(dump(a.unit, elem, a.palette), ensure_ascii=False, indent=1))
    print(f"{u['en']}({u['ko']}) · {u['tier']}({u['tier_i']}) · {elem} · {u['weapon']} · "
          f"그림 높이 {u['unit_h']}px · sc {u['sc']}")
    print(f"팔레트 {len(palette_for(elem, a.palette))}색({a.palette}) → {png}")
    print(f"스펙 → {js}")
    print(f"픽셀당 {ORTHO_SCALE / CELL[0]:.4f}m · 1m = {PX_PER_M:.1f}px · "
          f"캐릭터 {CHAR_H}m = {CHAR_H * PX_PER_M:.0f}px")
