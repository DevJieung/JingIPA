# 후보 C — 2·3·4단계. **덩어리로 짓되 원화에서 색과 텍스처를 가져온다.**
#
#   env -u DISPLAY bl -b --factory-startup --python tools/blender3d/cand_c/build.py -- --proj se
#
# 2단계 메시 · 3단계 리그 · 4단계 액션(idle 6 · attack 6)을 한 프로세스에서 만들고
# `build/b3d/cand_c/2_model/jokull.blend` 로 저장한다. 렌더는 render.py 가 한다.
#
# ---------------------------------------------------------------------------
# ★ 이 후보의 요점 — 원화(`jokull_hi.png`)를 3D 에 얹는다. 두 갈래를 **둘 다** 짓는다:
#     (1) `tex`  원화를 **비스듬한 평면 투영**으로 메시에 씌운다 (UV Project)
#     (2) `flat` 원화에서 **부위별 대표색**을 뽑아 재질에 배정한다 (텍스처 없음)
#   재질을 둘 다 만들어 두고 render.py 가 슬롯만 갈아 끼운다 — 메시·리그·액션이
#   **한 벌**이어야 두 갈래의 차이가 「재질」에서만 오기 때문이다.
#
# ★★ 투영 축을 왜 45도(SE)로 잡았는가.
#   원화는 **3/4 옆면**이다. 그림의 가로축은 캐릭터의 「폭(X)」과 「앞뒤(Y)」가
#   섞인 축이라, 정면(Y)으로도 옆면(X)으로도 투영하면 반드시 **한쪽이 눌린다.**
#   실측(몸통 상자 기준, 원화 몸통 폭 740px):
#       X 축 투영(옆) : 1194 px/m  (세로 564 px/m 의 2.1배 압축)
#       Y 축 투영(정면):  822 px/m  (1.46배)
#       SE 45도 투영  :  776 px/m  (**1.38배** — 가장 덜 눌린다)
#   그림이 3/4 니까 3/4 로 쏘는 것이 산수로도 맞다. 축은 `--proj` 로 바꿀 수 있다.
#
# ★ 칼과 카드는 **투영에서 뺐다.** 몸에서 1m 나가 있어 어떤 평면 투영에도 안 맞고,
#   대검의 대각선이 이 캐릭터 실루엣의 3분의 1을 지고 있어서 도박을 걸 자리가 아니다.
#
# ★★ **선 자세를 35도 비틀었다**(`TWIST`). 처음 판에서 배운 것이다 — spec 의
#   GAME_DIR 은 E(90도)라 **완전한 옆모습**이고, 옆모습에서는 「어깨가 넓은 거인」이
#   폭 14px 짜리 판때기가 된다. 게임의 정지 일러스트도 공식 시트도 전부 3/4 다.
#   그래서 발은 앞을 보게 두고 **상체만 카메라 쪽으로 35도 튼다** — 실제 검사가
#   그렇게 서고, E 에서 어깨 폭이 14px → 34px 이 된다.
# ---------------------------------------------------------------------------
import json
import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))     # tools/blender3d
import spec                                    # noqa: E402

OUT = os.path.join(spec.ROOT, "build", "b3d", "cand_c")
UNIT = "jokull"

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
PROJ_AXIS = "se"
for i, t in enumerate(argv):
    if t == "--proj" and i + 1 < len(argv):
        PROJ_AXIS = argv[i + 1]

TWIST = -35.0        # 상체를 카메라 쪽으로 트는 각(도)
LEG_TWIST = -12.0    # 다리는 조금만 (완전히 안 틀면 허리가 끊겨 보인다)

#: ★★ 가로로 **부풀린다**(비튼 뒤에 곱한다). 첫 판들이 전부 홀쭉했다 — 실측으로
#:   E 에서 몸+칼 폭이 51px 인데 공식 시트는 74px 이고 채움 비율이 0.23 대 0.44 였다.
#:   96px 칸에서 「거인」은 **키가 아니라 폭**으로 읽힌다. 키는 이미 74px 로 맞으니
#:   (공식 79px) 손댈 곳은 가로뿐이다. 로스터의 몸통 묘사도 "a huge
#:   broad-shouldered warrior" 라 이 방향이 맞다.
FAT_X, FAT_Y = 1.28, 1.22

