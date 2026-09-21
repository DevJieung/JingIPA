#!/usr/bin/env python3
"""이펙트 그리기 — ART.md 6 「이펙트 그리는 법」.

★ 동그라미에 각도 흔들림을 먹이면 반지름 7~9px 에서 **울퉁불퉁한 고깃덩이**가 된다.
  그래서 **하나의 깊이 지도**로 그린다: 심(core) 하나 + 뻗는 가지 몇 개를 한 장의 t 로
  합치고, t 로 띠를 나눈 뒤 바깥에 테두리를 **한 겹** 두른다.
  실루엣이 하나라 어디서 잘라도 그 이펙트로 읽히고, 테두리가 한 겹이라 도트로 보인다.

★ **반투명을 한 픽셀도 쓰지 마라.** 이 게임의 그림은 알파가 0/255 뿐이다.

★ 속성은 **심의 모양**과 **가지의 성질**로만 갈린다. 그것 말고는 전부 같은 코드다.

      불   `facets=0`   둥근 심 + 흔들리는 혓바닥        (살랑거린다)
      얼음 `facets=6`   육각 결정 + 곧고 뾰족한 가시     (안 흔들린다)
      전기 `facets=-1`  작고 사나운 심 + **지그재그 가지**  (꺾이고 갈라진다)

  얼음 가지에 흔들림을 넣어 봤더니 그냥 **녹는 것**처럼 보였다. 얼음은 각져야 한다.
  ★ 번개도 마찬가지다. 불의 혓바닥을 노랗게만 칠하면 그냥 **노란 불**이고, 얼음의 곧은
  가시를 노랗게 칠하면 **노란 얼음**이다. 번개를 번개로 만드는 것은 색이 아니라
  **꺾임과 갈라짐**이다 — 그래서 가지를 곧은 토막 하나가 아니라 **꺾인 폴리라인**으로 긋고,
  굵기를 거의 안 줄인다(불·얼음은 끝으로 갈수록 뾰족해진다). 갈래는 첫 마디에서 하나 친다.

★ 꺾이는 자리는 **난수가 아니라 각도와 phase 로만** 정한다. `random` 을 쓰면 같은 프레임을
  다시 그릴 때마다 모양이 달라져서 화면에서 **깜빡임**으로 보인다.

★ **속성(`facets`)과 무기(`shot`)는 다른 것이다.** 앞의 둘(마법사)은 손에서 나가므로
  날아가는 것이 곧 그 속성 덩어리였고, 그래서 하나로 묶여 있었다. 궁수를 만들며 갈랐다 —
  번개 궁수가 쏘는 것은 「번개」가 아니라 **번개로 된 화살**이다. 살대·살촉·깃이 안 보이면
  활을 든 뜻이 사라진다.

      shot="bolt"   (기본) 속성 덩어리가 그대로 날아간다 — 지팡이 · 손
      shot="arrow"  곧은 살대 + 살촉 + 깃 — 활

  램프 색으로 그리므로 얼음 궁수(달빛궁수)는 `facets=6, shot="arrow"` 면 된다.
"""
from __future__ import annotations

import math

import numpy as np


