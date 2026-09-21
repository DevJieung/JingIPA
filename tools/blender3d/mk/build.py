#!/usr/bin/env python3
"""요쿨(검) — 2·3·4단계. **덩어리 지오메트리만** 여기 있다.

    env -u DISPLAY bl -b --factory-startup --python tools/blender3d/mk/build.py -- \
        --out build/b3d/jokull/2_model/jokull.blend

★★ 둘째 캐릭터(솔라나)를 만들면서 **일반 부분을 `core.py` 로 갈랐다.**
   여기 남은 것은 요쿨의 덩어리 서른넷뿐이고, 프리미티브·재질·리그·액션·저장은
   `core` 가 한다. 뼈·색·자세는 `rigdef.py`. 결과는 한 픽셀도 안 바뀐다.

## 후보 A 에서 그대로 가져온 것 (이긴 수)
* **강체 뼈 부착** — 덩어리마다 `parent_type='BONE'` + `matrix_parent_inverse`.
* **`aim()` 은 쉬는 자세에서 최소 회전** — 절대 프레임을 새로 지으면 부츠가 뒤바뀐다.
* **Emission + view_transform='Standard' + `hex2linear`** — 팔레트 이탈 0.

## 이 파일이 지는 것
★★ **`pass_index` 로 덩어리마다 번호가 붙고**(`ctx.make` 이 순서대로 준다) 5단계가
그 번호로 내부 선을 긋는다(`lineart.py`). 그래서 **선을 넣고 싶은 곳마다 덩어리를
갈랐다** — 갈기와 후드, 후드와 수염, 수염과 얼굴, 겉옷과 띠, 소매와 소맷부리가
저마다 다른 오브젝트다.
"""
import sys
import math
from pathlib import Path

from mathutils import Matrix

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))
import core                  # noqa: E402
import rigdef as RD          # noqa: E402

_cone, _cube, _sphere, _shell, _taper = (
    core._cone, core._cube, core._sphere, core._shell, core._taper)