# ---------------------------------------------------------------------------
# 재질 — 원화 실측색을 15색 팔레트 안으로 옮긴 것 (갈래 2)
#
# ★ 팔레트 밖으로 나가면 안 되므로 **팔레트 색을 그대로** 3톤씩 쓴다. 그래야
#   양자화가 아무것도 안 바꾸고, `tex` 갈래가 얼마나 잃는지를 **이것과 견줘서** 잰다.
# ★★ 96px 에서 실루엣 **안**을 읽게 하는 것은 색상이 아니라 **명도**다. 첫 판에서
#   털·판금·정강이가 전부 밝은 하늘색이라 사람이 한 덩어리 기둥으로 보였다.
#   지금은 세 층으로 갈라 뒀다: 수염(가장 밝다) > 후드·털 > 판금 > 다리·부츠 > 망토(검정).
# ---------------------------------------------------------------------------
TONES = {
    #            그늘        중간        빛           ← 원화 실측색
    "beard":   ("#6fb8e6", "#dff4ff", "#f4fcff"),   # #e8f8f0 수염·낙인 — 가장 밝다
    "fur":     ("#24568c", "#8fd0ef", "#dff4ff"),   # #98c0d8 후드·어깨 털
    "skin":    ("#7a5136", "#b9835a", "#eec49a"),   # #f0a890 살결 (후드 그늘 속이라 밝게)
    "plate":   ("#24568c", "#3f8fc9", "#6fb8e6"),   # #3080c8 파란 판금
    "deep":    ("#000000", "#24568c", "#3f8fc9"),   # #183088 부츠 — 가장 어둡다
    "cloak":   ("#000000", "#3a3740", "#3a3740"),   # #000010 검푸른 망토·장갑
    #   ★ 순검정 셋으로 두면 6단계가 두르는 1도트 테두리와 **한 덩어리**가 되어
    #     망토가 실루엣에서 사라진다. 중간·빛 톤을 #3a3740 으로 띄웠다.
    "teal":    ("#24568c", "#6fb8e6", "#b8e6f8"),   # #68d0d0 청록 겉옷 ← 램프에 청록이 없다
    "leather": ("#2b1a12", "#7a5136", "#b9835a"),   # #a05850 허리띠
    "blade":   ("#3f8fc9", "#b8e6f8", "#f4fcff"),   # 얼음 대검
    "metal":   ("#3a3740", "#8d8a95", "#ccc8d4"),   # 코등이·쇠붙이
    "eye":     ("#000000", "#000000", "#000000"),   # 눈 두 점
    "card":    ("#8d8a95", "#ccc8d4", "#f4fcff"),   # 손에 뜬 카드
}
MATS = list(TONES)                       # 슬롯 차례 (render.py 가 이 차례를 믿는다)
MI = {n: i for i, n in enumerate(MATS)}
#: `tex` 갈래에서 원화 텍스처로 갈아 끼울 슬롯 — 몸통뿐이다
BODY_SLOTS = ["beard", "fur", "skin", "plate", "deep", "cloak", "teal", "leather"]

RAMP_POS = (0.0, 0.36, 0.70)             # 툰 밴드 세 칸의 경계
#: ★ 경계를 0.30/0.62 에서 올렸다. 낮게 두면 **그늘 칸이 거의 안 생겨서** 96px 에서
#:   사람이 밝은 한 덩어리로 보인다 — 공식 시트는 어두운 몫이 3할쯤이다.

V: list[Vector] = []
F: list[tuple] = []
FM: list[int] = []
VG: list[str] = []

_BOX_F = ((0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1),
          (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0))

UPPER = {"hips", "spine", "head", "arm_R", "fore_R", "hand_R",
         "arm_L", "fore_L", "hand_L"}
#: ★ 칼은 **안 비튼다.** 상체를 35도 틀면 날까지 같이 돌아 화면 안쪽을 향하고,
#   E 에서 대검이 통째로 앞단축돼 사라진다 — 실측으로 몸 폭이 42px 밖에 안 나왔다
#   (공식 시트는 74px). 자루 자리는 **비튼 손**을 따라가고 날 방향만 그대로 둔다.


def tw(p, deg):
    """Z 축(발밑 원점) 둘레로 비튼다."""
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    x, y, z = p
    return Vector((x * c - y * s, x * s + y * c, z))


def twist_for(grp):
    if grp == "weapon":
        return 0.0
    return TWIST if grp in UPPER else LEG_TWIST


def fat(p):
    return Vector((p[0] * FAT_X, p[1] * FAT_Y, p[2]))


def _emit(pts, mat, grp):
    d = twist_for(grp)
    b = len(V)
    V.extend(fat(tw(p, d)) for p in pts)
    VG.extend([grp] * 8)
    for f in _BOX_F:
        F.append(tuple(b + i for i in f))
        FM.append(MI[mat])


