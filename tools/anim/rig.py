#!/usr/bin/env python3
"""팔 하나짜리 뼈대 — **원본 팔 조각을 어깨 축으로 돌린다.** ART.md 5번.

★ 손으로 다시 그려 봤고, 버렸다. 소매를 거리장으로 칠했더니 AI 가 그린 원본 소매
  (금테 · 접힌 주름 · 자락)를 못 따라가고 **맨 튜브**가 됐다. 손은 얼룩이 됐다.
  그림의 값어치가 거기 다 들어 있는데 그걸 버리고 도형을 그리면 캐릭터가 바뀐다.

★ 그래서 오려서 돌린다. 문제는 **자락**이다 — 종처럼 벌어진 소맷자락은 늘 아래로
  드리워야 하는데, 왼쪽으로 뻗으려고 150도쯤 돌리면 자락이 하늘을 본다.
  **좌우를 뒤집어서 푼다.** 뒤집으면 팔은 왼쪽을 보고 자락은 그대로 아래다.
  그 덕에 실제 회전은 늘 ±60도 안이고, 그 범위에서는 천이 이상해 보이지 않는다.

★ 회전 · 확대 · 뒤집기는 전부 **최근접**이다. 쌍선형을 한 번이라도 쓰면 그 자리에서
  팔레트가 수백 색으로 번져 도트가 아니게 된다.
"""
from __future__ import annotations

import json
import math

import numpy as np
from PIL import Image

STRETCH = (0.80, 1.35)   # 길이 배수 한계. ±35% 를 넘기면 소매가 국수가 된다.
# ★ 위·아래 끝이 **뜻이 다르다.** 위(1.35)는 「소매가 국수가 된다」는 그림의 한계이고,
#   아래(0.80)는 그냥 마법사에게 그만큼이 필요 없었을 뿐이다. 궁수는 다르다 —
#   **당기는 것이 곧 짧아지는 것**이라, 0.80 으로는 어깨~손이 20% 밖에 안 줄어 만작이
#   만작으로 안 읽힌다(팔 30px 에서 6px). 아래끝을 내리면 팔이 길이 방향으로 눌리는데,
#   3/4 정면에서 팔을 당기면 실제로 **앞으로 줄어들어 보이므로**(단축법) 그림이 안 상한다.
#   위끝을 올리는 것과는 위험이 다르다. 캐릭터마다 `--stretch` 로 준다.
PAD = 160                # 돌릴 때 잘리지 않도록 두르는 여백


class Rig:
    """마스터 좌표로 셈하는 팔 뼈대. `cut_arm.py` 가 남긴 rig.json 을 읽는다."""

    def __init__(self, shoulder, tip, prop_tip=None, prop_grip=None, stretch=None):
        self.stretch = tuple(stretch) if stretch else STRETCH
        self.shoulder = (float(shoulder[0]), float(shoulder[1]))
        self.tip = (float(tip[0]), float(tip[1]))
        dx, dy = self.tip[0] - self.shoulder[0], self.tip[1] - self.shoulder[1]
        self.L0 = math.hypot(dx, dy)
        self.A0 = math.atan2(dy, dx)
        self.prop_tip = tuple(prop_tip) if prop_tip else None
        self.prop_grip = tuple(prop_grip) if prop_grip else None

    @classmethod
    def load(cls, path: str, prop_tip=None, prop_grip=None, stretch=None) -> "Rig":
        with open(path, encoding="utf-8") as f:
            d = json.load(f)
        return cls(d["shoulder"], d["tip"],
                   prop_tip or d.get("prop_tip"), prop_grip or d.get("prop_grip"),
                   stretch)

    # ------------------------------------------------------------------ #
    def plan(self, tx: float, ty: float):
        """손끝 목표 → (돌릴 각, 늘릴 배수, 뒤집을지). 전부 마스터 좌표로 센다."""
        sx, sy = self.shoulder
        dx, dy = tx - sx, ty - sy
        d = math.hypot(dx, dy) or 1e-6
        ang = math.atan2(dy, dx)
        stretch = min(self.stretch[1], max(self.stretch[0], d / self.L0))
        # 뒤집는 것은 목표가 **팔이 본디 보던 쪽의 반대**일 때다.
        # ★ 예전에는 `cos(ang) < 0` — 곧 「목표가 왼쪽이면 뒤집는다」였다. 마법사 둘은
        #   팔이 본디 오른쪽을 봐서 그게 같은 말이었지만, **궁수는 팔이 왼쪽을 본다**
        #   (만작이라 시위 쥔 손이 뒤에 있다). 그 규칙 그대로면 **제자리 자세에서조차**
        #   뒤집혀서 150도가 돌아가고, 팔이 통째로 뒤집힌 채 하늘을 본다.
        #   본디 방향과 견주면 마법사에게는 셈이 한 톨도 안 바뀐다(cos(A0)>0 이므로).
        mirror = (math.cos(ang) < 0.0) != (math.cos(self.A0) < 0.0)
        # 뒤집힌 팔의 자연 각은 (pi - A0). 거기서 얼마나 더 돌릴지.
        delta = ang - ((math.pi - self.A0) if mirror else self.A0)
        return (delta + math.pi) % (2.0 * math.pi) - math.pi, stretch, mirror

    def arm_sprite(self, arm: np.ndarray, delta: float, stretch: float, mirror: bool):
        """팔 조각을 뒤집고 · 길이 방향으로 늘이고 · 어깨를 축으로 돌린다."""
        a = arm
        sx, sy = self.shoulder
        if mirror:
            a = np.ascontiguousarray(a[:, ::-1])
            sx = a.shape[1] - 1 - sx
        im = Image.fromarray(a)
        if abs(stretch - 1.0) > 0.01:
            im = im.resize((max(1, int(round(im.width * stretch))), im.height),
                           Image.NEAREST)
            sx = sx * stretch
        pad = Image.new("RGBA", (PAD * 2, PAD * 2), (0, 0, 0, 0))
        pad.paste(im, (PAD - int(round(sx)), PAD - int(round(sy))))
        if abs(delta) > 0.005:
            pad = pad.rotate(-math.degrees(delta), resample=Image.NEAREST,
                             center=(PAD, PAD))
        return np.array(pad), (PAD, PAD)

    def tip_at(self, tx: float, ty: float, delta: float, stretch: float):
        """실제로 손끝이 어디에 놓이는지 — 늘이기를 잘라 냈으면 목표보다 짧다.
        이펙트는 **여기**에 놓아야 손에 얹힌 것으로 보인다."""
        sx, sy = self.shoulder
        dx, dy = tx - sx, ty - sy
        d = math.hypot(dx, dy) or 1e-6
        r = self.L0 * stretch
        return (sx + dx / d * r, sy + dy / d * r)


def blit(out: np.ndarray, src: np.ndarray, at, pivot) -> None:
    ch, cw = out.shape[:2]
    sh, sw = src.shape[:2]
    ox, oy = int(round(at[0] - pivot[0])), int(round(at[1] - pivot[1]))
    x0, y0 = max(0, ox), max(0, oy)
    x1, y1 = min(cw, ox + sw), min(ch, oy + sh)
    if x1 <= x0 or y1 <= y0:
        return
    sub = src[y0 - oy:y1 - oy, x0 - ox:x1 - ox]
    m = sub[:, :, 3] > 0
    out[y0:y1, x0:x1][m] = sub[m]
