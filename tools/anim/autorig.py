#!/usr/bin/env python3
"""정지 그림 한 장에서 **리그 점을 자동으로 잡는다** — ART.md 3·4번을 손 대신.

    python3 tools/anim/autorig.py blaze_wizard
    python3 tools/anim/autorig.py --all          # concepts.json 의 서른 명 전부
    python3 tools/anim/autorig.py blaze_wizard --shoulder 55,31 --tip 89,32   # 손으로 덮어쓰기

내는 것: `build/<id>/` 에 master.png · master_body.png · part_torso.png · part_arm.png ·
rig.json, 그리고 **눈으로 볼 probe.png**(어깨·손끝·소품에 십자를 얹은 그림).

★ **왜 자동으로 잡는가.** 캐릭터가 서른이다. 한 명마다 어깨·손끝·소품 좌표를 눈으로
  찍으면 백 번 가까이 사진을 들여다봐야 한다. 그런데 이 그림들은 자세가 **같다** —
  마법사는 전부 「한쪽 팔을 앞으로 뻗어 시전」이고 궁수·총병은 전부 「소품을 앞으로
  내밀고 겨눔」이다(roster.json 의 pose). 자세가 같으면 좌표도 같은 규칙으로 잡힌다.

★ **그래도 눈으로 봐야 한다.** 자동으로 잡은 것이 맞는지는 픽셀이 아니라 **뜻**의
  문제다 — 「손끝」이 소매 자락 끝일 수도 있고 지팡이 꼭대기일 수도 있다(서리여왕에서
  실제로 자락 끝을 집었다). 그래서 probe.png 를 반드시 내놓고, 틀린 것만 손으로 덮는다.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))          # tools/anim
ROOT = os.path.dirname(os.path.dirname(HERE))              # 저장소 뿌리
CONCEPTS = os.path.join(HERE, "concepts.json")
# ★ 자동이 못 잡는 캐릭터의 **사람이 찍은 좌표**. 여기 없으면 `--all` 을 다시 돌릴 때
#   조용히 사라진다 — build/ 는 gitignore 라 rig.json 이 저장소에 안 남는다.
OVERRIDES = os.path.join(HERE, "rig_overrides.json")

# 속성 → deffect 의 색 갈래. 이펙트를 물로 뗄 때 **옷 쪽으로 안 새게** 하는 최소 조건이다.
HUE = {"fire": "warm", "ice": "cool", "water": "cool", "elec": "any", "none": "any"}


def load_concepts() -> dict:
    with open(CONCEPTS, encoding="utf-8") as f:
        return json.load(f)


def body_mask(path: str) -> np.ndarray:
    return np.array(Image.open(path).convert("RGBA"))[:, :, 3] > 0


def blobs(mask: np.ndarray):
    """이어진 덩어리들을 큰 것부터. (라벨, 픽셀수, 중심) 목록."""
    from scipy import ndimage as nd
    lab, n = nd.label(mask, structure=np.ones((3, 3)))
    out = []
    for i in range(1, n + 1):
        m = lab == i
        ys, xs = np.nonzero(m)
        out.append((m, int(m.sum()), (float(xs.mean()), float(ys.mean()))))
    out.sort(key=lambda t: -t[1])
    return out


def split_effect(mask: np.ndarray):
    """몸과 **손 위의 이펙트**를 가른다. 돌려주는 것: (몸, 이펙트).

    ★ 색으로 가르려던 것을 버렸다. 불씨견습에서 실제로 걸렸다 — 불꽃도 황토색 옷도
      둘 다 `warm`(g>=40 & r-b>=70)이라 `deffect` 의 씨앗이 **두건 하이라이트**에 앉았고,
      거기서 물을 부으니 옷이 통째로 번졌다. ART.md 3번이 「색으로는 못 가른다」고
      적어 둔 그 함정이다.
    ★ 대신 **이어짐**으로 가른다. 이 그림들은 이펙트가 손에서 **떠 있다**(손 위에 뜬
      불덩이 · 얼음 조각 · 전하). 그래서 알파의 이어진 덩어리를 세면 가장 큰 것이 몸이고
      나머지가 이펙트다. 색이 옷과 같아도 상관이 없다.
    ★ 다만 **떠 있는 것이 늘 이펙트는 아니다** — 활 윗고자 · 화살통에서 삐져나온 살 ·
      어깨 너머 망토도 떠 있다. 그래서 **위쪽 60%** 에 있는 것만 이펙트로 친다.
      (아래쪽에 뜬 조각은 소품이다. 지우면 활이 반쪽이 난다)
    """
    bs = blobs(mask)
    if not bs:
        return mask, np.zeros_like(mask)
    body = bs[0][0]
    h = mask.shape[0]
    fx = np.zeros_like(mask)
    for m, n, (cx, cy) in bs[1:]:
        if cy < h * 0.60:
            fx |= m
    return body, fx


def fam_of(motion: str) -> str:
    """동작 이름에서 **무리**만 뽑는다 — `cast_lunge` → `cast` · `draw_snap` → `draw`.

    ★★ **동작 이름으로 직접 비교하지 마라.** 결(variant)이 생기면서(CLAUDE.md 18-5-2)
      `motion == "draw"` 같은 비교가 **조용히 거짓**이 된다. 여기가 특히 위험하다 —
      draw 는 「움직일 팔이 어깨보다 뒤에 있다」는 뜻이 통째로 뒤집히는 자리라
      (아래 두 곳), 비교가 빗나가면 활·총 스물한 명의 팔을 아예 못 찾는다.
      실패가 시끄럽지도 않다: 리그는 그냥 엉뚱한 자리에 잡히고, 클립은 만들어진다.
    """
    return motion.split("_")[0]


def guess_points(body: np.ndarray, fx: np.ndarray, motion: str = "cast") -> dict:
    """어깨 · 손끝 · 소품 자리를 잡는다.

    ★ 뼈대가 되는 관찰: 이 그림들은 **자세가 같다**(roster.json 의 pose).
      · 뻗은 팔은 이펙트가 떠 있는 쪽에 있다. 이펙트에서 가장 가까운 **몸 픽셀**이 손끝이다.
      · 소품은 **반대 손**에 있다(ART.md 0).
      · 어깨는 **팔이 몸통에 붙는 자리**다 — 손끝에서 몸통 쪽으로 되짚어 가며 세로 두께를
        재다가, 두께가 팔의 두 배를 넘는 첫 자리가 몸통의 가장자리다.
        ★ 「위에서 30%」 같은 비율로 못 박으면 안 된다. 불씨견습에서 그렇게 했더니 어깨가
          **두건 꼭대기**에 잡혔다 — 팔보다 위라 팔이 거꾸로 돈다.
    """
    ys, xs = np.nonzero(body)
    y0, y1, x0, x1 = int(ys.min()), int(ys.max()), int(xs.min()), int(xs.max())
    H, W = y1 - y0 + 1, x1 - x0 + 1
    mid_x = (x0 + x1) * 0.5

    # --- 팔이 어느 쪽인가 --------------------------------------------------
    # ★ 「이펙트가 있는 쪽」만으로 정하다가 버렸다. 서른 명 중 절반 가까이가 손 위에
    #   뜬 이펙트가 없다(물동이를 **쥐고** 있거나, 총·대포처럼 아예 없다). 그때 쓰던
    #   되돌림(띠 안에서 더 멀리 나간 쪽)은 옷자락에 걸려 **반대쪽을 골랐다** —
    #   태양사제·빙하신관·폭풍왕이 실제로 그랬다.
    # ★ 대신 **양쪽에서 다 재 보고 더 긴 쪽을 고른다.** 팔은 몸통 밖으로 길게 나온
    #   가는 돌기라서, 어깨를 찾는 셈(아래 run_len 계단)을 양쪽으로 돌리면 팔 쪽이
    #   반드시 더 길게 나온다. 이펙트가 있으면 그쪽에 힘을 실어 준다.
    band_h = 0.18

    def run_len(x: int, yc: int) -> int:
        """x 열에서 y=yc 를 지나는 **세로로 이어진 길이**."""
        if not (0 <= x < body.shape[1]):
            return 0
        col = body[:, x]
        if not col.any():
            return 0
        if not col[yc]:
            idx = np.nonzero(col)[0]
            yc = int(idx[np.argmin(np.abs(idx - yc))])
        a = yc
        while a > 0 and col[a - 1]:
            a -= 1
        c = yc
        while c < len(col) - 1 and col[c + 1]:
            c += 1
        return c - a + 1

    upper = np.zeros_like(body)
    upper[y0:int(y0 + H * 0.62) + 1] = body[y0:int(y0 + H * 0.62) + 1]
    uy, ux = np.nonzero(upper)
    if ux.size == 0:
        uy, ux = np.nonzero(body)

    def measure(sd: str):
        """그 쪽 끝을 손끝으로 보고 어깨까지 되짚는다. (손끝, 어깨x, 팔 길이)."""
        i = int(np.argmax(ux)) if sd == "right" else int(np.argmin(ux))
        t = (int(ux[i]), int(uy[i]))
        st = -1 if sd == "right" else 1
        base = max(3.0, float(np.median([run_len(t[0] + st * k, t[1]) for k in range(2, 7)])))
        sx_ = None
        for j in range(2, int(W)):
            x = t[0] + st * j
            if not (x0 <= x <= x1):
                break
            L = run_len(x, t[1])
            if L <= 0 or L < base * 0.30:
                continue      # 소매가 잠깐 끊긴 자리(멜대·허리끈). 팔 두께를 안 갱신한다.
            if L > max(base * 2.5, base + 18.0):
                sx_ = x
                break
            base = base * 0.7 + L * 0.3
        if sx_ is None:
            sx_ = int(mid_x + (W * 0.16) * (1 if sd == "right" else -1))
        return t, int(np.clip(sx_ - st, x0, x1)), abs(t[0] - sx_)

    cand = {sd: measure(sd) for sd in ("right", "left")}
    if fx.any():
        fy_, fx_ = np.nonzero(fx)
        cy, cx = float(fy_.mean()), float(fx_.mean())
        side = "right" if cx >= mid_x else "left"
    else:
        cy = y0 + H * 0.36
        side = "right" if cand["right"][2] >= cand["left"][2] else "left"
        cx = float(cand[side][0][0])
    tip, sh_x, _ = cand[side]

    band_lo = int(np.clip(tip[1] - H * band_h, y0, y1))
    band_hi = int(np.clip(tip[1] + H * band_h, y0, y1))
    col_s = np.nonzero(body[band_lo:band_hi + 1, sh_x])[0]
    sh_y = int(band_lo + (col_s.mean() if col_s.size else (band_hi - band_lo) * 0.5))
    shoulder = (sh_x, int(np.clip(sh_y, y0, y1)))

    # 소품 — **반대 손**. 손끝과 비슷한 높이대에서 반대쪽 가장 바깥.
    #   ★ 세로를 안 묶으면 옷자락 끝을 집는다(불씨견습에서 실제로 그랬다).
    lo = int(np.clip(tip[1] - H * 0.16, y0, y1))
    hi = int(np.clip(tip[1] + H * 0.30, y0, y1))
    half = np.zeros_like(body)
    half[lo:hi + 1] = body[lo:hi + 1]
    if side == "right":
        half[:, int(mid_x):] = False
    else:
        half[:, :int(mid_x) + 1] = False
    if half.any():
        hy, hx = np.nonzero(half)
        gi = int(np.argmin(hx)) if side == "right" else int(np.argmax(hx))
        grip = (int(hx[gi]), int(hy[gi]))
        band2 = body[:, max(x0, grip[0] - 2):min(x1, grip[0] + 3) + 1]
        cy2 = np.nonzero(band2.any(axis=1))[0]
        ptip = (grip[0], int(cy2.min()) if cy2.size else grip[1])
    else:
        grip = (int(mid_x), int(y0 + H * 0.5))
        ptip = grip

    cut_side = side
    if fam_of(motion) == "draw":
        # ★ **활·총은 뜻이 뒤집힌다** (ART.md 0·「세 번째 캐릭터」).
        #   · 소품(활·총)이 **앞쪽 손**에 있다. 위에서 「손끝」으로 잡은 앞쪽 끝은 사실
        #     활 끝이다.
        #   · **움직일 팔은 시위(방아쇠) 쪽**이라 어깨보다 **뒤에** 있다(만작이라 그렇다).
        #   · 그래서 `cut_arm` 의 자르는 쪽도 **반대**다(ART.md: 「팔이 왼쪽을 보는
        #     캐릭터(만작 궁수)는 --side left」).
        #
        # ★ **여기는 자동으로 못 잡는다. 비율로 찍어 놓고 사람이 고친다.**
        #   세로 줄 길이로 어깨를 찾는 수법이 활에서는 안 듣는다 — 앞쪽 끝에서 되짚어
        #   가면 **활대**의 세로 span 이 먼저 걸려서(짚신궁수 실측: 살 6 → 활대 47)
        #   거기서 멈춘다. 두 팔이 다 앞으로 나가 있어 실루엣만으로는 어느 쪽이 시위
        #   쥔 팔인지 가릴 수가 없다. 그건 픽셀이 아니라 **뜻**의 문제라 사람만 안다.
        #   그래서 뇌전궁수에서 손으로 맞춘 자리를 **비율로** 옮겨 첫 제안으로 삼는다
        #   (90x121 에서 어깨(33,50)·손(24,45)·활(70,46) → 아래 비율).
        #   probe.png 를 보고 틀린 것만 `--shoulder`/`--tip` 으로 덮는다.
        fwd = 1 if side == "right" else -1

        def prop(fx_: float, fy_: float):
            px = x0 + (fx_ if fwd > 0 else 1.0 - fx_) * (W - 1)
            return [int(np.clip(round(px), x0, x1)), int(np.clip(round(y0 + fy_ * (H - 1)), y0, y1))]

        shoulder = tuple(prop(0.37, 0.41))
        tip = tuple(prop(0.27, 0.37))
        grip = prop(0.78, 0.38)
        ptip = prop(0.80, 0.36)
        cut_side = "left" if side == "right" else "right"

    return {"shoulder": [shoulder[0], shoulder[1]], "tip": [tip[0], tip[1]],
            "prop_grip": [grip[0], grip[1]], "prop_tip": [ptip[0], ptip[1]],
            "side": side, "cut_side": cut_side, "bbox": [x0, y0, x1, y1],
            "band": [int(band_lo), int(band_hi)],
            "fx_center": [int(round(cx)), int(round(cy))]}


def probe(master: str, pts: dict, out: str) -> None:
    """어깨·손끝·소품에 십자를 얹은 그림. **이것을 눈으로 본다.**"""
    img = Image.open(master).convert("RGBA")
    z = 4
    big = img.resize((img.width * z, img.height * z), Image.NEAREST)
    d = ImageDraw.Draw(big)
    for key, col in (("shoulder", (255, 60, 60, 255)), ("tip", (60, 255, 120, 255)),
                     ("prop_grip", (80, 160, 255, 255)), ("prop_tip", (255, 220, 60, 255))):
        x, y = pts[key]
        cxp, cyp = (x + 0.5) * z, (y + 0.5) * z
        d.line((cxp - 10, cyp, cxp + 10, cyp), fill=col, width=2)
        d.line((cxp, cyp - 10, cxp, cyp + 10), fill=col, width=2)
    big.save(out)


def load_overrides() -> dict:
    if not os.path.exists(OVERRIDES):
        return {}
    with open(OVERRIDES, encoding="utf-8") as f:
        return {k: v for k, v in json.load(f).items() if not k.startswith("_")}


def one(uid: str, c: dict, args, ov: dict = None) -> int:
    src = os.path.join(ROOT, "art", "units", uid + ".png")
    if not os.path.exists(src):
        print("  !! 정지 그림이 없다: %s" % src)
        return 1
    out = args.out or os.path.join(ROOT, "build", uid)
    os.makedirs(out, exist_ok=True)
    master = os.path.join(out, "master.png")
    Image.open(src).save(master)

    # 1) 손 위 이펙트 떼기 — **이어짐으로** 가른다(split_effect 주석 참고).
    # ★ 표에 적힌 사람의 값을 먼저 깔고, 커맨드라인으로 준 것이 그 위를 덮는다.
    o = dict(ov or {})
    for k in ("deline", "yrange", "cut_side", "lift", "shoulder", "tip", "prop_grip", "prop_tip"):
        if getattr(args, k, ""):
            o[k] = getattr(args, k)

    m_all = body_mask(master)
    bodyp = os.path.join(out, "master_body.png")
    if o.get("deline"):
        r0 = subprocess.run([sys.executable, os.path.join(HERE, "deffect.py"), master, bodyp,
                             "--line", o["deline"]], capture_output=True, text=True)
        if r0.returncode != 0 or not os.path.exists(bodyp):
            print("  !! 선으로 이펙트를 못 뗐다: %s" % (r0.stderr.strip().splitlines() or ["?"])[-1])
            return 1
        m_body = body_mask(bodyp)
        fx = m_all & ~m_body
        note = "선으로 이펙트 %d px 를 뗐다" % int(fx.sum())
    else:
        m_body, fx = split_effect(m_all)
        im = np.array(Image.open(master).convert("RGBA"))
        im[~m_body] = 0
        Image.fromarray(im).save(bodyp)
        note = ("이펙트 %d px 를 뗐다" % int(fx.sum())) if fx.any() else "손 위 이펙트가 없다"

    pts = guess_points(m_body, fx, c.get("motion", "cast"))
    for k in ("shoulder", "tip", "prop_grip", "prop_tip"):
        if o.get(k):
            pts[k] = [int(x) for x in o[k].split(",")]
    if o.get("cut_side"):
        pts["cut_side"] = o["cut_side"]
    # ★★ **손끝을 손으로 덮었으면 팔이 지나는 띠도 다시 잰다.**
    #   `band` 는 guess_points 가 **자동으로 잡은 손끝**을 가운데로 삼아 만든다. 그런데
    #   손으로 덮는 경우는 언제나 그 자동 손끝이 틀렸을 때다 — 그대로 두면 띠가 옛
    #   (틀린) 손끝 둘레에 남아서, 어깨가 띠 **밖**에 놓이고 `cut_arm` 이 팔에 물을 부을
    #   씨앗을 못 찾아 통째로 실패한다.
    #   실제로 그랬다: bolt_lantern 은 자동 손끝이 등롱 꼭대기(y 13)라 띠가 [0,31] 인데
    #   사람이 찍은 어깨는 y 35 였다. 덮어 놓고도 「어깨에서 팔을 못 찾았다」로 죽었고,
    #   그 실패가 좌표를 잘못 찍은 것처럼 보여서 한참 헤맸다.
    if o.get("tip") and "band" in pts:
        bx0, by0, bx1, by1 = pts["bbox"]
        bh = by1 - by0 + 1
        ty = int(pts["tip"][1])
        pts["band"] = [int(max(by0, ty - bh * 0.18)), int(min(by1, ty + bh * 0.18))]

    # 2) 몸통 / 팔 가르기 — 어깨에서 아래로 비스듬히 긋는다.
    x0, y0, x1, y1 = pts["bbox"]
    H = y1 - y0 + 1
    sx, sy = pts["shoulder"]
    cs = pts.get("cut_side", pts["side"])
    lean = 3 if cs == "right" else -3
    # ★ 자르는 선을 **어깨보다 조금 위**에서 시작한다. 어깨 높이에서 시작하면 겨드랑이
    #   위쪽(어깨 덮개·견갑)이 몸통에 남아 팔만 돌 때 어깨에 구멍이 뚫린다.
    # ★ 아래끝은 **팔이 실제로 지나는 띠**까지만 내린다(band). 예전엔 어깨에서 0.30H 를
    #   못 박았는데, 그러면 망토·긴 자락이 있는 캐릭터에서 선이 **망토를 가로질러**
    #   그 조각이 팔에 딸려 돌고 자리에 곧은 이음매가 남는다 — 스페이드왕이 실제로
    #   망토 한가운데가 가로로 잘려 나갔다.
    # ★ 띠로 조이는 것은 **cast(마법사)만**이다. draw(활·총)는 움직일 팔이 어깨보다
    #   뒤에 있어서 띠가 시위 쥔 손을 감싸는데, 그 띠로 자르면 팔에 물을 부을 씨앗을
    #   못 찾아 통째로 실패한다(화승총병·뇌전궁수·별빛쇠뇌·왕실총사가 실제로 그랬다).
    band = pts.get("band", [sy - int(H * 0.06), sy + int(H * 0.30)])
    if fam_of(c.get("motion", "cast")) == "cast":
        c_lo = int(min(band[0], sy - int(H * 0.06)))
        c_hi = int(band[1])
    else:
        c_lo = sy - int(H * 0.06)
        c_hi = sy + int(H * 0.30)
    if o.get("yrange"):
        c_lo, c_hi = (int(v) for v in o["yrange"].split(","))
    cut = "%d@%d,%d@%d" % (sx, c_lo, sx + lean, c_hi)
    yr = "%d,%d" % (max(y0, c_lo), min(y1, c_hi))
    r2 = subprocess.run([sys.executable, os.path.join(HERE, "cut_arm.py"), bodyp,
                         "--shoulder", "%d,%d" % (sx, sy), "--cut", cut, "--yrange", yr,
                         "--side", cs, "--tip", "%d,%d" % (pts["tip"][0], pts["tip"][1]),
                         "--out", out], capture_output=True, text=True)
    ok = r2.returncode == 0
    if not ok:
        print("  !! 팔 가르기 실패: %s" % (r2.stderr.strip().splitlines()[-1] if r2.stderr.strip() else "?"))

    rig = os.path.join(out, "rig.json")
    cur = {}
    if os.path.exists(rig):
        with open(rig, encoding="utf-8") as f:
            cur = json.load(f)
    # ★ 이펙트가 손끝에서 **어디에 떠 있었는지**(lift)도 적어 둔다. mkanim 이 클립마다
    #   이펙트를 다시 그릴 때 그 자리를 그대로 써야, 아이들이 정지 그림과 안 어긋난다
    #   (docs/ART.md 6 「idle — 정지 스프라이트와 같은 자세여야 한다」).
    lift = [int(pts["fx_center"][0] - pts["tip"][0]), int(pts["fx_center"][1] - pts["tip"][1])]
    if o.get("lift"):
        lift = [int(v) for v in o["lift"].split(",")]
    cur.update({"shoulder": pts["shoulder"], "tip": pts["tip"],
                "prop_grip": pts["prop_grip"], "prop_tip": pts["prop_tip"],
                "fx_center": pts["fx_center"], "lift": lift,
                "has_fx": bool(fx.any())})
    with open(rig, "w", encoding="utf-8") as f:
        json.dump(cur, f, ensure_ascii=False, indent=1)

    probe(master, pts, os.path.join(out, "probe.png"))
    arm_px = int(np.array(Image.open(os.path.join(out, "part_arm.png")).convert("RGBA"))[:, :, 3].astype(bool).sum()) \
        if os.path.exists(os.path.join(out, "part_arm.png")) else 0
    total = int(m_body.sum())
    frac = arm_px / max(1, total)
    flag = ""
    # ★ 팔이 몸의 5% 밑이면 못 찾은 것이고 30% 위면 몸통을 통째로 집은 것이다.
    #   둘 다 프레임에서 바로 보이지만, 여기서 세어 두면 서른 장을 다 볼 필요가 없다.
    if frac < 0.05 or frac > 0.30:
        flag = "  ★눈으로 봐라"
    print("  %-18s %s · 팔 %d px (%.0f%%) · 어깨%s 손끝%s%s"
          % (uid, note, arm_px, frac * 100, tuple(pts["shoulder"]), tuple(pts["tip"]), flag))
    return 0 if ok else 1


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("name", nargs="?", default="")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--out", default="")
    ap.add_argument("--box", default="")
    ap.add_argument("--shoulder", default="")
    ap.add_argument("--tip", default="")
    ap.add_argument("--prop_grip", default="")
    ap.add_argument("--prop_tip", default="")
    # ★ 팔을 어느 쪽으로 자를지도 손으로 덮을 수 있어야 한다. 활·총은 「움직일 팔이
    #   어깨보다 뒤」라 자동이 반대쪽을 고르는데, 총열이 길어 테두리 상자가 총 쪽으로
    #   늘어난 캐릭터(왕실총사·별빛쇠뇌)는 그 셈이 어긋난다.
    ap.add_argument("--cut_side", default="", choices=["", "right", "left"])
    # ★ 자르는 띠도 손으로 덮을 수 있어야 한다. 소매가 길게 늘어진 옷(기우사제·해무사제)은
    #   팔이 손끝 높이 ±0.18H 를 훌쩍 넘어 아래로 처져 있어서, 자동 띠로 자르면
    #   **소매 아랫자락이 몸통에 남아** 팔만 돌 때 소매가 찢어진다.
    ap.add_argument("--yrange", default="", help="lo,hi — 자르는 띠(마스터 y 좌표)")
    # ★ 이펙트가 손끝에서 어디에 뜨는지도 손으로 덮을 수 있어야 한다. 이펙트가 손에
    #   **붙어 있는** 그림(혜성사제·물지게꾼)은 떠 있는 덩어리로 안 잡혀서 자동 lift 가
    #   엉뚱한 한두 픽셀에서 나온다.
    ap.add_argument("--lift", default="", help="dx,dy — 손끝에서 이펙트까지")
    # ★ **막대 모양 이펙트는 이어짐으로 못 뗀다** (docs/ART.md 3). 손에서 뻗어 나가는
    #   번개 줄기·메긴 살·창은 손과 **붙어 있어서** 덩어리 셈에 안 걸린다. 그런 것은
    #   양 끝을 아는 곧은 선이므로 `deffect.py --line` 으로 뗀다. 그 인자를 그대로 넘긴다.
    ap.add_argument("--deline", default="", help="deffect 의 --line 인자 (막대 이펙트)")
    a = ap.parse_args()
    cs = load_concepts()
    names = list(cs) if a.all else [a.name]
    if not names or not names[0]:
        raise SystemExit("이름을 주거나 --all")
    ovs = load_overrides()
    bad = 0
    for n in names:
        if n not in cs:
            print("  !! concepts.json 에 %s 가 없다" % n)
            bad += 1
            continue
        bad += one(n, cs[n], a, ovs.get(n))
    print("끝 — %d/%d 성공" % (len(names) - bad, len(names)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