def box(mat, grp, c, s, rot=None):
    hx, hy, hz = s[0] / 2, s[1] / 2, s[2] / 2
    loc = [Vector((x, y, z)) for x, y, z in
           ((-hx, -hy, -hz), (hx, -hy, -hz), (hx, hy, -hz), (-hx, hy, -hz),
            (-hx, -hy, hz), (hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz))]
    if rot:
        m = (Matrix.Rotation(math.radians(rot[0]), 3, 'X') @
             Matrix.Rotation(math.radians(rot[1]), 3, 'Y') @
             Matrix.Rotation(math.radians(rot[2]), 3, 'Z'))
        loc = [m @ p for p in loc]
    _emit([p + Vector(c) for p in loc], mat, grp)


def prism(mat, grp, p0, p1, w0, w1, t0, t1, nhint=(1, 0, 0)):
    """p0→p1 을 잇는 **끝이 가늘어지는** 상자. 팔다리와 칼날이 이걸로 만들어진다."""
    p0, p1 = Vector(p0), Vector(p1)
    a = (p1 - p0).normalized()
    n = Vector(nhint)
    n = (n - a * n.dot(a)).normalized()
    w = a.cross(n)
    pts = [p0 - w * w0 - n * t0, p0 + w * w0 - n * t0,
           p0 + w * w0 + n * t0, p0 - w * w0 + n * t0,
           p1 - w * w1 - n * t1, p1 + w * w1 - n * t1,
           p1 + w * w1 + n * t1, p1 - w * w1 + n * t1]
    _emit(pts, mat, grp)


# ---------------------------------------------------------------------------
# 2단계 — 몸.  모델은 **-Y 를 본다**. 모델의 오른쪽은 -X 이고, yaw 90(E)에서
# 그쪽이 카메라를 마주 본다 → **칼 든 오른손이 언제나 화면 앞**에 온다.
# ★ 1m = 40px 이므로 0.125m(5px) 미만짜리는 아예 안 만든다.
# ---------------------------------------------------------------------------
#: ★ 칼자루를 **높이** 잡고 날을 덜 기울였다. 낮게 잡으면 내려베는 칸에서 칼끝이
#:   발보다 아래로 내려가 칸 밖으로 잘린다(실측 5.4px). 「칼끝은 발 위, 손잡이는
#:   가슴 앞」이 96px 에서 벨 자리를 만드는 유일한 방법이다.
HAND_R = Vector((-0.20, -0.28, 1.00))
BLADE_D = Vector((-0.26, -0.94, -0.30)).normalized()
BLADE_L = 0.92


def _w(a: Vector) -> Vector:
    n = Vector((1, 0, 0))
    n = (n - a * n.dot(a)).normalized()
    return a.cross(n)


