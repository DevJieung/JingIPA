#!/usr/bin/env python3
"""마스터 한 장에서 프레임을 짠다 — ART.md 5·6·7.

★ 왜 AI 로 프레임을 여러 장 안 뽑는가
  `pixelart-pipeline-guide.md` §A-5 와 `pixelforge/README.md` §8 이 같은 말을 한다 —
  캐릭터 LoRA 없이 같은 시드로 포즈만 바꿔 뽑으면 프레임마다 **다른 사람**이 나온다.
  그래서 캐릭터는 **AI 마스터 한 장**이고, 프레임은 여기서 만든다.

★ 몸은 **정수 픽셀 변형만** 한다 (밀기 · 행 단위 기울이기 · 최근접 눌림).
  정수·최근접이라 새 색이 한 개도 안 생긴다.

★ **시트를 다시 양자화하지 않는다.** 마스터 색을 그대로 두고 램프 색만 더한다.
  처음에 시트 전체를 MEDIANCUT 으로 밀어 넣었더니 붉은 옷이 갈색으로 탁해졌다.

    python3 tools/anim/mkanim.py frost_queen --src build/frost_queen
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from fx import Fx          # noqa: E402
from rig import Rig, blit  # noqa: E402

# 몸에 얹는 빛의 세기별 램프 인덱스 (셀수록 낮은 인덱스 = 밝다)
LIT = [3, 2, 1]

# --------------------------------------------------------------------------- #
# 프레임 표 — 10 칸, 합 0.405초
#
# ★ 손 목표를 **마스터 픽셀로 적지 마라.** 캐릭터가 바뀔 때마다 열 줄을 다시 재야 하고,
#   무엇보다 0 번 칸이 마스터와 1px 이라도 어긋나면 아이들이 정지 그림과 달라진다.
#   네 가지로 적는다:
#
#     ("rest",)                제자리 — **손도 안 대는** 원본 그대로. 0·9 번과 아이들이 쓴다.
#     ("arm", 각도차°, 길이배수) 제자리에서 각도차만큼 돌린다. 음수가 위쪽이다.
#     ("toward", 길이배수, 각도차°) **소품 쪽으로** 그만큼 뻗는다.
#     ("prop", dx, dy)         소품 잡은 자리에 손을 댄다.
#
# ★ ("toward") 가 있는 이유 — 서리여왕은 팔이 짧아 홀에 **손이 안 닿는다**
#   (어깨~홀 50px, 팔 25px). ("prop") 로 적으면 늘이기 한계(±35%)에 걸려 손이 허공에
#   멈추고, 그 자리가 프레임마다 달라 떨린다. 홀 **쪽으로** 뻗고 성엣가루가 홀에서
#   손으로 흐르게 하면 "홀에서 뽑아 온다"가 똑같이 읽힌다.
#
# ★ 가장 짧은 칸(20ms)이 **놓는 순간**이다. 눈은 제일 짧은 프레임을 타격으로 읽는다.
#   균등하게 나누면 언제 쐈는지가 안 읽힌다.
# ★ 8칸 0.26초짜리 앞 판은 **몸통만 통째로 밀렸다.** 팔이 안 움직이니 아이들에서
#   미끄러진 것으로만 보였다. 왕복이 0.26초에 안 들어가서 0.405초로 늘렸다.
#   (급하면 1·8 번 칸을 뺀다. 그 둘이 되돌아오는 칸이다 → 0.32초)
#
#   dx,dy 몸통 밀기 · k 기울기 · hand 손 목표 · orb 손 안 이펙트 반지름
#   glow 소품 결정 밝기 · flash 터짐 · shot (앞으로 px, 반지름) · trail 잔상 칸 수
# --------------------------------------------------------------------------- #
MOTIONS = {}
IDLES = {}

# --------------------------------------------------------------------------- #
# 「cast」 — 마법사. 손에 모아서 **손에서** 던진다.
# --------------------------------------------------------------------------- #
MOTIONS["cast"] = [
    dict(ms=45, dx=0,  dy=0,  k=+0.000, hand=("rest",),             orb=4.2, glow=0.10, flash=0.0, shot=None),
    dict(ms=45, dx=-2, dy=0,  k=-0.020, hand=("arm", 54.3, 0.68),   orb=2.6, glow=0.40, flash=0.0, shot=None),
    dict(ms=50, dx=-4, dy=1,  k=-0.045, hand=("toward", 1.00, -14), orb=2.8, glow=0.80, flash=0.0, shot=None),
    dict(ms=55, dx=-5, dy=1,  k=-0.060, hand=("toward", 1.25, -12), orb=5.0, glow=1.00, flash=0.0, shot=None),
    dict(ms=45, dx=-5, dy=1,  k=-0.055, hand=("toward", 1.18, -30), orb=7.2, glow=0.85, flash=0.0, shot=None),
    dict(ms=25, dx=1,  dy=-1, k=+0.020, hand=("arm", -68.0, 0.72),  orb=7.6, glow=0.45, flash=0.0, shot=None, trail=3),
    dict(ms=20, dx=6,  dy=-1, k=+0.075, hand=("arm", -25.7, 1.07), orb=0.0, glow=0.25, flash=1.00, shot=(9, 7.0), trail=3),
    dict(ms=30, dx=5,  dy=0,  k=+0.055, hand=("arm",  -8.7, 1.24), orb=0.0, glow=0.15, flash=0.40, shot=(27, 6.2)),
    dict(ms=40, dx=2,  dy=0,  k=+0.020, hand=("arm",  -1.7, 1.09), orb=0.0, glow=0.10, flash=0.10, shot=(45, 5.2)),
    dict(ms=50, dx=0,  dy=0,  k=-0.008, hand=("rest",),             orb=4.0, glow=0.10, flash=0.0, shot=None),
]

# --------------------------------------------------------------------------- #
# 「draw」 — 궁수. **만작으로 겨누고 있다가 놓는다.**
#
# ★ 마스터가 이미 만작이다. 그래서 「당기는」 대목이 앞에 없고 겨눔 → 놓음 → 되돌림이다.
#   만작으로 뽑은 것은 골라서 그런 것이 아니라 **아홉 장이 다 그랬다** — 활을 앞으로
#   내밀라고 적으면 모델은 늘 만작을 그린다. 그리고 그게 정지 스프라이트로도 제일 좋다:
#   활을 든 사람이 무엇을 하는 중인지가 한 장에서 읽힌다.
#
# ★ 마법사와 뜻이 뒤집힌 곳이 셋이다.
#   (1) **총구가 소품이다** (`--muzzle prop`). 터짐과 날아가는 살을 손에 두면 만작에서
#       손이 뺨 옆이므로 화살이 **얼굴에서** 나간다. 활을 든 뜻이 통째로 사라진다.
#   (2) **손과 소품을 잇는 것이 살이다** (`--link shaft`). 마법사의 흔들리는 부스러기
#       줄기는 「소품에서 뽑아 온다」인데, 살은 **뻣뻣한 막대**다. 흔들리면 살이 아니다.
#       그 살이 4~6 번 칸에서 **사라지는 것**이 이 동작에서 제일 크게 읽히는 사건이다.
#   (3) **팔이 짧다.** 만작이라 어깨~손이 10px 뿐이다(마법사는 34px). 길이로는 아무것도
#       못 보여 준다. 대신 **팔꿈치가 어깨에서 27px** 이라 각도가 잘 듣는다 — 놓는 칸에서
#       24도를 돌리면 손은 4px, 팔꿈치는 11px 간다. 그래서 길이가 아니라 각도로 짠 표다.
#
# ★ 가장 짧은 칸(20ms)이 놓는 순간이다. 그 앞 40ms 칸이 「숨 멈춤」이다 —
#   60·40 으로 끌다가 20 으로 떨어뜨려야 **탕** 하고 놓은 것으로 읽힌다. 합 0.405초.
#   shaft=True 인 칸에만 살을 긋는다 (메겨 있을 때만). ★ 놓은 뒤 **7 번 칸은 비워 둔다** —
#   6→7 에서 살이 되살아나면 「쐈는데 그대로 있다」로 보인다. 8 번에서 다시 메긴다.
# ★ 살을 6·26·46px 까지만 보낸다. 32·58 로 보내 봤더니 칸이 234px 로 부풀었다(정지 그림은
#   90px 이다). 게임은 탄을 코드로 그리므로(`battle_screen._draw_bullets`) 칸 안의 살은
#   **놓았다는 표시**일 뿐이고, 멀리 보낼수록 빈 칸만 넓어진다.
#
# ★ **모으는 것은 손이 아니라 살촉 쪽(활)이다** — orb 를 작게, glow 를 크게 잡은 까닭이다.
#   처음엔 마법사처럼 손에 크게 모았는데(orb 7.4), 만작에서 손이 뺨 옆이라 그 덩이가
#   **얼굴을 통째로 가렸다.** 서리여왕에서 겪은 그 흠(홀 쪽으로 손을 내린 칸에서 얼음이
#   얼굴 위에 얹힌 것)이 궁수에서는 **가장 세게 모으는 칸마다** 나온다.
#   힘이 살촉에 모였다가 활에서 터져 나가는 쪽이 뜻도 맞다 — 손에 모으면 「손에서
#   쏘는 사람」이 된다. 손에는 시위를 문 불꽃만 조금 남긴다.
# --------------------------------------------------------------------------- #
MOTIONS["draw"] = [
    dict(ms=45, dx=0,  dy=0,  k=+0.000, hand=("rest",),             orb=2.0, glow=0.16, flash=0.0, shot=None, shaft=True),
    dict(ms=50, dx=-1, dy=0,  k=-0.012, hand=("arm",  -4.0, 1.04),  orb=2.6, glow=0.46, flash=0.0, shot=None, shaft=True),
    dict(ms=60, dx=-2, dy=0,  k=-0.028, hand=("arm",  -7.0, 1.10),  orb=3.0, glow=0.76, flash=0.0, shot=None, shaft=True),
    dict(ms=40, dx=-2, dy=1,  k=-0.034, hand=("arm",  -9.0, 1.13),  orb=3.4, glow=1.00, flash=0.0, shot=None, shaft=True),
    dict(ms=20, dx=3,  dy=-1, k=+0.048, hand=("arm", -24.0, 1.30),  orb=0.0, glow=0.50, flash=1.00, shot=(6, 7.0), trail=3),
    dict(ms=30, dx=4,  dy=0,  k=+0.052, hand=("arm", -30.0, 1.34),  orb=0.0, glow=0.24, flash=0.35, shot=(26, 6.2)),
    dict(ms=35, dx=2,  dy=0,  k=+0.026, hand=("arm", -16.0, 1.20),  orb=0.0, glow=0.15, flash=0.10, shot=(46, 5.2)),
    dict(ms=45, dx=0,  dy=0,  k=+0.006, hand=("arm",  -6.0, 1.08),  orb=0.0, glow=0.20, flash=0.0, shot=None),
    dict(ms=40, dx=-1, dy=0,  k=-0.006, hand=("arm",  -2.0, 1.02),  orb=1.7, glow=0.17, flash=0.0, shot=None, shaft=True),
    dict(ms=40, dx=0,  dy=0,  k=-0.004, hand=("rest",),             orb=2.0, glow=0.14, flash=0.0, shot=None, shaft=True),
]

# --------------------------------------------------------------------------- #
# 「raise」 — **광역 마법.** 두 팔을 들어 지정한 자리에 장판을 깐다.
#
# 사용자가 정한 연출이다: 「광역마법같은경우는 굳이 캐릭터에서 바로 샷이 나갈 필요없고
# 약간 두팔을 들어올림과 동시에 발밑에서 머리위로 이펙트가 지나가고, 그게 특정 area 에
# 특정범위를 가진 애니메이션을 생성하고」.
#
# ★ 앞의 둘과 뜻이 갈라지는 곳이 셋이다.
#   (1) **shot 이 전부 None 이다.** 캐릭터에서 탄이 안 나간다 — 장판은 저 멀리 깔린다.
#       여기에 shot 을 넣으면 「쏘고 나서 딴 데도 터지는」 것이 되어 규칙이 흐려진다.
#   (2) **먼저 가라앉았다가 올라간다**(dy: 0 → +3 → -2). 힘을 모으는 몸짓은 위로
#       뻗기 전에 **아래로 눌리는** 것으로만 읽힌다. 이것이 없으면 팔만 까딱한다.
#   (3) **발밑에서 머리 위로 지나가는 이펙트는 클립에 안 넣는다.** 게임이 그린다
#       (`Fx.rise`, battle_screen 의 aim 갈래). 까닭이 둘이다 — 그 파동은 **속성 색**을
#       타야 하는데 클립은 팔레트가 구워져 있고, 크기가 **그려지는 키**(성역에 몇이
#       섰느냐로 달라진다)에 맞아야 하는데 클립은 크기가 고정이다.
#
# ★ 가장 짧은 칸(20ms)이 **자리를 정하는 순간**이다. 그 앞 55ms 칸이 「숨 멈춤」이고,
#   눈은 제일 짧은 프레임을 사건으로 읽는다(CLAUDE.md 18-4). 합 0.445초 —
#   BULLET["zone"]["cast"] 0.34 보다 길므로 전투의 바닥값이 아니라 이 값이 쓰인다.
# --------------------------------------------------------------------------- #
MOTIONS["raise"] = [
    dict(ms=45, dx=0,  dy=0,  k=+0.000, hand=("rest",),            orb=3.4, glow=0.10, flash=0.0, shot=None),
    dict(ms=50, dx=0,  dy=2,  k=-0.010, hand=("arm",  14.0, 0.90), orb=4.0, glow=0.30, flash=0.0, shot=None),
    dict(ms=55, dx=-1, dy=3,  k=-0.018, hand=("arm",  22.0, 0.86), orb=5.0, glow=0.55, flash=0.0, shot=None),
    dict(ms=50, dx=-1, dy=1,  k=-0.010, hand=("arm", -28.0, 1.02), orb=6.0, glow=0.75, flash=0.0, shot=None),
    dict(ms=45, dx=0,  dy=-1, k=+0.006, hand=("arm", -62.0, 1.14), orb=7.0, glow=0.92, flash=0.0, shot=None, trail=3),
    dict(ms=55, dx=0,  dy=-2, k=+0.010, hand=("arm", -88.0, 1.22), orb=8.2, glow=1.00, flash=0.0, shot=None, trail=3),
    dict(ms=20, dx=0,  dy=-2, k=+0.014, hand=("arm", -96.0, 1.26), orb=3.0, glow=0.60, flash=1.00, shot=None, trail=3),
    dict(ms=35, dx=0,  dy=-1, k=+0.008, hand=("arm", -80.0, 1.18), orb=1.4, glow=0.30, flash=0.35, shot=None),
    dict(ms=45, dx=0,  dy=0,  k=+0.002, hand=("arm", -40.0, 1.06), orb=2.2, glow=0.16, flash=0.08, shot=None),
    dict(ms=45, dx=0,  dy=0,  k=-0.004, hand=("rest",),            orb=3.2, glow=0.10, flash=0.0, shot=None),
]

# 장판 시전자의 숨쉬기 — 손을 낮게 든 채 천천히 오르내린다.
IDLES["raise"] = [
    dict(ms=170, dy=0, hand=("rest",),            glow=0.10, orb=3.4),
    dict(ms=170, dy=-1, hand=("arm", -8.0, 1.04), glow=0.24, orb=4.0),
    dict(ms=170, dy=0, hand=("rest",),            glow=0.16, orb=3.6),
    dict(ms=170, dy=1, hand=("arm",  4.0, 0.98),  glow=0.10, orb=3.1),
]


# 숨쉬기 넷. 발은 붙어 있고 몸만 1px 뜬다. 손은 0 번 칸 자세 그대로 —
# ★ **정지 스프라이트와 같은 자세**여야 한다. 게임이 정지 그림을 쓰는 화면(편성 판 ·
#   확정 연출)과 전투 화면이 다른 사람으로 보이면 안 된다.
IDLES["cast"] = [
    dict(ms=160, dy=0, hand=("rest",),           glow=0.10, orb=4.2),
    dict(ms=160, dy=0, hand=("arm", -1.7, 1.00), glow=0.22, orb=4.8),
    dict(ms=160, dy=0, hand=("rest",),           glow=0.14, orb=4.4),
    dict(ms=160, dy=1, hand=("arm",  1.8, 0.97), glow=0.10, orb=3.9),
]

# 궁수의 숨쉬기 — **만작을 문 채** 떤다. 정지 그림이 그 자세이기 때문이다.
IDLES["draw"] = [
    dict(ms=160, dy=0, hand=("rest",),            glow=0.16, orb=2.0),
    dict(ms=160, dy=0, hand=("arm", -2.0, 1.03),  glow=0.30, orb=2.5),
    dict(ms=160, dy=0, hand=("rest",),            glow=0.22, orb=2.2),
    dict(ms=160, dy=1, hand=("arm",  1.0, 0.99),  glow=0.14, orb=1.8),
]


# =========================================================================== #
# ★★ **결(variant) — 무리 하나에 동작 셋** (사용자가 정한 것: 「모션도 좀 너무
#    일관적인데 다양하게 나올 수 있도록」).
#
#    여든 명이 `cast` 36 · `raise` 16 · `draw` 21 · (thrown 은 cast) 7 로 나뉘어,
#    **서른여섯 명이 한 프레임도 안 다른 같은 동작**으로 싸우고 있었다. 성역에 여섯이
#    서면 그중 셋이 같은 팔을 같은 박자로 뻗는다.
#
# ★ **무리는 못 바꾼다 — 결만 바꾼다.** 무리(cast·draw·raise)는 무기와 방식이 정하고
#   (`gen_art.pose_family`), 거기에 `autorig` 의 팔 찾기 · `muzzle`(탄이 손에서 나가나
#   소품에서 나가나) · 정지 그림의 자세가 전부 매여 있다. 결이 바꾸는 것은 **칸마다의
#   시간과 팔 각도와 몸통 눌림**뿐이다.
#
# ★ 결마다 반드시 지킬 것 셋:
#     1. **가장 짧은 칸이 놓는 칸이다**(CLAUDE.md 18-4). `hit_i` 를 그렇게 뽑으므로,
#        짧은 칸을 두 개 두면 앞의 것이 놓는 칸이 되어 탄이 일찍 나간다.
#     2. **`raise` 는 `shot` 이 전부 None 이다.** 캐릭터에서 탄이 나가면 장판의 뜻이
#        깨진다 — 장판은 저 멀리 깔린다(CLAUDE.md 18-5-2).
#     3. **`draw` 는 무는 칸에 `shaft=True`.** 안 적으면 만작인데 살이 없다.
#
# ★ 총 길이를 크게 늘리지 마라. 놓는 칸까지의 시간이 곧 `wind`(총구 지연)이고,
#   `Balance.windup` 이 쿨다운의 0.72배로 자른다 — 넘으면 화면이 클립을 빨리 돌려
#   맞추므로 동작이 부자연스럽게 빨라진다.
# =========================================================================== #

# --- cast 의 결 둘 ---------------------------------------------------------- #
# 「내지르기」 — 앞발로 크게 파고들며 지른다. 되감기가 깊고(-9) 뻗음이 멀다(1.34).
MOTIONS["cast_lunge"] = [
    dict(ms=50, dx=0,  dy=0,  k=+0.000, hand=("rest",),             orb=3.8, glow=0.10, flash=0.0, shot=None),
    dict(ms=55, dx=-3, dy=1,  k=-0.038, hand=("arm",  72.0, 0.60),  orb=2.4, glow=0.42, flash=0.0, shot=None),
    dict(ms=60, dx=-6, dy=2,  k=-0.072, hand=("arm",  88.0, 0.52),  orb=3.2, glow=0.82, flash=0.0, shot=None),
    dict(ms=55, dx=-7, dy=2,  k=-0.086, hand=("toward", 1.30, -18), orb=6.4, glow=1.00, flash=0.0, shot=None),
    dict(ms=40, dx=-4, dy=1,  k=-0.052, hand=("arm", -46.0, 0.80),  orb=8.0, glow=0.80, flash=0.0, shot=None, trail=3),
    dict(ms=25, dx=4,  dy=-2, k=+0.062, hand=("arm", -58.0, 0.90),  orb=8.4, glow=0.42, flash=0.0, shot=None, trail=4),
    dict(ms=20, dx=9,  dy=-2, k=+0.104, hand=("arm", -20.0, 1.34),  orb=0.0, glow=0.22, flash=1.00, shot=(9, 7.4), trail=4),
    dict(ms=30, dx=7,  dy=-1, k=+0.078, hand=("arm",  -6.0, 1.30),  orb=0.0, glow=0.14, flash=0.40, shot=(28, 6.4)),
    dict(ms=45, dx=3,  dy=0,  k=+0.030, hand=("arm",   0.0, 1.12),  orb=0.0, glow=0.10, flash=0.10, shot=(47, 5.2)),
    dict(ms=55, dx=0,  dy=0,  k=-0.010, hand=("rest",),             orb=3.6, glow=0.10, flash=0.0, shot=None),
]

# 「후려치기」 — 반대쪽에서 몸을 가로질러 훑고 나간다. 되감기가 **몸 뒤**(126도)라
# 실루엣이 크게 열렸다 닫힌다. 잔상(trail)이 길어서 호가 눈에 남는다.
MOTIONS["cast_sweep"] = [
    dict(ms=45, dx=0,  dy=0,  k=+0.000, hand=("rest",),             orb=4.0, glow=0.10, flash=0.0, shot=None),
    dict(ms=50, dx=2,  dy=0,  k=+0.024, hand=("arm", 126.0, 0.72),  orb=3.0, glow=0.36, flash=0.0, shot=None),
    dict(ms=60, dx=4,  dy=1,  k=+0.046, hand=("arm", 148.0, 0.86),  orb=5.2, glow=0.74, flash=0.0, shot=None),
    dict(ms=50, dx=3,  dy=1,  k=+0.034, hand=("arm", 160.0, 0.92),  orb=7.4, glow=1.00, flash=0.0, shot=None),
    dict(ms=35, dx=0,  dy=0,  k=-0.014, hand=("arm",  96.0, 0.98),  orb=7.8, glow=0.76, flash=0.0, shot=None, trail=5),
    dict(ms=30, dx=-3, dy=-1, k=-0.046, hand=("arm",  30.0, 1.12),  orb=7.2, glow=0.44, flash=0.0, shot=None, trail=5),
    dict(ms=20, dx=-5, dy=-1, k=-0.062, hand=("arm", -22.0, 1.26),  orb=0.0, glow=0.22, flash=1.00, shot=(9, 7.0), trail=5),
    dict(ms=35, dx=-4, dy=0,  k=-0.048, hand=("arm", -40.0, 1.20),  orb=0.0, glow=0.14, flash=0.38, shot=(28, 6.2)),
    dict(ms=45, dx=-2, dy=0,  k=-0.020, hand=("arm", -18.0, 1.06),  orb=0.0, glow=0.10, flash=0.10, shot=(46, 5.2)),
    dict(ms=50, dx=0,  dy=0,  k=+0.004, hand=("rest",),             orb=3.8, glow=0.10, flash=0.0, shot=None),
]

# --- draw 의 결 둘 ---------------------------------------------------------- #
# 「속사」 — 무는 칸이 짧고 놓자마자 튄다. 총 0.345초로 셋 중 제일 빠르다.
MOTIONS["draw_snap"] = [
    dict(ms=35, dx=0,  dy=0,  k=+0.000, hand=("rest",),             orb=2.0, glow=0.18, flash=0.0, shot=None, shaft=True),
    dict(ms=40, dx=-1, dy=0,  k=-0.016, hand=("arm",  -6.0, 1.06),  orb=2.8, glow=0.62, flash=0.0, shot=None, shaft=True),
    dict(ms=45, dx=-2, dy=1,  k=-0.032, hand=("arm", -10.0, 1.14),  orb=3.6, glow=1.00, flash=0.0, shot=None, shaft=True),
    dict(ms=15, dx=5,  dy=-2, k=+0.070, hand=("arm", -30.0, 1.34),  orb=0.0, glow=0.48, flash=1.00, shot=(6, 7.2), trail=4),
    dict(ms=25, dx=6,  dy=-1, k=+0.078, hand=("arm", -38.0, 1.38),  orb=0.0, glow=0.22, flash=0.35, shot=(27, 6.2)),
    dict(ms=30, dx=3,  dy=0,  k=+0.038, hand=("arm", -20.0, 1.22),  orb=0.0, glow=0.14, flash=0.10, shot=(47, 5.2)),
    dict(ms=35, dx=1,  dy=0,  k=+0.012, hand=("arm",  -8.0, 1.10),  orb=0.0, glow=0.18, flash=0.0, shot=None),
    dict(ms=40, dx=-1, dy=0,  k=-0.008, hand=("arm",  -2.0, 1.02),  orb=1.8, glow=0.16, flash=0.0, shot=None, shaft=True),
    dict(ms=40, dx=0,  dy=0,  k=-0.004, hand=("rest",),             orb=2.0, glow=0.14, flash=0.0, shot=None, shaft=True),
    dict(ms=40, dx=0,  dy=0,  k=+0.000, hand=("rest",),             orb=2.0, glow=0.14, flash=0.0, shot=None, shaft=True),
]

# 「중포」 — 대포·화승총. 오래 겨누고, 놓으면 **뒤로 크게 밀린다**(dx -7 · k -0.09).
# 되돌아오는 데도 오래 걸린다 — 무거운 것은 무겁게 보여야 한다.
MOTIONS["draw_heavy"] = [
    dict(ms=55, dx=0,  dy=0,  k=+0.000, hand=("rest",),             orb=1.8, glow=0.14, flash=0.0, shot=None, shaft=True),
    dict(ms=60, dx=-1, dy=1,  k=-0.010, hand=("arm",  -3.0, 1.02),  orb=2.4, glow=0.40, flash=0.0, shot=None, shaft=True),
    dict(ms=65, dx=-2, dy=1,  k=-0.022, hand=("arm",  -6.0, 1.08),  orb=3.0, glow=0.72, flash=0.0, shot=None, shaft=True),
    dict(ms=50, dx=-3, dy=2,  k=-0.030, hand=("arm",  -8.0, 1.12),  orb=3.6, glow=1.00, flash=0.0, shot=None, shaft=True),
    dict(ms=20, dx=-7, dy=-2, k=-0.090, hand=("arm", -18.0, 1.24),  orb=0.0, glow=0.52, flash=1.00, shot=(6, 7.6), trail=3),
    dict(ms=35, dx=-6, dy=-1, k=-0.078, hand=("arm", -26.0, 1.28),  orb=0.0, glow=0.26, flash=0.40, shot=(26, 6.4)),
    dict(ms=45, dx=-3, dy=0,  k=-0.040, hand=("arm", -14.0, 1.16),  orb=0.0, glow=0.16, flash=0.12, shot=(46, 5.2)),
    dict(ms=50, dx=-1, dy=0,  k=-0.014, hand=("arm",  -6.0, 1.06),  orb=0.0, glow=0.20, flash=0.0, shot=None),
    dict(ms=50, dx=0,  dy=0,  k=-0.004, hand=("arm",  -2.0, 1.02),  orb=1.6, glow=0.16, flash=0.0, shot=None, shaft=True),
    dict(ms=45, dx=0,  dy=0,  k=+0.000, hand=("rest",),             orb=1.8, glow=0.13, flash=0.0, shot=None, shaft=True),
]

# --- raise 의 결 둘 --------------------------------------------------------- #
# ★ 둘 다 `shot` 이 전부 None 이다. 위 규칙 2번.
# 「내리찍기」 — 훨씬 깊이 가라앉았다가(dy +5) 세게 던져 올린다. 힘을 모으는 몸짓은
# 위로 뻗기 전에 **아래로 눌리는** 것으로만 읽힌다 — 그것을 끝까지 밀어붙인 결이다.
MOTIONS["raise_slam"] = [
    dict(ms=45, dx=0,  dy=0,  k=+0.000, hand=("rest",),            orb=3.2, glow=0.10, flash=0.0, shot=None),
    dict(ms=55, dx=0,  dy=3,  k=-0.016, hand=("arm",  26.0, 0.84), orb=4.2, glow=0.34, flash=0.0, shot=None),
    dict(ms=60, dx=-1, dy=5,  k=-0.030, hand=("arm",  40.0, 0.76), orb=5.6, glow=0.62, flash=0.0, shot=None),
    dict(ms=50, dx=-1, dy=3,  k=-0.018, hand=("arm",  -6.0, 0.98), orb=6.8, glow=0.84, flash=0.0, shot=None, trail=3),
    dict(ms=40, dx=0,  dy=-1, k=+0.008, hand=("arm", -68.0, 1.16), orb=8.0, glow=0.96, flash=0.0, shot=None, trail=4),
    dict(ms=50, dx=0,  dy=-3, k=+0.016, hand=("arm", -98.0, 1.28), orb=9.0, glow=1.00, flash=0.0, shot=None, trail=4),
    dict(ms=20, dx=0,  dy=-3, k=+0.020, hand=("arm",-104.0, 1.30), orb=3.2, glow=0.58, flash=1.00, shot=None, trail=3),
    dict(ms=35, dx=0,  dy=-1, k=+0.010, hand=("arm", -84.0, 1.20), orb=1.6, glow=0.30, flash=0.34, shot=None),
    dict(ms=45, dx=0,  dy=1,  k=+0.002, hand=("arm", -36.0, 1.04), orb=2.2, glow=0.16, flash=0.08, shot=None),
    dict(ms=45, dx=0,  dy=0,  k=-0.004, hand=("rest",),            orb=3.0, glow=0.10, flash=0.0, shot=None),
]

# 「펼치기」 — 팔을 옆으로 크게 벌렸다가 머리 옆으로 모은다. 실루엣이 넓게 열린다.
MOTIONS["raise_wide"] = [
    dict(ms=50, dx=0,  dy=0,  k=+0.000, hand=("rest",),            orb=3.4, glow=0.10, flash=0.0, shot=None),
    dict(ms=55, dx=0,  dy=2,  k=-0.008, hand=("arm",  58.0, 1.04), orb=3.8, glow=0.28, flash=0.0, shot=None),
    dict(ms=60, dx=0,  dy=2,  k=-0.014, hand=("arm",  30.0, 1.22), orb=4.8, glow=0.52, flash=0.0, shot=None),
    dict(ms=55, dx=0,  dy=1,  k=-0.006, hand=("arm",   2.0, 1.30), orb=6.0, glow=0.74, flash=0.0, shot=None, trail=3),
    dict(ms=45, dx=0,  dy=-1, k=+0.006, hand=("arm", -44.0, 1.26), orb=7.2, glow=0.90, flash=0.0, shot=None, trail=4),
    dict(ms=50, dx=0,  dy=-2, k=+0.012, hand=("arm", -84.0, 1.18), orb=8.4, glow=1.00, flash=0.0, shot=None, trail=3),
    dict(ms=20, dx=0,  dy=-2, k=+0.016, hand=("arm", -94.0, 1.22), orb=3.0, glow=0.60, flash=1.00, shot=None, trail=3),
    dict(ms=35, dx=0,  dy=-1, k=+0.008, hand=("arm", -78.0, 1.14), orb=1.5, glow=0.30, flash=0.34, shot=None),
    dict(ms=45, dx=0,  dy=0,  k=+0.002, hand=("arm", -38.0, 1.04), orb=2.3, glow=0.16, flash=0.08, shot=None),
    dict(ms=45, dx=0,  dy=0,  k=-0.004, hand=("rest",),            orb=3.2, glow=0.10, flash=0.0, shot=None),
]

# --- 숨쉬기도 결마다 다르다 ------------------------------------------------- #
# ★ 아이들은 **자세가 정지 그림과 같아야 한다**(전투 화면과 편성 판이 다른 사람으로
#   보이면 안 된다). 그래서 결이 바꾸는 것은 **박자와 흔들림의 방향**뿐이다.
# ★ 여기에 탄을 그리지 마라 — 아래 build() 의 숨쉬기 주석 참고.

# 「기우뚱」 — 좌우로 천천히 기운다. 박자가 느려서 무거운 캐릭터에 맞는다.
IDLES["_sway"] = [
    dict(ms=200, dy=0, hand=("rest",),            glow=0.10, orb=3.9),
    dict(ms=180, dy=0, hand=("arm", -3.4, 1.02),  glow=0.20, orb=4.4),
    dict(ms=200, dy=1, hand=("rest",),            glow=0.14, orb=4.1),
    dict(ms=180, dy=0, hand=("arm",  3.0, 0.98),  glow=0.10, orb=3.7),
]

# 「들썩」 — 짧고 잦다. 속사·번개처럼 안절부절못하는 캐릭터에 맞는다.
IDLES["_twitch"] = [
    dict(ms=120, dy=0, hand=("rest",),            glow=0.12, orb=4.0),
    dict(ms=130, dy=-1, hand=("arm", -2.2, 1.03), glow=0.26, orb=4.6),
    dict(ms=120, dy=0, hand=("rest",),            glow=0.16, orb=4.2),
    dict(ms=150, dy=1, hand=("arm",  1.4, 0.98),  glow=0.10, orb=3.8),
]

# 결 → 숨쉬기 표. 없는 결은 무리의 기본 숨쉬기를 쓴다.
IDLE_OF = {
    "cast_lunge": "_sway",   "cast_sweep": "_twitch",
    "draw_snap":  "_twitch", "draw_heavy": "_sway",
    "raise_slam": "_sway",   "raise_wide": "_twitch",
}


def idles_for(motion: str) -> list:
    """그 결의 숨쉬기. 결이 따로 없으면 무리(cast·draw·raise)의 기본을 쓴다."""
    if motion in IDLE_OF:
        return IDLES[IDLE_OF[motion]]
    return IDLES[motion.split("_")[0]]


# --------------------------------------------------------------------------- #
def render_body(master, cell, anchor, sx, sy, k, dx, dy):
    """마스터를 눌러(sx,sy) · 기울여(k) · 밀어(dx,dy) 칸 안에 놓는다.

    기울이기는 **발밑을 축**으로 한다. 머리 쪽이 더 많이 움직여야 "몸을 젖혔다"로
    읽힌다 — 통째로 밀면 그냥 미끄러진 것으로 보인다.

    같은 셈을 뼈대의 점에도 먹일 수 있도록 변환 함수를 같이 돌려준다. 손으로 다시
    맞추면 프레임마다 1~2px 씩 어긋나고, 그 어긋남이 화면에서 **떨림**으로 보인다.
    """
    h, w = master.shape[:2]
    w2, h2 = max(1, round(w * sx)), max(1, round(h * sy))
    a = np.array(Image.fromarray(master).resize((w2, h2), Image.NEAREST))

    cw, ch = cell
    out = np.zeros((ch, cw, 4), np.uint8)
    left0 = anchor[0] - w2 // 2 + dx
    top0 = anchor[1] - h2 + dy
    for y in range(h2):
        ty = top0 + y
        if not (0 <= ty < ch):
            continue
        x0 = left0 + int(round(k * (h2 - 1 - y)))
        sa, sb = max(0, -x0), min(w2, cw - x0)
        if sb <= sa:
            continue
        row = a[y, sa:sb]
        dst = out[ty, x0 + sa:x0 + sb]
        m = row[:, 3] > 0
        dst[m] = row[m]

    def to_cell(px, py):
        """마스터 좌표 → 칸 좌표. **몸에 먹인 것과 똑같은 셈**을 뼈대에도 먹인다.
        여기서 갈라지면 몸은 젖혔는데 팔만 제자리인 프레임이 생긴다."""
        ax, ay = px * sx, py * sy
        return (left0 + ax + k * (h2 - 1 - ay), top0 + ay)

    return out, to_cell


def rim_edge(body, fxo: Fx, mx, my, r, power, face):
    """몸에 얹는 빛 — **램프 색으로만** 칠한다.

    ★ 몸 색을 이펙트 쪽으로 섞어 봤더니 프레임마다 새 색이 수십 개씩 생겨서 시트를
      다시 양자화해야 했고, 그 양자화가 옷 색을 탁하게 만들었다. 지금은 이펙트를
      **마주 보는 실루엣 테두리 한 겹**만 갈아 끼운다. 팔레트가 한 칸도 안 늘어난다.
    """
    if power <= 0.02 or r <= 1.0:
        return
    op = body[:, :, 3] > 0
    p = np.pad(op, 1)
    inner = p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:]
    ys, xs = np.nonzero(op & ~inner)
    for y, x in zip(ys.tolist(), xs.tolist()):
        dx, dy = x + 0.5 - mx, y + 0.5 - my
        d = math.hypot(dx, dy)
        if d > r:
            continue
        # 이펙트를 등진 쪽은 안 밝아진다. 다 밝히면 몸이 통째로 빛나 실루엣이 죽는다.
        if dx * face < -r * 0.35:
            continue
        f = (1.0 - d / r) * power
        if f > 0.18:
            body[y, x] = (*fxo.ramp[LIT[min(2, int(f * 3.0))]], 255)


def hand_target(rg: Rig, spec):
    """프레임 표의 손 목표 → (마스터 좌표) 또는 None(제자리)."""
    kind = spec[0]
    if kind == "rest":
        return None                      # 원본 그대로 — 손을 아예 안 건드린다
    if kind == "arm":
        ang = rg.A0 + math.radians(float(spec[1]))
        r = rg.L0 * float(spec[2])
    elif kind in ("toward", "prop"):
        if not rg.prop_grip:
            raise SystemExit("!! rig.json 에 prop_grip 이 없다 — 소품 잡는 자리를 적어라")
        if kind == "prop":
            return (rg.prop_grip[0] + spec[1], rg.prop_grip[1] + spec[2])
        base = math.atan2(rg.prop_grip[1] - rg.shoulder[1],
                          rg.prop_grip[0] - rg.shoulder[0])
        ang = base + math.radians(float(spec[2]))
        r = rg.L0 * float(spec[1])
    else:
        raise SystemExit(f"!! 모르는 손 목표 {spec}")
    return (rg.shoulder[0] + math.cos(ang) * r, rg.shoulder[1] + math.sin(ang) * r)


def pose(torso, arm, rg: Rig, cell, anchor, dx, dy, k, face, target):
    """한 칸 그리기 — 몸통을 놓고, 그 위에 팔을 돌려 얹는다.

    ★ 팔은 **몸통 위**에 그린다. 던지는 팔은 앞쪽 팔이고, 되감을 때 가슴을 가로지른다.
      뒤에 그리면 그 칸에서 팔이 통째로 사라진다.
    """
    body, to_cell = render_body(torso, cell, anchor, 1.0, 1.0, k * face, dx * face, dy)
    if target is None:
        # ★ 제자리 칸은 팔을 **한 번도 안 돌리지 않는다.** 0도 회전·1.0 배도 최근접을
        #   한 번 거치면 1px 씩 밀린다. 아이들이 정지 그림과 어긋나 보이는 원인이 그것이다.
        #   대신 몸통과 **똑같은 셈**(밀기·기울이기)을 팔에도 먹인다. 기울이기는 행마다
        #   다르므로 통째로 옮기면 몸만 젖혀지고 팔은 안 젖혀진다.
        only, _ = render_body(arm, cell, anchor, 1.0, 1.0, k * face, dx * face, dy)
        m = only[:, :, 3] > 0
        body[m] = only[m]
        return body, to_cell, to_cell(*rg.tip), 0.0, False
    delta, stretch, mirror = rg.plan(*target)
    sp, pv = rg.arm_sprite(arm, delta, stretch, mirror)
    blit(body, sp, to_cell(*rg.shoulder), pv)
    tip = to_cell(*rg.tip_at(target[0], target[1], delta, stretch))
    return body, to_cell, tip, delta, mirror


def fx_at(tip, lift, delta: float, mirror: bool):
    """이펙트를 놓을 자리 — 손끝에서 **팔과 같이 돌아간** 만큼 옮긴 곳.

    ★ 손바닥에 얹힌 것은 손이 돌면 같이 돈다. 늘 「손끝의 위쪽」에 놓아 봤더니,
      손을 홀 쪽으로 내렸을 때 얼음이 **얼굴 위**에 얹혔다. 가장 세게 모은 칸에서
      캐릭터의 얼굴이 가려지는 것이 그 판의 제일 큰 흠이었다.
    """
    lx, ly = lift
    if mirror:
        lx = -lx                     # 뒤집힌 팔에서는 손바닥도 뒤집힌다
    c, s2 = math.cos(delta), math.sin(delta)
    return (tip[0] + lx * c - ly * s2, tip[1] + lx * s2 + ly * c)


def shaft(eff, fxo: Fx, a, b, fxs: float):
    """메긴 살 — 시위 쥔 손(a)에서 활(b)까지 **곧은 한 줄**. `--link shaft`.

    ★ 마법사의 흔들리는 부스러기 줄기(`--link wobble`)를 그대로 쓰면 안 된다. 그것은
      「소품에서 뽑아 온다」로 읽히는 것이고, 살은 **뻣뻣한 막대**다. 흔들리는 살은
      살로 안 보인다 — 실제로 먼저 그렇게 그려 봤고 활에 걸친 불씨처럼 보였다.
    ★ 테두리를 한 겹 두른다. 1px 짜리 금색 줄만 그으면 몬스터 위를 지날 때 통째로
      묻힌다 (fx.shape 이 테두리를 두르는 이유와 같다).
    """
    ch, cw = eff.shape[:2]
    dx, dy = b[0] - a[0], b[1] - a[1]
    n = int(math.hypot(dx, dy))
    if n < 4:
        return
    line = np.zeros((ch, cw), bool)
    for i in range(n + 1):
        t = i / n
        x, y = int(round(a[0] + dx * t)), int(round(a[1] + dy * t))
        if 0 <= x < cw and 0 <= y < ch:
            line[y, x] = True
    # 살촉(활 쪽)과 오늬깃(손 쪽). 둘 다 없으면 그냥 「빛나는 실」이고, 활을 든 뜻이 없다.
    ang = math.atan2(dy, dx)
    for at, base, ln, spread in ((b, ang + math.pi, max(3.0, 4.2 * fxs), 0.62),
                                 (a, ang, max(2.0, 3.0 * fxs), 0.85)):
        for sgn in (+1, -1):
            ba = base + sgn * spread
            for i in range(int(ln) + 1):
                x = int(round(at[0] + math.cos(ba) * i))
                y = int(round(at[1] + math.sin(ba) * i))
                if 0 <= x < cw and 0 <= y < ch:
                    line[y, x] = True
    p = np.pad(line, 1)
    nb = (p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]
          | p[:-2, :-2] | p[:-2, 2:] | p[2:, :-2] | p[2:, 2:])
    for y, x in zip(*np.nonzero(nb & ~line)):
        if eff[y, x, 3] == 0:
            eff[y, x] = (*fxo.edge, 255)
    for k, (y, x) in enumerate(zip(*np.nonzero(line))):
        eff[y, x] = (*fxo.ramp[0 if (k % 5 == 0) else 1], 255)


def merge(fire, body):
    """이펙트를 몸 **앞에** 얹는다. 알파는 끝까지 0 아니면 255 다."""
    out = body.copy()
    m = fire[:, :, 3] > 0
    out[m] = fire[m]
    return out


PAD_BOT = 2
SLACK = 70          # 넉넉히 그려 놓고 나중에 잘라 낸다


def fit_cell(frames, master_wh, pad_bot: int):
    """다 그린 뒤 **아무것도 안 잘리는 가장 작은 칸**으로 줄인다.

    ★ ART.md 8 의 「좌우 40 · 위 18」은 어림수다. 실제로 필요한 여백은 그 캐릭터가
      팔을 얼마나 치켜드는지 · 이펙트를 얼마나 키웠는지 · 탄을 얼마나 멀리 보내는지에
      달려 있어서, 숫자를 못 박으면 언젠가 조용히 잘린다.
      **화염마도사가 실제로 그랬다** — 7·8 번 칸의 불덩이가 오른쪽에서 14px·6px 잘려
      나갔고, 스트립만 봐서는 안 보였다. 그래서 여백을 정하지 않고 **재서** 맞춘다.
    ★ 기준점은 그대로 **가로 가운데 · 세로 발밑**이다. 그래서 좌우를 같은 만큼 둔다 —
      한쪽만 넓히면 기준점이 가운데가 아니게 되어 `Art.draw_at()` 규칙이 깨진다.
    """
    mw, mh = master_wh
    ch, cw = frames[0].shape[:2]
    cx = cw // 2
    half, top = mw // 2 + 1, mh
    for f in frames:
        ys, xs = np.nonzero(f[:, :, 3] > 0)
        if not len(xs):
            continue
        half = max(half, int(cx - xs.min()) + 1, int(xs.max() - cx) + 2)
        top = max(top, int(ch - pad_bot - ys.min()) + 1)
    nw, nh = half * 2, top + pad_bot
    x0, y0 = cx - half, (ch - pad_bot) - top
    out = []
    for f in frames:
        g = np.zeros((nh, nw, 4), np.uint8)
        sx0, sy0 = max(0, x0), max(0, y0)
        sx1, sy1 = min(cw, x0 + nw), min(ch, y0 + nh)
        g[sy0 - y0:sy1 - y0, sx0 - x0:sx1 - x0] = f[sy0:sy1, sx0:sx1]
        out.append(g)
    return (nw, nh), out


def build(torso, arm, rg: Rig, fxo: Fx, face: int, lift, fxs: float,
          motion: str = "cast", muzzle: str = "hand", link: str = "wobble"):
    frames, idles = MOTIONS[motion], idles_for(motion)
    h, w = torso.shape[:2]
    pad_bot = PAD_BOT
    pad_x = round(40 * fxs) + SLACK
    pad_top = round(18 * fxs) + SLACK
    cell = (w + pad_x * 2, h + pad_top + pad_bot)
    anchor = (cell[0] // 2, cell[1] - pad_bot)

    # ★ **놓는 칸의 총구가 어디였는가**를 적어 둔다. 게임이 탄을 그 자리에서 내보낸다 —
    #   적어 두지 않으면 화면이 영웅의 **발밑**에서 탄을 뽑을 수밖에 없고, 실제로 그랬다.
    #   기준점(가로 가운데 · 세로 발밑)에서 잰 상대 좌표라 fit_cell 로 칸을 줄여도 그대로다
    #   (fit_cell 이 기준점을 옮기지 않기 때문이다 — 그 함수의 주석 참고).
    hit_i = min(range(len(frames)), key=lambda i: frames[i]["ms"])
    muzzle_at = None

    atk, prev_tip = [], None
    for i, f in enumerate(frames):
        tgt = hand_target(rg, f["hand"])
        body, to_cell, tip, delta, mir = pose(torso, arm, rg, cell, anchor,
                                              f["dx"], f["dy"], f["k"], face, tgt)
        ph = i * 1.9
        prop = to_cell(*rg.prop_tip) if rg.prop_tip else None
        eff = np.zeros_like(body)
        # 이펙트는 **손끝**에 놓되, 팔이 돈 만큼 **같이 돌린다**(fx_at).
        # ★ 여기가 한동안 아이들과 갈라져 있었다 — 공격 칸만 `tip + lift` 로 안 돌렸다.
        #   서리여왕에서 가장 세게 모으는 칸의 얼음이 관 위로 올라가 얼굴을 가렸고,
        #   궁수에서는 더 나빴다: 만작에서 손이 -54도 돌아가는데 메긴 살이 안 따라가서
        #   **화살이 손을 떠나 허공에 떠 있었다.** 손바닥에 얹힌 것은 손이 돌면 같이 돈다.
        mx, my = fx_at(tip, lift, delta, mir)

        # ★ **탄이 어디서 나가는가**. 마법사는 손이고 궁수·총병은 소품이다.
        #   궁수를 손으로 두면 만작에서 손이 얼굴 옆에 있으므로 화살이 얼굴에서 나간다.
        mzx, mzy = (prop if (muzzle == "prop" and prop) else (mx, my))
        if i == hit_i:
            muzzle_at = (mzx - anchor[0], mzy - anchor[1])

        if prop and f["glow"] > 0.05:
            fxo.charge(eff, prop[0], prop[1], (1.8 + 3.6 * f["glow"]) * fxs, ph, face)
        if prop and link == "shaft":
            # 궁수 — 손과 활을 잇는 것은 **메긴 살**이다. 칸마다 표에 적어 둔다.
            if f.get("shaft"):
                shaft(eff, fxo, (mx, my), prop, fxs)
        elif prop and (0.45 < f["glow"] < 0.99 or f["orb"] > 1.0):
            # 마법사 — 소품에서 손으로 흐르는 부스러기. "소품에서 뽑아 온다"가 여기서 읽힌다
            n = 6
            for j in range(1, n):
                t = j / n
                px = prop[0] + (mx - prop[0]) * t
                py = prop[1] + (my - prop[1]) * t + math.sin(t * 3.4 + ph) * 3.0
                ix, iy = int(px), int(py)
                if 0 <= ix < cell[0] and 0 <= iy < cell[1] and eff[iy, ix, 3] == 0:
                    eff[iy, ix] = (*fxo.ramp[1 + (j % 3)], 255)

        if f["flash"] > 0.0:
            fxo.burst(eff, mzx, mzy, (4.8 + 7.4 * f["flash"]) * fxs, ph, face)
            fxo.motes(eff, mzx, mzy, 10, 15.0 * fxs, 8.0 * fxs, ph)
        if f["orb"] > 0.0:
            fxo.charge(eff, mx, my, f["orb"] * fxs, ph, face)
            # 마스터가 얼음조각 둘레에 성엣가루를 여섯 점 찍어 놓았다. 정지 그림과
            # 아이들이 **다른 물건**으로 보이지 않으려면 그것도 이어 줘야 한다.
            fxo.motes(eff, mx, my, 4, f["orb"] * 2.0 * fxs, 1.0, ph * 0.7)
            if f["orb"] > 6.0:
                fxo.motes(eff, mx, my - f["orb"] * fxs, 5, 8.0 * fxs, 7.0 * fxs, ph)
        # 휘두름 잔상 — 앞 칸의 손끝에서 지금 손끝까지.
        # ★ 없으면 팔이 한 칸에 60도씩 건너뛰어 **순간이동**으로 보인다.
        if f.get("trail") and prev_tip is not None:
            n = int(f["trail"])
            for j in range(1, n + 1):
                t = j / (n + 1.0)
                fxo.blob(eff, prev_tip[0] + (mx - prev_tip[0]) * t,
                         prev_tip[1] + (my - prev_tip[1]) * t, (1.4 + 2.2 * t) * fxs, ph + j)

        if f["shot"]:
            ax, ar = f["shot"]
            fxo.dart(eff, mzx + ax * fxs * face, mzy + 1.0, ar * fxs, ph + 0.9, face)

        lit_r = (30.0 if f["flash"] > 0.0 else max(13.0, f["orb"] * 2.6)) * fxs
        lit_p = 1.0 if f["flash"] > 0.0 else min(1.0, f["orb"] / 9.0)
        # 터지는 칸에서는 빛도 **터진 자리**에서 온다. 손에 두면 활에서 화살이 나가는데
        # 몸의 테두리는 얼굴 옆에서 밝아져 어느 쪽이 사건인지가 흐려진다.
        rim_edge(body, fxo, mzx if f["flash"] > 0.0 else mx,
                 mzy if f["flash"] > 0.0 else my, lit_r, lit_p, face)
        atk.append(merge(eff, body))
        prev_tip = (mx, my)

    # ------------------------------------------------------------------ #
    # 숨쉬기 — ★ **여기에 탄을 그리지 마라.**
    #
    # 사용자가 본 것: 「idle 상태에서도 shot 들이 꼬랑지에 계속 붙어있어」.
    # 예전 아이들은 공격 칸과 같은 이펙트 상자를 그대로 썼다. 그래서:
    #   1. `link == "shaft"` 인 궁수·총병은 **메긴 살**(shaft)이 매 칸 그려졌다. 그것은
    #      살촉과 오늬깃이 달린 **화살 모양**이라, 총구 앞 허공에 화살 한 대가 영원히
    #      떠 있는 그림이 됐다 (화승총병·서리총병·수문지기가 실제로 그랬다).
    #      게다가 마스터 그림에 이미 살이 그려져 있어서 **화살이 두 대**로 보였다.
    #   2. `motes` 가 손에서 떨어진 자리에 점 넷을 뿌렸다. 몸에 안 닿은 점은 화면에서
    #      「날아가는 부스러기」로 읽힌다 — 가만히 선 캐릭터가 뭔가를 흘리고 있었다.
    #
    # 그래서 숨쉬기의 이펙트를 **두 가지 규칙**으로 줄였다:
    #   ★ **탄 모양(shaft·dart)은 한 번도 안 그린다.** 아이들은 「쏘기 전」이지
    #     「쏘는 중」이 아니다. 무엇이 날아가는 것처럼 보이는 순간 그 뜻이 깨진다.
    #   ★ **떨어져 나온 점(motes)도 안 그린다.** 몸에 붙어 있지 않은 것은 전부
    #     날아가는 것으로 읽힌다.
    #   ★ 남는 것은 **손과 소품에 붙은 작은 불씨** 하나뿐이고, 그마저도 **마법사에게만**
    #     있다(cast · raise). 활과 총은 쉬는 동안 빛나지 않는다 — 총열이 저 혼자
    #     달아오르면 그것도 「쏘는 중」이다.
    idle_lit = (link != "shaft")
    idl = []
    for i, f in enumerate(idles):
        tgt = hand_target(rg, f["hand"])
        body, to_cell, tip, delta, mir = pose(torso, arm, rg, cell, anchor,
                                              0, f["dy"], 0.0, face, tgt)
        eff = np.zeros_like(body)
        mx, my = fx_at(tip, lift, delta, mir)
        if idle_lit:
            if rg.prop_tip:
                p = to_cell(*rg.prop_tip)
                fxo.charge(eff, p[0], p[1], (1.2 + 1.8 * f["glow"]) * fxs, i * 2.7, face)
            # 손의 불씨 — 공격 칸의 절반쯤이다. 여기서 크게 두면 「모으는 중」으로
            # 읽혀서, 정작 공격 칸에서 진짜로 모을 때 세기가 안 올라 보인다.
            fxo.charge(eff, mx, my, f["orb"] * 0.55 * fxs, i * 2.1, face)
            rim_edge(body, fxo, mx, my, 10.0 * fxs, 0.24, face)
        idl.append(merge(eff, body))

    # 넉넉히 그려 놓았으니 이제 **아무것도 안 잘리는 가장 작은 칸**으로 줄인다.
    # 공격과 아이들이 **같은 칸**이어야 한다 — 다르면 화면에서 클립을 바꿀 때 튄다.
    cell, both = fit_cell(atk + idl, (w, h), pad_bot)
    atk, idl = both[:len(atk)], both[len(atk):]

    # 날아가는 탄 — 게임은 탄을 코드로 그리므로 **선택**이다.
    shots = []
    # ★ 화살은 덩어리보다 훨씬 길다. 38 칸에 그리면 살촉이 조용히 잘린다 —
    #   `qc` 의 「칸 밖으로 잘림」이 잡아 주지만, 애초에 넉넉히 그리고 재서 줄인다.
    sw = 46.0 if fxo.shot == "arrow" else 38.0
    for i in range(4):
        s = np.zeros((int(24 * fxs), int(sw * fxs), 4), np.uint8)
        fxo.dart(s, 20.0 * fxs, 12.0 * fxs, 7.0 * fxs, i * 1.55, 1)
        shots.append(s)
    _, shots = fit_cell(shots, (1, 1), 0)

    return cell, atk, idl, shots, muzzle_at


# --------------------------------------------------------------------------- #
def strip(frames):
    h, w = frames[0].shape[:2]
    sheet = np.zeros((h, w * len(frames), 4), np.uint8)
    for i, f in enumerate(frames):
        sheet[:, i * w:(i + 1) * w] = f
    return Image.fromarray(sheet)


def gif(frames, ms, path, scale=4, bg=(26, 20, 32)):
    ims = []
    for f in frames:
        im = Image.new("RGB", (f.shape[1], f.shape[0]), bg)
        im.paste(Image.fromarray(f), (0, 0), Image.fromarray(f))
        ims.append(im.resize((im.width * scale, im.height * scale), Image.NEAREST))
    ims[0].save(path, save_all=True, append_images=ims[1:], duration=ms, loop=0,
                disposal=2, optimize=False)


def qc(tag, frames, allowed) -> bool:
    """pixelforge QC 게이트 1·2 와 같은 잣대 (ART.md 7).
      1 반투명 0개 · 2 색 수 예산 안 · 3 **마스터 팔레트를 벗어난 색 0개**
    셋째가 핵심이다 — 벗어났다면 어딘가에서 색을 섞은 것이고, 그건 곧 시트를
    다시 양자화해야 한다는 뜻이다.

    ★ 넷째: **칸 밖으로 잘린 것이 없는가.** 이펙트를 키우거나 탄을 멀리 보내면 마지막
      칸에서 조용히 잘린다. 스트립만 보면 안 보이고 게임에서 「탄이 반쪽」으로 나온다.
      아래·좌우·위 테두리에 불투명 픽셀이 닿으면 알려 준다 (발밑은 닿는 게 맞다).
    """
    big = np.concatenate(frames, axis=0)
    op = big[:, :, 3] > 0
    semi = int(((big[:, :, 3] > 0) & (big[:, :, 3] < 255)).sum())
    cols = {tuple(int(v) for v in c)
            for c in np.unique(big[:, :, :3][op].reshape(-1, 3), axis=0)}
    stray = cols - allowed
    clipped = []
    for i, f in enumerate(frames):
        m = f[:, :, 3] > 0
        if m[:, 0].any() or m[:, -1].any() or m[0, :].any():
            clipped.append(i)
    ok = semi == 0 and not stray and not clipped
    note = "OK"
    if stray:
        note = "!! 팔레트이탈 " + str(sorted(stray)[:4])
    elif clipped:
        note = f"!! 칸 밖으로 잘린 프레임 {clipped}"
    elif semi:
        note = "!! 반투명"
    print(f"  {tag:7s} {len(frames)}프레임  칸 {frames[0].shape[1]}x{frames[0].shape[0]}  "
          f"색 {len(cols)}  반투명 {semi}  팔레트이탈 {len(stray)}  {note}")
    return ok


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("name")
    ap.add_argument("--src", required=True, help="part_torso.png · part_arm.png · rig.json 이 있는 곳")
    ap.add_argument("--static", default="", help="게임용 정지 스프라이트 (기본 <src>/master.png)")
    ap.add_argument("--face", type=int, default=1, help="1 오른쪽 · -1 왼쪽")
    ap.add_argument("--lift", default="0,-2",
                    help="이펙트를 손끝에서 dx,dy 만큼 옮겨 놓는다. ★ 마스터에서 이펙트가 "
                         "손바닥 위에 떠 있었으면 그 자리를 그대로 적어라 — 아이들이 "
                         "정지 그림과 달라 보이는 것이 여기서 온다")
    ap.add_argument("--fx", type=float, default=1.0,
                    help="이펙트 크기 배수. 등급이 큰 캐릭터는 1.2~1.4")
    ap.add_argument("--motion", default="", choices=["", *MOTIONS],
                    help="동작 표. 안 주면 concepts.json 의 motion (기본 cast)")
    ap.add_argument("--muzzle", default="", choices=["", "hand", "prop"],
                    help="탄이 나가는 자리. 마법사는 hand · 궁수·총병은 prop")
    ap.add_argument("--link", default="", choices=["", "wobble", "shaft"],
                    help="손과 소품을 잇는 것. 마법사는 흐르는 부스러기 · 궁수는 메긴 살")
    ap.add_argument("--stretch", default="",
                    help="팔 길이 배수 한계 lo,hi (기본 0.80,1.35). 당기는 동작은 lo 를 내린다")
    ap.add_argument("--out", default="")
    a = ap.parse_args()

    with open(os.path.join(HERE, "concepts.json"), encoding="utf-8") as f:
        c = json.load(f)[a.name]
    static = a.static or os.path.join(a.src, "master.png")
    out = a.out or os.path.join(a.src, "out")
    os.makedirs(out, exist_ok=True)

    torso = np.array(Image.open(os.path.join(a.src, "part_torso.png")).convert("RGBA"))
    arm = np.array(Image.open(os.path.join(a.src, "part_arm.png")).convert("RGBA"))
    ref = np.array(Image.open(static).convert("RGBA"))
    mcols = {tuple(int(v) for v in c2)
             for c2 in np.unique(ref[:, :, :3][ref[:, :, 3] > 0].reshape(-1, 3), axis=0)}

    motion = a.motion or c.get("motion", "cast")
    muzzle = a.muzzle or c.get("muzzle", "hand")
    link = a.link or c.get("link", "wobble")
    st = a.stretch or c.get("stretch", "")
    rg = Rig.load(os.path.join(a.src, "rig.json"),
                  stretch=[float(v) for v in st.split(",")] if st else None)
    fxo = Fx(c["ramp"], c["edge"], facets=int(c.get("facets", 0)),
             shot=c.get("shot", "bolt"))
    lift = tuple(float(v) for v in a.lift.split(","))
    cell, atk, idl, shots, muzzle_at = build(torso, arm, rg, fxo, a.face, lift, a.fx,
                                             motion, muzzle, link)
    fr, idf = MOTIONS[motion], idles_for(motion)
    hit = min(range(len(fr)), key=lambda i: fr[i]["ms"])   # 제일 짧은 칸이 놓는 순간

    p = lambda s: os.path.join(out, f"{a.name}{s}")
    strip(atk).save(p("_attack.png"), optimize=True)
    strip(idl).save(p("_idle.png"), optimize=True)
    strip(shots).save(p("_shot.png"), optimize=True)
    Image.open(static).save(p(".png"), optimize=True)
    gif(atk, [f["ms"] for f in fr], p("_attack.gif"))
    gif(idl, [f["ms"] for f in idf], p("_idle.gif"))
    gif(shots, [80] * 4, p("_shot.gif"), scale=6)

    meta = {
        "name": a.name, "ko": c.get("ko", ""), "elem": c.get("elem", ""),
        "cell": {"w": cell[0], "h": cell[1]},
        "static": {"w": int(ref.shape[1]), "h": int(ref.shape[0]),
                   "note": "그림자·이름표는 **이 높이**로 잡는다. 칸 높이를 쓰면 그림자가 커진다"},
        "anchor": {"x": cell[0] // 2, "y": cell[1] - 2,
                   "note": "가로 가운데 · 세로 발밑 (Art.draw_at 과 같은 규칙)"},
        # ★ 놓는 칸(hit_frame)의 **총구 자리**. 기준점에서 잰 상대 좌표(칸 픽셀)다.
        #   게임은 이것을 그림 높이로 나눠 roster 의 muz 로 삼고, 탄을 그 자리에서 내보낸다.
        "muzzle_at": {"x": int(muzzle_at[0]), "y": int(muzzle_at[1]),
                      "note": "기준점(발밑 가운데)에서 잰 상대 좌표. 탄이 여기서 나간다"},
        "hit_ms": sum(f["ms"] for f in fr[:hit]),
        "face": a.face,
        "motion": motion, "muzzle": muzzle, "link": link,
        "palette": {"master": len(mcols), "ramp": len(fxo.cols),
                    "ramp_colors": [list(x) for x in fxo.cols]},
        "clips": {
            "attack": {"frames": len(atk), "ms": [f["ms"] for f in fr],
                       "total_ms": sum(f["ms"] for f in fr), "loop": False,
                       "hit_frame": hit,
                       "note": "hit_frame 은 **제일 짧은 칸**이다 — 눈이 그것을 타격으로 읽는다. "
                               "0.26초에 맞춰야 하면 되돌아오는 칸(놓은 뒤 마지막 둘)을 뺀다"},
            "idle": {"frames": len(idl), "ms": [f["ms"] for f in idf],
                     "total_ms": sum(f["ms"] for f in idf), "loop": True},
            "shot": {"frames": len(shots), "ms": [80] * 4, "total_ms": 320, "loop": True},
        },
    }
    with open(p("_anim.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)

    allowed = mcols | set(fxo.cols)
    good = all([qc("attack", atk, allowed), qc("idle", idl, allowed),
                qc("shot", shots, allowed)])
    print(f"  마스터 {len(mcols)}색 + 램프 {len(fxo.cols)}색 = {len(allowed)}색 예산")
    print(f"  → {out}")
    return 0 if good else 1


if __name__ == "__main__":
    raise SystemExit(main())
