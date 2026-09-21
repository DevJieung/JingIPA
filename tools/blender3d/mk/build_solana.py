#!/usr/bin/env python3
"""솔라나(활 · 불) — 2·3·4단계. **덩어리 지오메트리만** 여기 있다.

    env -u DISPLAY bl -b --factory-startup --python tools/blender3d/mk/build_solana.py -- \
        --out build/b3d/solana/2_model/solana.blend

프리미티브 · 재질 · 리그 · 액션 · 저장은 `core.py` 가 그대로 한다(요쿨과 **같은 코드**).
뼈 · 색 · 자세는 `rigdef_solana.py`. 여기 있는 것은 덩어리 서른다섯뿐이다.

## 요쿨의 `build.py` 와 무엇이 다른가
* **좌표계**가 다르다 — 여기서는 `scr(a,d,z)` 로 **화면 좌표**에 바로 짓는다.
  `a` 가 화면 가로 · `z` 가 화면 세로라, 원화를 픽셀로 재서 그대로 옮겨 적었다.
* **다리·부츠·망토·후드·수염·대검이 통째로 없고**, 대신 치마·자락·불붙은 밑단·
  해맞이 관·활채·시위·카드가 생겼다. 재사용한 덩어리는 **팔 열 개뿐**이다.
* `_ribbon()` 을 새로 넣었다(`core`) — 활채처럼 **휜 것**은 `_taper` 를 이어 붙이면
  이음매마다 검은 점이 생긴다. 96px 에서 점 하나는 흠집이다.

## 내부 선화 (숙제 10번) — 같은 손잡이를 쓴다
선은 **덩어리와 덩어리의 경계**에만 그어지므로(`lineart.py`), 「선을 넣고 싶은 곳마다
덩어리를 나눈다」. 여기서 나눈 자리: 관/머리카락/얼굴 · 목깃/몸통 · 몸통/앞섶 ·
치마/불붙은 밑단/불꽃 혀 · 소매/소맷부리/손 · 활채/손잡이/시위.
"""
import sys
import math
from pathlib import Path

from mathutils import Matrix, Vector

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))
import core                       # noqa: E402
import rigdef_solana as RD        # noqa: E402

_cone, _cube, _sphere, _shell, _taper, _ribbon = (
    core._cone, core._cube, core._sphere, core._shell, core._taper, core._ribbon)

R2 = math.sqrt(0.5)
#: 화면 좌표계의 밑틀 — 열이 (a, d, z) 다.
BASIS = Matrix(((R2, -R2, 0.0), (R2, R2, 0.0), (0.0, 0.0, 1.0))).transposed().to_4x4()


def scr(a=0.0, d=0.0, z=0.0):
    """원점이 (a,d,z) 인 **화면 프레임**. x=가로 · y=깊이 · z=세로."""
    M = BASIS.copy()
    M.translation = Vector(RD.P(a, d, z))
    return M


def AX(z):
    """세로축에 붙는 축대칭 덩어리용 (관·치마·띠). 원점은 몸 한가운데."""
    return Matrix.Translation((0.0, 0.0, z))


def spike(bm, ang, r, z0, tilt, L, r1, r2, seg=5):
    """세로축 둘레에 방사로 뻗는 뿔 하나 — 불꽃 혀 · 관의 햇살.

    `ang` 은 세로축 둘레의 각(도) · `tilt` 은 세로에서 바깥으로 눕는 각(도).
    ★ **축대칭으로 두는 것이 중요하다.** 실루엣의 꼭대기가 관이라, 한쪽으로
      치우치면 화면 세로가 `0.2419(d-a)+0.9397z` 인 탓에 **yaw 마다 키가 바뀐다**
      (검사 11번의 한도가 2px 다 — 요쿨의 후드가 거기서 겨우 통과했다).
    """
    a = math.radians(ang)
    M = (Matrix.Translation((r * math.cos(a), r * math.sin(a), z0))
         @ Matrix.Rotation(a, 4, 'Z')
         @ Matrix.Rotation(math.radians(tilt), 4, 'Y')
         @ Matrix.Translation((0.0, 0.0, L / 2.0)))
    _cone(bm, seg, r1, r2, L, M)