def build_body():
    # 발·다리 — 아래로 갈수록 어둡게. 실루엣의 밑동을 눌러 준다 ------------
    for sgn, sd in ((-1, "R"), (1, "L")):
        x = 0.145 * sgn
        box("deep", f"foot_{sd}", (x, -0.04, 0.075), (0.22, 0.32, 0.15))
        prism("plate", f"shin_{sd}", (x, 0, 0.47), (x, -0.01, 0.13),
              0.105, 0.095, 0.12, 0.11)
        prism("plate", f"thigh_{sd}", (x, 0, 0.78), (x, 0, 0.42),
              0.13, 0.11, 0.14, 0.12)
    # 허리 ---------------------------------------------------------------
    box("plate", "hips", (0, 0, 0.84), (0.46, 0.34, 0.24))
    box("leather", "hips", (0, 0, 0.925), (0.50, 0.38, 0.11))
    box("teal", "hips", (0, -0.175, 0.74), (0.36, 0.10, 0.44))    # 청록 겉옷
    # 몸통 — 어깨 털 밑으로 파란 판금이 9px 쯤 보이게 길게 -----------------
    box("plate", "spine", (0, 0, 1.10), (0.50, 0.36, 0.46))
    box("beard", "spine", (0, -0.195, 1.06), (0.16, 0.05, 0.16), rot=(0, 45, 0))  # 다이아 낙인
    # 망토 — 두껍고 넓게. 검정이라 실루엣의 뒤쪽 절반을 통째로 진다
    box("cloak", "spine", (0, 0.27, 0.86), (0.60, 0.17, 1.08))
    box("cloak", "spine", (0, 0.22, 1.26), (0.48, 0.20, 0.28))
    # 털 망토(어깨) — 「어깨가 넓다」를 지는 덩어리. 아래로 갈수록 좁아진다
    for sgn in (-1, 1):
        prism("fur", "spine", (0.30 * sgn, -0.01, 1.40), (0.24 * sgn, -0.01, 1.10),
              0.16, 0.12, 0.20, 0.15, nhint=(0, 1, 0))
    box("fur", "spine", (0, 0.02, 1.33), (0.42, 0.38, 0.24))   # 목까지 올려 붙인다
    # 목·머리 -------------------------------------------------------------
    box("skin", "head", (0, -0.04, 1.35), (0.17, 0.17, 0.10))
    box("skin", "head", (0, -0.075, 1.50), (0.24, 0.25, 0.24))
    box("cloak", "head", (0, -0.115, 1.598), (0.25, 0.21, 0.035))  # ★후드 그늘 — 눈썹 한 줄
    box("fur", "head", (0, 0.02, 1.665), (0.36, 0.39, 0.125))      # 후드 지붕
    for sgn in (-1, 1):
        box("fur", "head", (0.165 * sgn, 0.06, 1.52), (0.10, 0.34, 0.28))
    box("fur", "head", (0, 0.20, 1.53), (0.40, 0.15, 0.32))        # 후드 뒤
    # ★수염 — 가슴 **앞**으로 나와야 한다. 어깨 털 안에 묻히면 통째로 사라진다
    box("beard", "head", (0, -0.215, 1.23), (0.22, 0.20, 0.36))
    for sgn in (-1, 1):
        box("eye", "head", (0.095 * sgn, -0.205, 1.525), (0.07, 0.06, 0.05))
    # 오른팔(카메라 쪽) — 칼자루를 쥔다 ----------------------------------
    prism("plate", "arm_R", (-0.25, 0.0, 1.27), (-0.30, -0.05, 1.09),
          0.09, 0.08, 0.09, 0.08)
    prism("plate", "fore_R", (-0.30, -0.05, 1.09), (-0.21, -0.28, 1.01),
          0.08, 0.07, 0.08, 0.07)
    box("cloak", "hand_R", (-0.20, -0.30, 1.00), (0.14, 0.15, 0.14))
    # 왼팔 — 카드를 든 손을 앞·위로 (원화가 그렇다) ------------------------
    prism("plate", "arm_L", (0.25, 0.0, 1.24), (0.32, -0.14, 1.16),
          0.09, 0.08, 0.09, 0.08)
    prism("plate", "fore_L", (0.32, -0.14, 1.16), (0.20, -0.44, 1.26),
          0.08, 0.07, 0.08, 0.07)
    box("cloak", "hand_L", (0.18, -0.46, 1.28), (0.14, 0.14, 0.14))
    box("card", "hand_L", (0.16, -0.52, 1.39), (0.13, 0.03, 0.17), rot=(0, 0, 24))
    # 대검 — 자루는 **비튼 손**에, 날 방향은 안 비튼 채로 -------------------
    a = BLADE_D
    H = tw(HAND_R, TWIST)
    tip = H + a * BLADE_L
    mid = H + a * (BLADE_L - 0.15)
    prism("blade", "weapon", H + a * 0.06, mid, 0.115, 0.105, 0.028, 0.026)
    prism("blade", "weapon", mid, tip, 0.105, 0.014, 0.026, 0.010)
    prism("metal", "weapon", H + a * 0.06 - _w(a) * 0.19,
          H + a * 0.06 + _w(a) * 0.19, 0.04, 0.04, 0.04, 0.04)
    prism("leather", "weapon", H + a * 0.05, H - a * 0.20,
          0.042, 0.042, 0.042, 0.042)
    box("metal", "weapon", tuple(H - a * 0.24), (0.10, 0.10, 0.10))