def _seg_dist(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    L2 = vx * vx + vy * vy
    if L2 <= 1e-6:
        return math.hypot(px - ax, py - ay), 0.0
    u = ((px - ax) * vx + (py - ay) * vy) / L2
    u = max(0.0, min(1.0, u))
    return math.hypot(px - (ax + vx * u), py - (ay + vy * u)), u


class Fx:
    """램프 하나를 쥐고 그 색으로만 그린다.

    ★ 램프 밖의 색을 절대 만들지 않는다. 색을 섞으면 프레임마다 새 색이 수십 개씩
      생기고, 그러면 시트를 다시 양자화해야 하는데 그 양자화가 옷 색을 탁하게 만든다.
    """

    BANDS = ((0.62, 0), (0.42, 1), (0.24, 2), (0.10, 3), (0.0, 4))

    def __init__(self, ramp, edge, facets: int = 0, wobble: float = 1.0,
                 shot: str = "bolt"):
        self.ramp = [tuple(int(v) for v in c) for c in ramp]
        self.edge = tuple(int(v) for v in edge)
        self.facets = int(facets)
        self.wobble = float(wobble)
        self.shot = str(shot)

    @property
    def cols(self):
        return self.ramp + [self.edge]

    # ------------------------------------------------------------------ #
    def _core_r(self, ang: float, r: float, phase: float) -> float:
        """그 각도에서 심의 반지름."""
        if self.facets < 0:
            # 전기 — 작고 사납게 일그러진 매듭. 심을 불만큼 크고 둥글게 두면 가지가
            # 아무리 꺾여도 「노란 불덩이에 가시가 붙은 것」으로 보인다. 번개의 몸은
            # 가지에 있고 심은 그 가지들이 만나는 **매듭**일 뿐이다.
            return r * (0.84 + 0.20 * math.sin(5.0 * ang + 2.3 * phase)
                        + 0.12 * math.sin(9.0 * ang - 1.7 * phase))
        if self.facets >= 3:
            # 정n각형 — 각진 면이 있어야 **결정**으로 읽힌다. 천천히 돈다.
            n = self.facets
            step = 2.0 * math.pi / n
            a = (ang + phase * 0.10) % step
            return r * math.cos(math.pi / n) / max(0.35, math.cos(a - math.pi / n))
        w = self.wobble
        return r * (1.0 + 0.09 * w * math.sin(3.0 * ang + phase)
                    + 0.055 * w * math.sin(5.0 * ang - 1.7 * phase))

    def _zig(self, cx, cy, r, a, ln, tw, phase, idx, jag, fork):
        """지그재그 가지 하나 → 꺾인 토막 목록 (전기 전용).

        토막은 `(ax, ay, bx, by, 각, 굵기배수, u0, u1)` 이다. u0~u1 은 **가지 전체에서**
        그 토막이 차지하는 구간이라, 굵기·밝기가 가지를 따라 이어진다.

        ★ 끝마디는 축으로 되돌아온다. 안 그러면 가지 끝이 옆으로 휘어 **갈고리**가 되고,
          여러 갈래가 다 같은 쪽으로 휘어서 번개가 아니라 촉수로 보인다.

        ★ **꺾임의 세기(jag)는 쓰임새마다 다르다.** 하나로 못 박아 봤고 버렸다 —
          0.28 로 통일했더니 모으는 전하는 좋았지만 (1) 터짐은 가지가 서로 겹쳐
          **부챗살이 아니라 얼룩**이 되었고 (2) 날아가는 살은 앞이 어딘지 안 보이는
          **지렁이**가 되었다. 모을 때는 사납게, 날아갈 때는 곧게.
        ★ `fork` 도 같다 — 갈래를 **모든** 가지에 치면 덤불이 되어 실루엣이 통째로 뭉갠다.
          0 은 안 침 · 1 은 다 침 · 2 는 하나 걸러 하나.
        """
        L = r * ln
        n = 3
        ca, sa = math.cos(a), math.sin(a)
        # 씨앗은 각도·갈래번호·phase 로만 만든다 (난수 금지 — 프레임마다 모양이 바뀐다)
        seed = math.sin(a * 12.9898 + idx * 4.1414 + phase * 0.37) * 43758.5453
        pts = [(cx, cy)]
        for i in range(1, n + 1):
            t = i / n
            side = 1.0 if (i % 2) else -1.0
            j = (seed * (i + 1)) % 1.0
            off = L * jag * side * (0.5 + 0.8 * j) * (1.0 - 0.5 * t)
            if i == n:
                off *= 0.30
            pts.append((cx + ca * L * t - sa * off, cy + sa * L * t + ca * off))
        segs = [(pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1],
                 a, tw, i / n, (i + 1) / n) for i in range(n)]
        if fork and ln >= 1.0 and (fork == 1 or idx % fork == 0):
            fa = a + (0.66 if (idx % 2) else -0.66)
            segs.append((pts[1][0], pts[1][1],
                         pts[1][0] + math.cos(fa) * L * 0.46,
                         pts[1][1] + math.sin(fa) * L * 0.46,
                         fa, tw * 0.66, 0.34, 1.0))
        return segs

    def shape(self, out: np.ndarray, cx: float, cy: float, r: float, phase: float,
              spikes=None, lead=(0.0, 0.0), squash: float = 1.0,
              jag: float = 0.28, fork: int = 1) -> np.ndarray:
        """이펙트 하나를 그리고 그 자리 표(bool)를 돌려준다.

        spikes: (각도, 길이배수, 굵기배수) 목록. 각도는 라디안, 0 이 오른쪽.
        lead:   심을 어느 쪽으로 밀지 (진행 방향으로 밀면 앞이 밝아 보인다).
        jag·fork: 전기에서만 쓴다 (`_zig`). 불·얼음은 곧은 토막 하나라 안 본다.
        """
        if r <= 0.7:
            return np.zeros(out.shape[:2], bool)
        spikes = spikes or []
        ch, cw = out.shape[:2]
        reach = int(r * (1.5 + max([s[1] for s in spikes], default=0.0))) + 3
        y0, y1 = max(0, int(cy - reach)), min(ch, int(cy + reach) + 1)
        x0, x1 = max(0, int(cx - reach)), min(cw, int(cx + reach) + 1)
        if y1 <= y0 or x1 <= x0:
            return np.zeros(out.shape[:2], bool)

        icy = self.facets >= 3
        elec = self.facets < 0
        t = np.zeros((y1 - y0, x1 - x0), np.float32)
        hx, hy = cx + lead[0] * r, cy + lead[1] * r
        # 가지를 **토막 목록**으로 미리 펴 둔다 — 픽셀마다 다시 셈하면 몇 배 느려진다.
        # 불·얼음은 심에서 끝까지 곧은 토막 하나, 전기는 꺾인 폴리라인이라 여러 토막이다.
        segs = []
        for i, (a, ln, tw) in enumerate(spikes):
            if elec:
                segs.extend(self._zig(cx, cy, r, a, ln, tw, phase, i, jag, fork))
            else:
                segs.append((cx, cy, cx + math.cos(a) * r * ln,
                             cy + math.sin(a) * r * ln, a, tw, 0.0, 1.0))
        for py in range(y0, y1):
            for px in range(x0, x1):
                ux, uy = px + 0.5 - hx, (py + 0.5 - hy) / squash
                d = math.hypot(ux, uy)
                rr = self._core_r(math.atan2(uy, ux), r, phase)
                v = 1.0 - d / rr
                for ax, ay, bx, by, a, tw, u0, u1 in segs:
                    dd, uu = _seg_dist(px + 0.5, py + 0.5, ax, ay, bx, by)
                    u = u0 + (u1 - u0) * uu
                    if elec:
                        # 번개 — 굵기가 거의 안 준다. 뿌리에서 끝까지 **같은 실**이라야
                        # 「번쩍 그어진 금」으로 보인다. 뾰족하게 깎으면 얼음이 된다.
                        thick = r * tw * (1.0 - u * 0.45)
                        fall = 1.0 - u * 0.22
                    elif icy:
                        # 얼음 — 뿌리에서 끝까지 **곧게** 가늘어진다. 안 흔들린다.
                        thick = r * tw * (1.0 - u * 0.97)
                        fall = 1.0 - u * 0.30
                    else:
                        # 불 — 끝에서 살랑거린다.
                        wob = 1.0 + 0.35 * math.sin(6.0 * u + phase * 1.7 + a * 3.0)
                        thick = r * tw * (1.0 - u * 0.92) * wob
                        fall = 1.0 - u * 0.45
                    if thick > 0.35:
                        v = max(v, (1.0 - dd / thick) * fall)
                t[py - y0, px - x0] = v

        inside = t > 0.0
        for py in range(y1 - y0):
            for px in range(x1 - x0):
                v = t[py, px]
                if v <= 0.0:
                    continue
                for lim, i in self.BANDS:
                    if v > lim:
                        out[y0 + py, x0 + px] = (*self.ramp[i], 255)
                        break

        # 테두리 한 겹 — 없으면 몬스터 위를 지날 때 이펙트가 통째로 묻힌다.
        p = np.pad(inside, 1)
        nb = (p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]
              | p[:-2, :-2] | p[:-2, 2:] | p[2:, :-2] | p[2:, 2:])
        for py, px in zip(*np.nonzero(nb & ~inside)):
            yy, xx = y0 + py, x0 + px
            if 0 <= yy < ch and 0 <= xx < cw and out[yy, xx, 3] == 0:
                out[yy, xx] = (*self.edge, 255)

        full = np.zeros(out.shape[:2], bool)
        full[y0:y1, x0:x1] = inside
        return full

    # ------------------------------------------------------------------ #
    # 세 가지 쓰임새. 무엇을 뜻하는지가 **가지의 방향**에 들어 있다.
    # ------------------------------------------------------------------ #
    def charge(self, out, cx, cy, r, phase, face=1):
        """손 위에서 자라는 것. 가지가 **위로** 오른다 — 아직 안 날아갔다는 뜻."""
        up = -math.pi / 2
        if self.facets < 0:
            # 전기 — 위로 두 갈래가 길게 오르고 아래로 둘이 짧게 튄다.
            # ★ 전부 위로만 뻗으면 불꽃과 실루엣이 같아진다. 번개는 **아무 쪽으로나**
            #   튀되 위쪽이 길다 — 그래야 「손 위에서 모으는 중」이 그대로 읽힌다.
            ss = [(up + 0.26 * math.sin(phase * 0.7), 1.50, 0.26),
                  (up - 0.82, 1.10, 0.21),
                  (up + 0.88, 1.02, 0.21),
                  (up - 2.10, 0.74, 0.17),
                  (up + 2.16, 0.70, 0.17)]
            return self.shape(out, cx, cy, r, phase, ss, lead=(0.0, -0.08), squash=1.0,
                              jag=0.30, fork=1)
        if self.facets >= 3:
            # 얼음 — 육각 결정에서 여섯 갈래가 고르게 뻗는다(눈 결정). 위쪽이 길다.
            ss = []
            for i in range(6):
                a = up + i * math.pi / 3.0 + phase * 0.10
                ln = 1.55 if math.sin(a) < -0.2 else 0.88
                ss.append((a, ln, 0.30))
            # squash>1 = 세로로 길다. 마스터가 손 위에 그려 놓은 얼음조각이 길쭉한
            # 기둥이라, 동글납작하게 그리면 정지 그림과 다른 물건으로 보인다.
            return self.shape(out, cx, cy, r, phase, ss, lead=(0.0, -0.10), squash=1.42)
        ss = [(up + 0.22 * math.sin(phase), 1.35, 0.42),
              (up - 0.55, 0.95, 0.30), (up + 0.62, 0.90, 0.28)]
        return self.shape(out, cx, cy, r, phase, ss, lead=(0.0, -0.10), squash=0.92)

    def dart(self, out, cx, cy, r, phase, face=1):
        """날아가는 탄. 앞은 뾰족하고 꼬리는 **뒤로** 눕는다."""
        fwd = 0.0 if face > 0 else math.pi
        back = fwd + math.pi
        if self.shot == "arrow":
            return self._arrow(out, cx, cy, r, phase, fwd, back)
        if self.facets < 0:
            # 전기 — 앞으로 길게 그어진 금 하나, 뒤로 짧은 스파크 셋.
            # ★ 여기서는 **거의 안 꺾는다**(jag 0.11 · 갈래 없음). 모을 때처럼 사납게
            #   꺾었더니 앞이 어딘지 안 보이는 지렁이가 됐다. 날아가는 것은 곧아야 한다.
            ss = [(fwd, 2.30, 0.32), (back, 1.05, 0.22),
                  (back + 0.60, 0.60, 0.14), (back - 0.60, 0.56, 0.14)]
            return self.shape(out, cx, cy, r, phase, ss, lead=(0.22 * face, 0.0),
                              squash=0.72, jag=0.11, fork=0)
        if self.facets >= 3:
            # 얼음 — 앞으로 긴 창끝 하나, 뒤로 짧은 성엣가지 둘. 납작하게 눌러 빠르게.
            ss = [(fwd, 1.95, 0.34), (back, 1.15, 0.26),
                  (back + 0.42, 0.72, 0.18), (back - 0.42, 0.72, 0.18)]
            return self.shape(out, cx, cy, r, phase, ss, lead=(0.18 * face, 0.0),
                              squash=0.68)
        ss = [(back, 2.30, 0.52), (back + 0.30, 1.35, 0.30), (back - 0.30, 1.30, 0.28)]
        return self.shape(out, cx, cy, r, phase, ss, lead=(0.16 * face, 0.0), squash=0.94)

    def _arrow(self, out, cx, cy, r, phase, fwd, back):
        """번개(또는 무엇이든)로 된 **화살** 한 대 — 살대 · 살촉 · 깃.

        ★ 살대는 **곧게** 긋는다. 전기라고 살대까지 지그재그로 꺾어 봤고 버렸다 —
          꺾인 살대 위에서는 살촉이 묻혀 버려서 그냥 「번개 줄기」가 되고, 활을 든
          캐릭터가 쏜 것이라는 뜻이 사라진다. 꺾임은 **모으는 전하와 터짐**이 맡는다.
        ★ 세 조각을 따로 그려 겹친다. `shape` 의 가지는 늘 심에서 뻗으므로 **살촉의
          미늘**(끝에서 뒤로 젖힌 둘)은 한 번의 호출로는 안 나온다.
        """
        ca, sa = math.cos(fwd), math.sin(fwd)
        m = self.shape(out, cx, cy, r, phase, [(fwd, 2.30, 0.19), (back, 2.05, 0.17)],
                       lead=(0.10 * ca, 0.10 * sa), squash=0.42, jag=0.02, fork=0)
        m |= self.shape(out, cx + ca * r * 2.26, cy + sa * r * 2.26, r * 0.46, phase,
                        [(back + 0.62, 2.4, 0.30), (back - 0.62, 2.4, 0.30)],
                        lead=(0.35 * ca, 0.35 * sa), jag=0.03, fork=0)
        m |= self.shape(out, cx - ca * r * 1.90, cy - sa * r * 1.90, r * 0.26, phase,
                        [(back + 0.80, 2.2, 0.34), (back - 0.80, 2.1, 0.34)],
                        lead=(-0.30 * ca, -0.30 * sa), jag=0.03, fork=0)
        return m

    def burst(self, out, cx, cy, r, phase, face=1):
        """놓는 순간의 터짐.

        ★ 가는 빛살을 사방으로 고르게 뻗으면 **별 반짝이**로 읽힌다 — 실제로 그랬다.
          (1) 가지를 **굵게**, (2) **앞쪽 부챗살**로 몰아서 고친다.
          뒤로는 짧게 둘만 남긴다 — 전부 앞으로 가면 손에서 떨어져 날아간 것으로 보인다.
        """
        base = 0.0 if face > 0 else math.pi
        ss = []
        for i, s in enumerate((-1.0, -0.58, -0.18, 0.18, 0.58, 1.0)):
            a = base + s * 0.95
            if self.facets < 0:
                # 전기 — 길이를 번갈아 주고 굵게. 가지 자체가 꺾이고 갈라지므로
                # 가늘게 두면 부챗살이 아니라 **먼지**가 된다.
                ln = 1.80 if i % 2 == 0 else 1.15
                ss.append((a, ln, 0.30 - 0.06 * abs(s)))
            elif self.facets >= 3:
                # 얼음 — 길이를 **번갈아** 준다. 다 같으면 부채가 아니라 톱니가 된다.
                ln = 1.85 if i % 2 == 0 else 1.25
                ss.append((a, ln, 0.30 - 0.06 * abs(s)))
            else:
                ln = 1.30 + 0.80 * abs(math.sin(2.2 * i + phase))
                ss.append((a, ln, 0.54 - 0.11 * abs(s)))
        w = 0.24 if self.facets < 0 else (0.22 if self.facets >= 3 else 0.36)
        ss.append((base + math.pi + 0.38, 0.85, w))
        ss.append((base + math.pi - 0.38, 0.78, w - 0.02))
        if self.facets < 0:
            # ★ 터짐에서 가지를 꽉 꺾으면 부챗살이 서로 겹쳐 **얼룩**이 된다. 앞쪽으로
            #   몰아 놓은 뜻이 거기서 사라진다. 덜 꺾고 갈래는 하나 걸러 하나만 친다.
            return self.shape(out, cx, cy, r, phase, ss, lead=(0.12 * face, 0.0),
                              jag=0.17, fork=2)
        return self.shape(out, cx, cy, r, phase, ss, lead=(0.12 * face, 0.0))

    def blob(self, out, cx, cy, r, phase):
        """잔상용 작은 덩어리. 가지 없이 하나만 — 잔상에 가지까지 붙이면 지나간 자리가
        여러 개로 보여서 무엇이 진짜인지 흐려진다."""
        return self.shape(out, cx, cy, r, phase, [])

    def motes(self, out, cx, cy, n, spread, rise, seed_phase):
        """떠오르는 부스러기 몇 점(불똥 · 눈발). 고정 씨앗이라 다시 돌려도 같은 자리다."""
        ch, cw = out.shape[:2]
        for i in range(n):
            a = i * 2.39996 + seed_phase          # 황금각 — 뭉치지 않는다
            px = cx + math.cos(a) * spread * (0.45 + 0.55 * ((i * 7 % 5) / 4.0))
            py = cy + math.sin(a) * spread * 0.55 - rise * (0.6 + 0.4 * ((i * 3 % 4) / 3.0))
            ix, iy = int(px), int(py)
            if 0 <= ix < cw and 0 <= iy < ch and out[iy, ix, 3] == 0:
                out[iy, ix] = (*self.ramp[1 + (i % 3)], 255)