def blocks(ctx):
    make, F = ctx.make, ctx.F

    # ---- 망토 : 화면에서 가장 넓은 **어두운** 덩어리 (공식 마스터의 34% 자리)
    #      ★ 몸을 감싸는 곡면 껍질이다. 납작한 판때기로 두면 바닥에 깔린 검은
    #        삼각형(그림자)으로 읽힌다 — 1차에서 실제로 그랬다.
    make("cape", "cape", "cape", lambda bm: (
        _shell(bm, 0.0, 0.03, 1.52, 0.62, 0.44, 0.70, -24, 204, 12),
        _shell(bm, 0.0, 0.03, 0.62, 0.19, 0.70, 0.76, -24, 204, 12)))
    # 망토 밑단의 흰 모피 — 뒤 3면도에 있다. 어두운 덩어리를 바닥에서 끊어 준다
    make("capetrim", "fur", "cape", lambda bm: _shell(
        bm, 0.0, 0.03, 0.21, 0.13, 0.755, 0.76, -24, 204, 12, 0.064))

    # ---- 다리 / 부츠 (발목 뼈에 매단다)
    for sfx, sx in (("R", -0.19), ("L", 0.19)):
        make("shin" + sfx, "dark", "shin" + sfx, lambda bm, s=sfx: _cone(
            bm, 8, 0.115, 0.098, RD.LEN["shin" + s] + 0.05,
            F["shin" + s] @ Matrix.Translation((0, RD.LEN["shin" + s] / 2, 0))
            @ Matrix.Rotation(-math.pi / 2, 4, 'X')))
        make("thigh" + sfx, "dark", "thigh" + sfx, lambda bm, s=sfx: _cone(
            bm, 8, 0.150, 0.122, RD.LEN["thigh" + s] + 0.04,
            F["thigh" + s] @ Matrix.Translation((0, RD.LEN["thigh" + s] / 2, 0))
            @ Matrix.Rotation(-math.pi / 2, 4, 'X')))
        fb = "foot" + sfx
        make("boot" + sfx, "boot", fb, lambda bm, s=sfx, b=fb: (
            _cube(bm, (0.23, 0.30, 0.19), F[b] @ Matrix.Translation((0, 0.10, 0.005))),
            _cube(bm, (0.25, 0.12, 0.10), F[b] @ Matrix.Translation((0, 0.03, 0.075)))))

    # ---- 골반 · 겉옷 치마 : 아래를 넓게 벌려 실루엣의 무게를 준다
    make("skirt", "coat", "hips", lambda bm: _cone(
        bm, 10, 0.55, 0.33, 0.80,
        Matrix.Translation((0, -0.03, 0.70)) @ Matrix.Diagonal((1, 0.84, 1, 1))))
    make("skirthem", "fur", "hips", lambda bm: _cone(
        bm, 10, 0.565, 0.545, 0.12,
        Matrix.Translation((0, -0.03, 0.355)) @ Matrix.Diagonal((1, 0.84, 1, 1))))
    # 겉옷 앞섶 — 어두운 판. 밝은 파랑 한가운데를 끊어 값 대비를 준다
    #  ★★ `Rotation(+90, X)` 이면 판이 **위로** 뻗어 얼굴을 통째로 덮는다(실제로 그랬다).
    #     -90 이어야 허리에서 아래로 흐른다. `_taper` 의 y 는 「그 프레임의 앞쪽」이다.
    make("placket", "dark", "hips", lambda bm: _taper(
        bm, Matrix.Translation((0, -0.30, 1.14)) @ Matrix.Rotation(math.radians(-90), 4, 'X'),
        0.00, 0.76, 0.13, 0.13, 0.32, 0.44))
    # 앞자락 띠 — 얇은 판. 갈라 놓아야 겉옷 한가운데에 선이 생긴다
    make("sash", "sash", "hips", lambda bm: _taper(
        bm, Matrix.Translation((0, -0.335, 1.16)) @ Matrix.Rotation(math.radians(-90), 4, 'X'),
        0.00, 0.70, 0.10, 0.10, 0.165, 0.195))
    make("belt", "belt", "hips", lambda bm: _cone(
        bm, 10, 0.335, 0.340, 0.10,
        Matrix.Translation((0, -0.02, 1.115)) @ Matrix.Diagonal((1, 0.80, 1, 1))))

    # ---- 몸통
    make("torso", "coat", "chest", lambda bm: _cone(
        bm, 10, 0.305, 0.345, 0.40,
        Matrix.Translation((0, -0.05, 1.34)) @ Matrix.Diagonal((1, 0.86, 1, 1))))

    # ---- 팔
    for sfx, sgn in (("R", -1), ("L", 1)):
        a, f, hd = "arm" + sfx, "fore" + sfx, "hand" + sfx
        make(a, "coat", a, lambda bm, a=a: _cone(
            bm, 8, 0.120, 0.104, RD.LEN[a] + 0.05,
            F[a] @ Matrix.Translation((0, RD.LEN[a] / 2, 0))
            @ Matrix.Rotation(-math.pi / 2, 4, 'X')))
        make("elbow" + sfx, "coat", f, lambda bm, f=f: _sphere(
            bm, 6, 3, F[f] @ Matrix.Diagonal((0.108, 0.108, 0.108, 1.0))))
        make(f, "coat", f, lambda bm, f=f: _cone(
            bm, 8, 0.104, 0.092, RD.LEN[f] + 0.04,
            F[f] @ Matrix.Translation((0, RD.LEN[f] / 2, 0))
            @ Matrix.Rotation(-math.pi / 2, 4, 'X')))
        # 소맷부리 모피 — 손 바로 앞. 팔과 손을 갈라 주는 밝은 띠
        make("cuff" + sfx, "fur", f, lambda bm, f=f: _cone(
            bm, 8, 0.118, 0.110, 0.085,
            F[f] @ Matrix.Translation((0, RD.LEN[f] - 0.03, 0))
            @ Matrix.Rotation(-math.pi / 2, 4, 'X')))
        make(hd, "skin", hd, lambda bm, hd=hd: _cone(
            bm, 6, 0.088, 0.076, 0.135,
            F[hd] @ Matrix.Translation((0, 0.05, 0)) @ Matrix.Rotation(-math.pi / 2, 4, 'X')))

    # ---- 어깨 갈기(모피) : 이 캐릭터 실루엣의 절반. 3면도에서 가장 큰 덩어리다
    make("mane", "fur", "chest", lambda bm: (
        _sphere(bm, 10, 6, Matrix.Translation((0, 0.04, 1.395))
                @ Matrix.Diagonal((0.74, 0.47, 0.33, 1.0))),
        _sphere(bm, 8, 5, Matrix.Translation((0, 0.18, 1.235))
                @ Matrix.Diagonal((0.60, 0.38, 0.26, 1.0))),
        # 어깨 봉우리 둘 — 3면도의 「사자 갈기」를 지는 덩어리.
        # ★ 따로 뗐다가 **갈기 위에 선이 그어져** 퍼즐 조각처럼 보였다. 같은 모피니
        #   한 덩어리여야 맞다 — 선은 「뜻이 다른 것」 사이에만 그어야 한다.
        _sphere(bm, 8, 5, Matrix.Translation((-0.50, -0.01, 1.345))
                @ Matrix.Diagonal((0.30, 0.28, 0.23, 1.0))),
        _sphere(bm, 8, 5, Matrix.Translation((0.50, -0.01, 1.345))
                @ Matrix.Diagonal((0.30, 0.28, 0.23, 1.0)))))

    # ---- 머리 · 후드 · 수염 : **셋을 갈라** 흰 덩어리 안에 선이 생기게 한다
    #  ★★ 1차에는 후드 구의 앞끝(y=-0.240)이 얼굴 앞면(y=-0.2525)보다 겨우 0.012m
    #     뒤라 **후드가 얼굴을 통째로 삼켰다.** 3면도의 후드는 뒤통수만 감싼다.
    make("head", "skin", "head", lambda bm: _cube(
        bm, (0.255, 0.225, 0.305), Matrix.Translation((0, -0.165, 1.715))))
    make("eyes", "eye", "head", lambda bm: [
        _cube(bm, (0.040, 0.060, 0.062), Matrix.Translation((ex, -0.262, 1.760)))
        for ex in (-0.120, 0.120)], line=False)
    make("hood", "fur", "head", lambda bm: (
        #  ★★ 후드 구의 **중심 y 가 곧 8방향 검사의 성패**다. 실루엣의 꼭대기가
        #     후드인데, 화면 세로는 `y·sin20 + z·cos20` 이라 꼭대기의 y 가 0 에서
        #     벗어난 만큼 **돌릴 때마다 키가 바뀐다**(0.115m → 3px · 검사선 2px).
        _sphere(bm, 12, 8, Matrix.Translation((0, 0.020, 1.795))
                @ Matrix.Diagonal((0.325, 0.255, 0.250, 1.0))),
        _cone(bm, 8, 0.265, 0.295, 0.20,
              Matrix.Translation((0, 0.100, 1.610)) @ Matrix.Diagonal((1, 0.88, 1, 1)))))
    # ★ 수염은 **아래가 넓다.** 1차에는 거꾸로 뒤집혀 뾰족했다 — 3면도의 수염은
    #   턱에서 가슴까지 퍼지는 덩어리라, 뾰족하면 통째로 딴 사람이 된다.
    make("beard", "beard", "head", lambda bm: _cone(
        bm, 8, 0.200, 0.120, 0.40,
        Matrix.Translation((0, -0.275, 1.450))
        @ Matrix.Rotation(math.radians(-15), 4, 'X')))

    # ---- 대검 (숙제 12번 — SE 는 앞단축이 있어 A 가 줄인 날을 되돌렸다)
    S = F["sword"]
    make("grip", "belt", "sword", lambda bm: _cone(
        bm, 6, 0.042, 0.040, 0.245,
        S @ Matrix.Translation((0, -0.030, 0)) @ Matrix.Rotation(-math.pi / 2, 4, 'X')))
    make("pommel", "steel", "sword", lambda bm: _cube(
        bm, (0.090, 0.090, 0.090), S @ Matrix.Translation((0, -0.170, 0))))
    make("guard", "steel", "sword", lambda bm: _taper(
        bm, S, 0.075, 0.155, 0.455, 0.360, 0.075, 0.060))
    make("blade", "blade", "sword", lambda bm: (
        _taper(bm, S, RD.BLADE_Y0, 0.80, 0.255, 0.175, 0.078, 0.060),
        _taper(bm, S, 0.80, RD.BLADE_Y1, 0.175, 0.030, 0.060, 0.020)))

    # ---- 빈 손의 카드 (설계서 §2 의 결)
    make("card", "steel", "handL", lambda bm: _cube(
        bm, (0.115, 0.014, 0.165),
        F["handL"] @ Matrix.Translation((0.03, 0.11, 0))
        @ Matrix.Rotation(math.radians(18), 4, 'Y')))


if __name__ == "__main__":
    a = core.cli("build/b3d/jokull/2_model/jokull.blend")
    core.run(RD, blocks, a.out)