# ---------------------------------------------------------------------------
# 3단계 — 리그. **강체 스키닝**(꼭짓점 하나 = 뼈 하나 · 웨이트 1.0).
# ★ 자동 웨이트를 안 쓴 까닭: 이 몸은 서로 떨어진 덩어리 서른몇 개라 자동 웨이트가
#   팔 덩어리에 몸통 뼈를 섞는다. 강체는 관절에 틈이 생기지만 덩어리를 겹쳐 두면
#   96px 에서 안 보이고, 무엇보다 **결과가 결정적**이다.
# ★ 허벅지의 부모가 hips 가 아니라 root 다. hips 를 내려 「가라앉는」 몸짓을 주는데
#   hips 밑에 다리가 달려 있으면 **발이 같이 떠서** 칸마다 발밑 y 가 흔들린다.
# ---------------------------------------------------------------------------
_B = [
    ("root",    (0, 0, 0),            (0, 0, 0.12),           None,      False, 0),
    ("hips",    (0, 0, 0.72),         (0, 0, 0.94),           "root",    False, TWIST),
    ("spine",   (0, 0, 0.94),         (0, 0, 1.32),           "hips",    True,  TWIST),
    ("head",    (0, 0, 1.32),         (0, 0, 1.68),           "spine",   True,  TWIST),
    ("arm_R",   (-0.25, 0, 1.27),     (-0.30, -0.05, 1.09),   "spine",   False, TWIST),
    ("fore_R",  (-0.30, -0.05, 1.09), (-0.21, -0.28, 1.01),   "arm_R",   True,  TWIST),
    ("hand_R",  (-0.21, -0.28, 1.01), (-0.20, -0.33, 0.98),   "fore_R",  True,  TWIST),
    ("weapon",  (-0.20, -0.28, 1.00), None,                   "hand_R",  False, TWIST),
    ("arm_L",   (0.25, 0, 1.24),      (0.32, -0.14, 1.16),    "spine",   False, TWIST),
    ("fore_L",  (0.32, -0.14, 1.16),  (0.20, -0.44, 1.26),    "arm_L",   True,  TWIST),
    ("hand_L",  (0.20, -0.44, 1.26),  (0.18, -0.49, 1.29),    "fore_L",  True,  TWIST),
    ("thigh_R", (-0.145, 0, 0.76),    (-0.145, 0, 0.42),      "root",    False, LEG_TWIST),
    ("shin_R",  (-0.145, 0, 0.42),    (-0.145, 0, 0.14),      "thigh_R", True,  LEG_TWIST),
    ("foot_R",  (-0.145, 0, 0.14),    (-0.145, -0.18, 0.06),  "shin_R",  True,  LEG_TWIST),
    ("thigh_L", (0.145, 0, 0.76),     (0.145, 0, 0.42),       "root",    False, LEG_TWIST),
    ("shin_L",  (0.145, 0, 0.42),     (0.145, 0, 0.14),       "thigh_L", True,  LEG_TWIST),
    ("foot_L",  (0.145, 0, 0.14),     (0.145, -0.18, 0.06),   "shin_L",  True,  LEG_TWIST),
]


def bone_list():
    out = []
    for name, h, t, par, con, d in _B:
        if name == "weapon":
            # 칼 뼈는 **비틀지 않는다** — 상체가 35도 돌아도 날은 화면 면에 남아야 한다
            hh = tw(HAND_R, TWIST)
            out.append((name, tuple(fat(hh)), tuple(fat(hh + BLADE_D * 0.35)), par, con))
        else:
            out.append((name, tuple(fat(tw(h, d))), tuple(fat(tw(t, d))), par, con))
    return out