def blocks(ctx):
    make, F = ctx.make, ctx.F

    # ================================================================ 치마
    # ★ 이 캐릭터 실루엣의 **절반**이다. 원화의 76~100줄이 통째로 치맛자락이고,
    #   다리는 한 픽셀도 안 보인다. 요쿨의 「망토」가 있던 자리를 이것이 진다.
    make("skirt", "gown", "skirt", lambda bm: _cone(
        bm, 14, 0.520, 0.215, 1.20, AX(0.62)))
    # 그늘 쪽 결 — 넓은 진홍 한복판을 끊어 값 대비를 준다. 없으면 96px 에서
    # 치마가 **붉은 판때기 한 장**이 된다(요쿨의 「망토가 검은 삼각형」과 같은 함정).
    make("skirtdk", "gowndk", "skirt", lambda bm: _shell(
        bm, 0.0, 0.0, 1.10, 0.06, 0.250, 0.512, 96, 214, 10, 0.030))

    # ---- 타들어 가는 밑단 : 아래로 갈수록 뜨겁다 (원화 78~100줄)
    make("hem", "flamehot", "skirt", lambda bm: _cone(
        bm, 14, 0.524, 0.455, 0.26, AX(0.15)))
    make("emb", "flame", "skirt", lambda bm: _cone(
        bm, 14, 0.455, 0.388, 0.25, AX(0.405)))
    # 불꽃 혀 — 치마 위로 핥아 올라간다. **덩어리를 따로 떼야** 사이에 선이 생긴다
    make("tongue", "ember", "skirt", lambda bm: [
        spike(bm, ang, 0.360 - 0.02 * (k % 2), 0.50, 6.0,
              0.26 + 0.10 * ((k * 5) % 3), 0.062, 0.010)
        for k, ang in enumerate(range(0, 360, 36))])

    # ---- 뒤로 끄는 자락 : 화면 왼쪽·안쪽으로 흐른다 (원화 90~100줄의 왼쪽 끝)
    make("train", "gowndk", "train", lambda bm: (
        _shell(bm, 0.0, 0.0, 1.02, 0.28, 0.25, 0.52, 66, 208, 10, 0.045),
        _shell(bm, 0.0, 0.0, 0.28, 0.03, 0.52, 0.60, 66, 208, 10, 0.045)))
    make("trainhem", "ember", "train", lambda bm: _shell(
        bm, 0.0, 0.0, 0.16, 0.03, 0.578, 0.604, 66, 208, 10, 0.052))

    # ================================================================ 몸통
    make("bodice", "gown", "chest", lambda bm: _cone(
        bm, 12, 0.235, 0.268, 0.36, AX(1.40) @ Matrix.Diagonal((1, 0.80, 1, 1))))
    # 앞섶 — 어두운 판. 가슴 한가운데를 세로로 끊는다
    make("placket", "gowndk", "chest", lambda bm: _taper(
        bm, scr(0.0, -0.185, 1.58) @ Matrix.Rotation(math.radians(-90), 4, 'X'),
        0.0, 0.40, 0.070, 0.086, 0.180, 0.205))
    make("belt", "gold", "hips", lambda bm: _cone(
        bm, 12, 0.244, 0.250, 0.085, AX(1.205) @ Matrix.Diagonal((1, 0.82, 1, 1))))
    make("collar", "gold", "chest", lambda bm: _cone(
        bm, 12, 0.205, 0.140, 0.085, AX(1.575) @ Matrix.Diagonal((1, 0.86, 1, 1))))

    # ================================================================ 팔 (열 개)
    # ★ 요쿨에서 **모양만** 그대로 가져온 자리다 — 숫자는 다 다르지만 짜임새가 같다.
    for sfx, sh in (("L", "armL"), ("R", "armR")):
        a, f, hd = "arm" + sfx, "fore" + sfx, "hand" + sfx
        make(a, "gown", a, lambda bm, a=a: _cone(
            bm, 8, 0.098, 0.082, RD.LEN[a] + 0.04,
            F[a] @ Matrix.Translation((0, RD.LEN[a] / 2, 0))
            @ Matrix.Rotation(-math.pi / 2, 4, 'X')))
        make("elbow" + sfx, "gown", f, lambda bm, f=f: _sphere(
            bm, 6, 3, F[f] @ Matrix.Diagonal((0.086, 0.086, 0.086, 1.0))))
        make(f, "gown", f, lambda bm, f=f: _cone(
            bm, 8, 0.082, 0.070, RD.LEN[f] + 0.03,
            F[f] @ Matrix.Translation((0, RD.LEN[f] / 2, 0))
            @ Matrix.Rotation(-math.pi / 2, 4, 'X')))
        # 금 소맷부리 — 소매와 손을 갈라 주는 밝은 띠
        make("cuff" + sfx, "gold", f, lambda bm, f=f: _cone(
            bm, 8, 0.090, 0.082, 0.070,
            F[f] @ Matrix.Translation((0, RD.LEN[f] - 0.022, 0))
            @ Matrix.Rotation(-math.pi / 2, 4, 'X')))
        make(hd, "skin", hd, lambda bm, hd=hd: _cone(
            bm, 6, 0.066, 0.058, 0.115,
            F[hd] @ Matrix.Translation((0, 0.045, 0))
            @ Matrix.Rotation(-math.pi / 2, 4, 'X')))
    # ★ 어깨의 금 견장은 **뺐다.** 구가 어깨 위에서 빛을 등져 96px 에서 「검은
    #   네모 구멍」으로 보였다(사진으로 확인). 금은 목깃과 소맷부리로 충분하다.

    # ================================================================ 머리
    # ★★ 얼굴은 **화살 축에서 45도 카메라 쪽으로 튼다.** 순수 옆모습이면 눈이
    #    모서리 한 줄로 사라진다(`spec.GAME_DIR` 주석이 후보 B 의 다섯 판을 그렇게
    #    날렸다고 적어 둔 그 함정). 몸통은 정면이고 얼굴만 3/4 다 — 원화와 같다.
    HF = scr(0.0, 0.0, 1.745) @ Matrix.Rotation(math.radians(-45), 4, 'Z')
    make("head", "skin", "head", lambda bm: (
        _cube(bm, (0.258, 0.238, 0.310), HF),
        _cube(bm, (0.070, 0.080, 0.086), HF @ Matrix.Translation((0.146, -0.012, -0.030)))))
    make("eyes", "eye", "head", lambda bm: [
        #  ★ 얼굴 앞면이 +0.129 라 눈이 0.118 이면 **0.28px 만 튀어나온다** — 안 보인다.
        #    0.132 로 밀어 1.2px 을 확보했다(96px 에서 눈은 그만큼이 전부다).
        _cube(bm, (0.038, 0.036, 0.048), HF @ Matrix.Translation((0.132, ey, 0.040)))
        for ey in (-0.072, 0.070)], line=False)
    # 틀어올린 머리 — 얼굴과 관 사이의 어두운 띠. 이것이 없으면 금관이 살빛에
    # 바로 붙어서 96px 에서 **머리통 하나**로 뭉친다
    make("hair", "hair", "head", lambda bm: (
        #  ★★ 구의 **앞끝이 얼굴 앞면(+0.129)을 넘으면 안 된다.** 1차에는 중심 -0.055 에
        #     반지름 0.165 라 앞끝이 +0.110 이었고, 얼굴이 0.019m 만 남아 96px 에서
        #     **검은 구멍**이 됐다. 요쿨의 후드가 낸 사고와 같은 것이다.
        _sphere(bm, 10, 6, HF @ Matrix.Translation((-0.105, 0.0, 0.055))
                @ Matrix.Diagonal((0.118, 0.138, 0.168, 1.0))),
        _cone(bm, 10, 0.132, 0.104, 0.12, AX(1.888))))

    # ---- 해맞이 관 : 원화에서 키의 5분의 1을 먹는다. 이 캐릭터의 이름표다
    make("crownband", "gold2", "crown", lambda bm: (
        _cone(bm, 12, 0.172, 0.152, 0.080, AX(1.905)),
        _cone(bm, 12, 0.148, 0.122, 0.060, AX(1.978))))
    make("crownray", "gold", "crown", lambda bm: [
        spike(bm, ang, 0.086, 1.992, 30.0 + 5.0 * (k % 2),
              0.205 + 0.030 * (k % 2), 0.075, 0.020, seg=4)
        for k, ang in enumerate(range(0, 360, 60))])

    # ================================================================ 활
    # ★ 뼈 프레임 그대로 쓴다 — y 가 화살 축 · z 가 활채가 서는 쪽 · x 가 깊이.
    #   그래서 **활채의 넓은 면이 화면과 나란**하다(요쿨은 `UP_HINT` 로 억지로 맞췄다).
    B = F["bow"]
    TY, BH = RD.TIP_Y, RD.BOW_H
    limb = [(0.02, 0.12), (0.08, 0.30), (0.135, 0.470), (0.125, 0.595), (TY, BH)]
    make("bowU", "gold", "bow", lambda bm: _ribbon(
        bm, B, limb, [0.062, 0.055, 0.046, 0.036, 0.026], 0.045))
    make("bowD", "gold", "bow", lambda bm: _ribbon(
        bm, B, [(y, -z) for (y, z) in limb], [0.062, 0.055, 0.046, 0.036, 0.026], 0.045))
    # 손잡이 — 활채와 다른 재질이라 한가운데에 선이 생긴다
    make("riser", "gold2", "bow", lambda bm: _taper(
        bm, B @ Matrix.Rotation(math.radians(90), 4, 'X'),
        -0.155, 0.155, 0.085, 0.085, 0.062, 0.062, 0.012, 0.012))

    # ---- 시위 : **`nock` 뼈의 크기가 곧 당김 깊이다**(rigdef_solana 3번)
    #      ★ 뼈 머리가 활채 끝의 y 라, 크기를 키워도 시위 끝은 활채에 붙어 있고
    #        매듭만 뒤로 물러난다. 산수로 그렇게 떨어진다.
    apex = (TY - RD.NOCK_D, 0.0)
    #  ★★ 재질이 `steel` 이면 안 된다. 강철의 빛 칸(#ccc8d4)이 이 화면에서 **가장
    #     밝은 색**이라, 1차 렌더에서 시위가 활보다 세게 읽혀 **칼을 든 것처럼**
    #     보였다(사진으로 확인). 시위는 어둡고 가늘어야 활채가 주인공이 된다.
    make("stringU", "gowndk", "nock", lambda bm: _ribbon(
        bm, B, [(TY, BH), apex], 0.028, 0.022))
    make("stringD", "gowndk", "nock", lambda bm: _ribbon(
        bm, B, [(TY, -BH), apex], 0.028, 0.022))
    # 시위에 메긴 **빛나는 카드** — 설계서 §2 「무기는 응결된 카드」. 로스터의
    # `prompt` 가 「strung with a glowing card」라 화살 대신 이것이 메겨 있다.
    #  ★ 넓은 면(z·x)으로 세워 둔다. 뼈 크기는 y 로만 늘어나므로 **두께만** 변한다 —
    #    카드가 당길 때마다 커지는 사고를 산수로 막는다.
    make("card", "card", "nock", lambda bm: _taper(
        bm, B @ Matrix.Translation((0.0, apex[0], 0.0))
        @ Matrix.Rotation(math.radians(90), 4, 'X'),
        -0.085, 0.085, 0.115, 0.115, 0.016, 0.016))


if __name__ == "__main__":
    a = core.cli("build/b3d/solana/2_model/solana.blend")
    core.run(RD, blocks, a.out)