# ---------------------------------------------------------------------------
# 4단계 — 액션.  ★ 자세를 **리그 공간의 축**으로 적는다 (`w` = (도 단위 x,y,z)).
#
#   왜: 뼈의 로컬 축은 뼈마다 다르고 이 몸은 상체가 35도 비틀려 있어서, 로컬로
#   적으면 「팔을 앞으로」가 뼈마다 다른 방향이 된다. 첫 판이 그래서 통째로
#   망가졌다(2번 칸에서 대검이 창처럼 앞으로 곧게 뻗었다).
#
#   ★★ **리그 공간이지 월드가 아니다.** 방향(yaw)은 리그 오브젝트를 통째로 돌려서
#   만드는데, `bone.matrix_local` 은 **리그 안쪽** 좌표라 그 회전을 안 본다.
#   E(yaw 90)에서 리그 축이 화면에 어떻게 앉는지가 이렇다:
#       리그 +X → 월드 +Y (화면 **안쪽**)  → **이 축 둘레의 회전이 화면 안의 호(弧)다**
#       리그 +Y → 월드 -X (화면 왼쪽)
#       리그 +Z → 월드 +Z (화면 위)
#   그래서 자세 표에서:
#       rx(+) = 화면 안에서 **아래·앞으로 휘두른다**   ← 내려베기가 이것이다
#       rz(+) = 몸을 카메라 쪽으로 더 튼다 (감았다 푸는 축)
#       loc z = 가라앉았다 솟는다
#   ☆ 한 판을 rx 대신 ry 로 적었다가 **칼끝이 아래가 아니라 위로 떠올랐다**
#     (실측: 공격 4·5칸에서 칼끝 화면 v 가 +0.20 → +0.71 → +0.86 으로 **올라갔다**).
#
# ★ idle 6칸(돈다) — 숨쉬기. 1m = 40px 이니 0.025m 가 1px. 그래서 0.02m 안쪽으로만.
# ★ attack 6칸(안 돈다 · 놓는 칸 = 0-based 3번 = 0004.png)
#   CLAUDE.md 18-5-2 「먼저 가라앉았다가 올라간다」 그대로:
#   1 준비 → 2 **가장 깊이 가라앉으며 감는다** → 3 올라온다 → 4 **닿는다** →
#   5 따라 나간다 → 6 되돌아온다.
# ★ CLAUDE.md 4-1-1: **slash 의 날을 머리 위로 치켜들게 하지 마라.** 그래서 감을 때
#   날은 「가슴 앞으로 당긴다」로만 한다 — 손을 뒤로 빼고(arm_R wy+) 날은 수평까지만
#   되돌린다(weapon wy-). 날 끝이 머리 높이를 넘지 않는다.
# ---------------------------------------------------------------------------
IDLE = [
    {},
    {"hips": {"loc": (0, 0, -0.008)}, "spine": (1.4, 0, 0), "head": (-1.0, 0, 0),
     "weapon": (-2, 0, 0)},
    {"hips": {"loc": (0, 0, -0.018)}, "spine": (2.4, 0, 0), "head": (-1.8, 0, 0),
     "arm_R": (-2, 0, 0), "arm_L": (2, 0, 0), "weapon": (-3.5, 0, 0)},
    {"hips": {"loc": (0, 0, -0.014)}, "spine": (1.8, 0, 0), "head": (-1.2, 0, 0),
     "arm_R": (-1, 0, 0), "weapon": (-2.5, 0, 0)},
    {"hips": {"loc": (0, 0, -0.004)}, "spine": (0.5, 0, 0), "head": (-0.2, 0, 0),
     "weapon": (-0.5, 0, 0)},
    {"hips": {"loc": (0, 0, 0.004)}, "spine": (-0.6, 0, 0), "head": (0.4, 0, 0),
     "weapon": (1, 0, 0)},
]
ATTACK = [
    # 1 준비 — 날을 조금 세우고 몸을 연다
    {"spine": (-3, 0, -3), "head": (-2, 0, -2), "arm_R": (-3, 0, 0),
     "weapon": (-9, 0, 0), "arm_L": (-4, 0, 0)},
    # 2 ★가장 깊이 가라앉으며 감는다 (날은 가슴 앞 수평까지만 — 머리 위로 안 올린다)
    {"hips": {"loc": (0, 0, -0.070), "w": (0, 0, -6)}, "spine": (-9, 0, -4),
     "head": (-5, 0, -3), "arm_R": (-8, 0, 0), "weapon": (-20, 0, 0),
     "arm_L": (-10, 0, 0)},
    # 3 올라오며 던지기 시작
    {"hips": {"loc": (0, 0, -0.020), "w": (0, 0, -2)}, "spine": (-1, 0, -1),
     "head": (0, 0, 0), "arm_R": (-1, 0, 0), "weapon": (-3, 0, 0),
     "arm_L": (-3, 0, 0)},
    # 4 ★닿는 칸 — 날이 앞·아래로 완전히 베어 나간다
    {"hips": {"loc": (0, 0, 0.020), "w": (0, 0, 6)}, "spine": (8, 0, 4),
     "head": (5, 0, 3), "arm_R": (5, 0, 0), "weapon": (19, 0, 0),
     "arm_L": (10, 0, 0)},
    # 5 따라 나간다
    {"hips": {"w": (0, 0, 8)}, "spine": (11, 0, 5), "head": (7, 0, 4),
     "arm_R": (6, 0, 0), "weapon": (27, 0, 0), "arm_L": (13, 0, 0)},
    # 6 되돌아온다
    {"spine": (4, 0, 2), "head": (2, 0, 1), "arm_R": (3, 0, 0),
     "weapon": (12, 0, 0), "arm_L": (5, 0, 0)},
]


# ---------------------------------------------------------------------------
def toon_nodes(nt, tones_lin, tex_img=None):
    """Diffuse → ShaderToRGB → ColorRamp(CONSTANT) → (곱) → Emission → Output.

    ★ EEVEE 전용이다. Cycles 에서는 Shader to RGB 가 **경고 한 줄 없이 무시**되어
      평평한 단색이 나온다 (앞 단계가 실측했다).
    ★ tex_img 가 있으면 밴드는 **밝기 사다리**가 되고 원화 색을 곱한다 — 그러면
      「원화가 이미 그려 둔 그림자」와 「3D 가 새로 만든 그림자」가 겹쳐 두 겹으로
      어두워진다. 그 몫을 갚으려고 밴드를 0.62/0.84/1.06 으로 **띄워** 잡았다.
    """
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    dif = nt.nodes.new("ShaderNodeBsdfDiffuse")
    dif.inputs["Color"].default_value = (1, 1, 1, 1)
    s2r = nt.nodes.new("ShaderNodeShaderToRGB")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = 'CONSTANT'
    cr = ramp.color_ramp
    cr.elements[0].position = RAMP_POS[0]
    cr.elements[1].position = RAMP_POS[1]
    e2 = cr.elements.new(RAMP_POS[2])
    emi = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(dif.outputs[0], s2r.inputs[0])
    nt.links.new(s2r.outputs[0], ramp.inputs[0])
    if tex_img is None:
        for el, t in zip((cr.elements[0], cr.elements[1], e2), tones_lin):
            el.color = tuple(t) + (1.0,)
        nt.links.new(ramp.outputs[0], emi.inputs[0])
    else:
        for el, g in zip((cr.elements[0], cr.elements[1], e2), (0.62, 0.84, 1.06)):
            el.color = (g, g, g, 1.0)
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = tex_img
        tex.interpolation = 'Linear'
        tex.extension = 'EXTEND'
        mul = nt.nodes.new("ShaderNodeMixRGB")
        mul.blend_type = 'MULTIPLY'
        mul.inputs[0].default_value = 1.0
        nt.links.new(tex.outputs[0], mul.inputs[1])
        nt.links.new(ramp.outputs[0], mul.inputs[2])
        nt.links.new(mul.outputs[0], emi.inputs[0])
    nt.links.new(emi.outputs[0], out.inputs["Surface"])


def make_materials():
    mats = []
    for n in MATS:
        m = bpy.data.materials.new("flat_" + n)
        m.use_nodes = True
        toon_nodes(m.node_tree, [spec.hex2linear(h) for h in TONES[n]])
        mats.append(m)
    img = bpy.data.images.load(os.path.join(OUT, "proj.png"))
    img.colorspace_settings.name = 'sRGB'
    img.use_fake_user = True
    tm = bpy.data.materials.new("tex_proj")
    tm.use_nodes = True
    # ★ 슬롯에 안 꽂힌 재질은 사용자가 0 이라 저장할 때 **조용히 사라진다**.
    #   render.py 가 갈아 끼울 때까지 살아 있어야 한다 (액션과 같은 함정이다).
    tm.use_fake_user = True
    toon_nodes(tm.node_tree, None, tex_img=img)
    return mats, tm


def proj_axis_vec(kind: str) -> Vector:
    """투영 카메라가 **바라보는** 방향. 모델은 -Y 를 본다."""
    return {"y":  Vector((0, 1, 0)),
            "x":  Vector((1, 0, 0)),
            "se": Vector((1, 1, 0)).normalized()}[kind]


def assign_uv(me, groups):
    """휴식 자세의 꼭짓점을 **비스듬한 평면**에 눌러 UV 를 만든다 (UV Project).

    ★ 세로(v)는 언제나 z 다 — 그래서 후드가 위, 부츠가 아래로 **반드시** 맞는다.
      가로(u)만 거짓말을 하는데, 이 화풍에서 정체성을 지는 것은 세로 띠 쪽이다.
    ★ 상자를 몸통 꼭짓점으로만 잰다. 칼(0.8m 밖)까지 넣으면 몸이 그림 구석으로 쭈그러든다.
    """
    A = proj_axis_vec(PROJ_AXIS)
    R = A.cross(Vector((0, 0, 1))).normalized()
    UP = Vector((0, 0, 1))
    body = [p for p, g in zip(V, groups) if g != "weapon"]
    rs = [p.dot(R) for p in body]
    r0, r1 = min(rs), max(rs)
    z0, z1 = min(p.z for p in body), max(p.z for p in body)
    U0, U1, V0, V1 = 0.04, 0.81, 0.0, 1.0     # 원화의 「몸통 띠」 (칼 쪽 끝을 뺀 자리)
    uv = me.uv_layers.new(name="proj")
    for poly in me.polygons:
        for li in poly.loop_indices:
            p = me.vertices[me.loops[li].vertex_index].co
            uv.data[li].uv = (
                U0 + (p.dot(R) - r0) / max(1e-6, r1 - r0) * (U1 - U0),
                V0 + (p.dot(UP) - z0) / max(1e-6, z1 - z0) * (V1 - V0))
    return {"axis": PROJ_AXIS, "r_span": round(r1 - r0, 4),
            "z_span": round(z1 - z0, 4),
            "px_per_m_u": round((U1 - U0) * 962 / max(1e-6, r1 - r0), 1),
            "px_per_m_v": round((V1 - V0) * 1009 / max(1e-6, z1 - z0), 1)}


def world_rot(pb, deg):
    """**리그 공간** 축 회전(도)을 그 뼈의 로컬 오일러로 옮긴다.

    ★ 뼈의 로컬 축은 뼈마다 다르다. 자세를 로컬로 적으면 「앞으로 휘두른다」가
      뼈마다 다른 방향이 되어, 첫 판에서 실제로 대검이 창처럼 앞으로 뻗었다.
    ★ 여기서 말하는 축은 **리그 오브젝트 안쪽** 축이다 — 방향(yaw)은 리그를
      통째로 돌려 만들므로 이 변환은 그 회전을 안 본다. E 에서 화면 안의 호는
      리그 +X 둘레다(액션 표 머리말).
    ★ 부모가 이미 돌아 있는 칸에서는 부모의 틀 위에 얹히므로 정확히 리그 축은
      아니다 — 그래도 「부모를 따라가며 그만큼 더」가 애니메이션에서 원하는 것이다.
    """
    Rw = (Matrix.Rotation(math.radians(deg[2]), 3, 'Z') @
          Matrix.Rotation(math.radians(deg[1]), 3, 'Y') @
          Matrix.Rotation(math.radians(deg[0]), 3, 'X'))
    M = pb.bone.matrix_local.to_3x3()
    return (M.inverted() @ Rw @ M).to_euler('XYZ')


def world_loc(pb, v):
    M = pb.bone.matrix_local.to_3x3()
    return M.inverted() @ Vector(v)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    vl = bpy.context.view_layer

    build_body()
    me = bpy.data.meshes.new("jokull")
    me.from_pydata([tuple(v) for v in V], [], F)
    me.validate()
    for i, f in enumerate(me.polygons):
        f.material_index = FM[i]
        f.use_smooth = False          # ★ 면마다 한 톤 — 도트에서 밴드가 또렷해진다
    ob = bpy.data.objects.new("jokull", me)
    sc.collection.objects.link(ob)

    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()

    mats, texmat = make_materials()
    for m in mats:
        me.materials.append(m)
    uvinfo = assign_uv(me, VG)

    ad = bpy.data.armatures.new("rig")
    arm = bpy.data.objects.new("rig", ad)
    sc.collection.objects.link(arm)
    vl.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    for name, h, t, par, con in bone_list():
        b = ad.edit_bones.new(name)
        b.head, b.tail = h, t
        if par:
            b.parent = ad.edit_bones[par]
            b.use_connect = con
    bpy.ops.object.mode_set(mode='OBJECT')

    for name in set(VG):
        ob.vertex_groups.new(name=name)
    for i, g in enumerate(VG):
        ob.vertex_groups[g].add([i], 1.0, 'REPLACE')
    ob.parent = arm
    ob.modifiers.new("Armature", 'ARMATURE').object = arm
    for pb in arm.pose.bones:
        pb.rotation_mode = 'XYZ'

    def make_action(name, poses, loop):
        act = bpy.data.actions.new(name)
        act.use_fake_user = True      # ★ 사용자 0 인 액션은 저장할 때 조용히 사라진다
        arm.animation_data_create()
        prev = arm.animation_data.action
        arm.animation_data.action = act
        keys = list(enumerate(poses, start=1))
        if loop:
            keys.append((len(poses) + 1, poses[0]))
        for fr, pose in keys:
            for pb in arm.pose.bones:
                d = pose.get(pb.name, ())
                if isinstance(d, dict):
                    pb.location = world_loc(pb, d.get("loc", (0, 0, 0)))
                    rot = d.get("w", (0, 0, 0))
                else:
                    pb.location = (0, 0, 0)
                    rot = d if d else (0, 0, 0)
                pb.rotation_euler = world_rot(pb, rot)
                pb.keyframe_insert("rotation_euler", frame=fr)
                pb.keyframe_insert("location", frame=fr)
        arm.animation_data.action = prev
        return act

    make_action("idle", IDLE, loop=True)
    make_action("attack", ATTACK, loop=False)

    os.makedirs(os.path.join(OUT, "2_model"), exist_ok=True)
    blend = os.path.join(OUT, "2_model", "jokull.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend)

    info = {"verts": len(me.vertices), "faces": len(me.polygons),
            "tris": sum(len(p.vertices) - 2 for p in me.polygons),
            "bones": len(ad.bones), "materials": MATS, "body_slots": BODY_SLOTS,
            "twist_deg": TWIST, "leg_twist_deg": LEG_TWIST,
            "actions": {a.name: len(a.fcurves) for a in bpy.data.actions},
            "uv": uvinfo, "blend": blend,
            "rest_bbox": {"x": [min(v.x for v in V), max(v.x for v in V)],
                          "y": [min(v.y for v in V), max(v.y for v in V)],
                          "z": [min(v.z for v in V), max(v.z for v in V)]}}
    with open(os.path.join(OUT, "build_report.json"), "w") as f:
        json.dump(info, f, ensure_ascii=False, indent=1)
    print("BUILD_JSON " + json.dumps(info, ensure_ascii=False))


main()
