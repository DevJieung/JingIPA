#!/usr/bin/env python3
"""후보 A · 2·3·4단계 — 메시 + 재질 + 리그 + 액션을 짜서 .blend 로 굽는다.

    env -u DISPLAY bl -b --factory-startup --python tools/blender3d/cand_a/build.py -- \
        --out build/b3d/cand_a/2_model/jokull.blend

## 이 후보가 다른 둘과 다른 점 — **프리미티브 덩어리를 뼈에 강체로 문다**
스키닝(자동 웨이트)을 아예 안 쓴다. 덩어리마다 `parent_type='BONE'` 으로 뼈 하나에
통째로 매달고, `matrix_parent_inverse` 로 쉬는 자세에서 제자리에 서게 한다.

  ★ **강점** — 관절이 절대 안 뭉개진다. 96px 에서 어깨가 찌그러지거나 팔꿈치가
    풍선처럼 부푸는 일이 원리상 없다. 그리고 덩어리마다 재질이 하나씩이라
    툰 램프가 재질별로 3톤을 정확히 갖는다(팔레트 이탈이 0 이 되는 까닭).
  ★ **약점** — 관절에 **틈이 벌어진다.** 두 가지로 막았다:
      1. **겹치기** — 아랫마디의 머리 쪽 반지름을 윗마디보다 크게 잡아
         두 원기둥이 서로의 살 속으로 파고들게 했다.
      2. **구 관절** — 팔꿈치·무릎에 6x3 짜리 작은 구를 하나씩 얹어 회전축을 덮는다.
    이 둘로도 **90도를 넘게 접으면 안쪽에 홈이 보인다.** 그래서 공격 자세의
    팔꿈치를 70도 안쪽으로 묶었다 — 후보 A 가 낸 **연출상의 값**이다.

## 좌표
캐릭터는 -Y 를 본다(정면). 아마추어 오브젝트를 yaw +90도 돌리면 spec.GAME_DIR="E".
**모든 덩어리는 월드 좌표로 짠다.** 오브젝트 변환은 항등이고 메시 정점이 곧 월드
좌표라, 뼈 부모의 `matrix_parent_inverse` 만 제대로 넣으면 쉬는 자세에서 한 톨도
안 움직인다(실측으로 확인했다).
"""
import sys, os, math, json, argparse
from pathlib import Path

import bpy, bmesh
from mathutils import Matrix, Vector

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))
import rigdef as RD          # noqa: E402
import spec                  # noqa: E402


# ---------------------------------------------------------------- 뼈 좌표계
def frame_of(direction, up_hint=(0, 0, 1)):
    """`aim()` 과 **똑같은 규칙**으로 정규 직교 프레임을 만든다.

    ★ 두 곳이 다르면 쉬는 자세로 겨눴을 때 덩어리가 **제자리에서 비틀린다.**
      칼날이 종잇장처럼 옆날로 서는 사고가 정확히 여기서 난다.
    """
    y = Vector(direction).normalized()
    up = Vector(up_hint) if abs(y.z) < 0.95 else Vector((0, 1, 0))
    x = up.cross(y).normalized()
    z = y.cross(x).normalized()
    return x, y, z


def author_frame(name):
    """덩어리를 **짜 넣을 때** 쓰는 프레임 (원점=뼈 머리 · y=뼈 방향 · up=+Z).

    ★★ 이것은 블렌더가 들고 있는 뼈의 쉬는 프레임과 **다르다**(블렌더의 롤은
      `align_roll` 이 정한다). 그래도 되는 까닭은 덩어리를 **월드 좌표로 짜서
      강체로 매달기** 때문이다 — 부모 프레임이 어떻든 쉬는 자세에서는 제자리에
      있고, 뼈가 돌면 통째로 따라 돈다.

    ★★★ 다만 **`aim()` 이 절대 프레임을 새로 지어 넣으면 그 순간 깨진다.**
      실제로 그렇게 만들었다가 「쉬는 방향으로 겨눴을 뿐인데」 덩어리가 뼈 축을
      따라 비틀렸다 — 실측으로 **부츠가 x 로 0.30m 옮겨 가 왼발과 오른발이
      자리를 바꿨다**(눈으로는 멀쩡해 보였다. 좌우가 거의 대칭이라서).
      그래서 `aim()` 은 **쉬는 자세에서 최소 회전**만 한다(아래).
    """
    for (n, h, t, _p, _c) in RD.BONES:
        if n == name:
            x, y, z = frame_of(Vector(t) - Vector(h))
            M = Matrix((x, y, z)).transposed().to_4x4()
            M.translation = Vector(h)
            return M
    raise KeyError(name)


# ---------------------------------------------------------------- 프리미티브
def _cone(bm, seg, r1, r2, depth, M, caps=True):
    bmesh.ops.create_cone(bm, cap_ends=caps, cap_tris=False, segments=seg,
                          radius1=r1, radius2=r2, depth=depth, matrix=M)


def _cube(bm, size, M):
    s = Matrix.Diagonal((size[0], size[1], size[2], 1.0))
    bmesh.ops.create_cube(bm, size=1.0, matrix=M @ s)


def _sphere(bm, u, v, M):
    bmesh.ops.create_uvsphere(bm, u_segments=u, v_segments=v, radius=1.0, matrix=M)


def _taper(bm, M, y0, y1, w0, w1, t0, t1, cz0=0.0, cz1=0.0):
    """뼈 공간에서 y0→y1 로 뻗는 **가늘어지는 상자**.
    `w` 는 뼈 z 방향(망토는 「뒤로」, 칼은 「날의 넓은 면」), `t` 는 뼈 x 방향,
    `cz` 는 z 중심을 밀어 주는 값이다 — 토막을 여러 개 이어 **휘어진 드리움**을 만든다.

    ★ 칼날이 이것이다. 8정점 6면 = 12삼각형. 96px 에서 날이 안 끊기려면
      실제보다 두껍게 잡아야 한다(w0 0.175m = 7px).
    """
    P = []
    for (y, w, t, cz) in ((y0, w0, t0, cz0), (y1, w1, t1, cz1)):
        for sz in (-1, 1):
            for sx in (-1, 1):
                P.append(M @ Vector((sx * t / 2, y, sz * w / 2 + cz)))
    vs = [bm.verts.new(p) for p in P]
    bm.verts.ensure_lookup_table()
    q = lambda *i: bm.faces.new([vs[k] for k in i])
    q(0, 1, 3, 2)          # y0 면
    q(6, 7, 5, 4)          # y1 면
    q(0, 4, 5, 1)          # z-
    q(2, 3, 7, 6)          # z+
    q(0, 2, 6, 4)          # x-
    q(1, 5, 7, 3)          # x+


def obj_from(bm, name, mat, arm, bone_name):
    """bmesh 를 오브젝트로 굳히고 **뼈에 강체로** 매단다."""
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    bone = arm.data.bones[bone_name]
    ob.parent = arm
    ob.parent_type = 'BONE'
    ob.parent_bone = bone_name
    # ★ 이 한 줄이 「강체 부착」의 전부다. 쉬는 자세에서 월드 항등이 되게 만든다.
    ob.matrix_parent_inverse = (
        arm.matrix_world @ bone.matrix_local
        @ Matrix.Translation((0, bone.length, 0))).inverted()
    return ob


# ---------------------------------------------------------------- 재질
def toon_mat(name, shadow, mid, light):
    """Diffuse → ShaderToRGB → ValToRGB(CONSTANT) → Emission → Output.

    ★ Emission 으로 내보내는 까닭: 뷰 트랜스폼이 'Standard' 라 **선형색이 그대로
      sRGB 로 찍힌다.** 즉 팔레트 hex 를 선형으로 바꿔 넣으면 렌더 결과가 그 hex
      **그 자체**로 나온다 — 양자화가 한 톨도 안 바꾼다(팔레트 이탈 0의 근거).
    ★ EEVEE 여야 한다. Cycles 는 Shader to RGB 를 경고 없이 버린다.
    """
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    dif = nt.nodes.new("ShaderNodeBsdfDiffuse")
    dif.inputs["Color"].default_value = (1, 1, 1, 1)
    s2r = nt.nodes.new("ShaderNodeShaderToRGB")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    cr = ramp.color_ramp
    cr.interpolation = 'CONSTANT'
    cols = [shadow, mid, light]
    cr.elements[0].position = RD.RAMP_STOPS[0]
    cr.elements[1].position = RD.RAMP_STOPS[1]
    e3 = cr.elements.new(RD.RAMP_STOPS[2])
    for el, hx in zip((cr.elements[0], cr.elements[1], e3), cols):
        el.color = spec.hex2linear(hx) + (1.0,)
    emi = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(dif.outputs[0], s2r.inputs[0])
    nt.links.new(s2r.outputs[0], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], emi.inputs[0])
    nt.links.new(emi.outputs[0], out.inputs["Surface"])
    return m


# ---------------------------------------------------------------- 리그
def build_rig(sc, vl):
    ad = bpy.data.armatures.new("Rig")
    arm = bpy.data.objects.new("Rig", ad)
    sc.collection.objects.link(arm)
    vl.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    for (n, h, t, p, c) in RD.BONES:
        b = ad.edit_bones.new(n)
        b.head, b.tail = h, t
        if p:
            b.parent = ad.edit_bones[p]
            b.use_connect = bool(c)
        # ★ 롤을 `aim()` 규칙에 맞춘다. 안 맞추면 쉬는 방향으로 겨눴을 뿐인데
        #   덩어리가 축을 따라 비틀린다.
        _x, _y, z = frame_of(Vector(t) - Vector(h))
        b.align_roll(z)
    bpy.ops.object.mode_set(mode='OBJECT')
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    return arm


def aim(arm, vl, name, direction):
    """뼈를 그 방향으로 겨눈다 — **쉬는 자세에서 최소 회전**으로.

    ★ 절대 프레임을 새로 지어 넣지 않는다. 그러면 `aim(rest)` 이 쉬는 자세를
      그대로 돌려주지 않아서(위 `bone_frame` 머리말) 덩어리가 비틀린다.
      최소 회전이면 `rest → rest` 가 항등이라 **산수로** 안 비틀린다.
      그리고 팔을 휘두를 때 축 회전(롤)이 안 딸려와서, 칼날의 넓은 면이
      스윙 내내 같은 쪽을 본다 — 96px 에서 칼이 종잇장으로 변하는 것을 막는 것이 이것이다.
    """
    pb = arm.pose.bones[name]
    rest = arm.data.bones[name].matrix_local.to_3x3()
    y_rest = Vector(rest.col[1]).normalized()
    q = y_rest.rotation_difference(Vector(direction).normalized())
    M = (q.to_matrix() @ rest).to_4x4()
    M.translation = pb.matrix.translation
    pb.matrix = M
    vl.update()


ORDER = [n for (n, _h, _t, _p, _c) in RD.BONES]      # 부모가 먼저 오게 적어 뒀다


def apply_pose(arm, vl, pose):
    for n in ORDER:
        d = pose.get(n, RD.REST[n])
        aim(arm, vl, n, d)


# ---------------------------------------------------------------- 덩어리
def build_blocks(arm, M):
    """월드 좌표로 짜서 뼈에 매단다. 돌려주는 것은 (오브젝트, 삼각형 수)."""
    obs = []

    def new(name, matname, bone):
        bm = bmesh.new()
        return bm, (name, matname, bone)

    def done(bm, meta):
        obs.append(obj_from(bm, meta[0], M[meta[1]], arm, meta[2]))

    F = {n: author_frame(n) for n in ORDER}

    # ---- 발 (부츠) : shin 에 매단다
    for sfx, sx, fy in (("R", -0.17, -0.245), ("L", 0.17, 0.115)):
        bm, meta = new(f"boot{sfx}", "leather", f"shin{sfx}")
        _cube(bm, (0.21, 0.33, 0.15), Matrix.Translation((sx, fy, 0.075)))
        # 발등의 금속 띠 — 96px 에서 부츠와 정강이를 갈라 주는 유일한 신호
        _cube(bm, (0.23, 0.11, 0.09), Matrix.Translation((sx, fy + 0.04, 0.135)))
        done(bm, meta)

    # ---- 정강이 / 허벅지 : 아랫마디를 굵게 해 관절을 파고들게 한다
    for sfx in ("R", "L"):
        bm, meta = new(f"shin{sfx}", "plate", f"shin{sfx}")
        _cone(bm, 8, 0.122, 0.100, RD.LEN[f"shin{sfx}"] + 0.06,
              F[f"shin{sfx}"] @ Matrix.Translation((0, RD.LEN[f"shin{sfx}"] / 2 - 0.03, 0))
              @ Matrix.Rotation(-math.pi / 2, 4, 'X'))
        done(bm, meta)
        bm, meta = new(f"thigh{sfx}", "plate", f"thigh{sfx}")
        _cone(bm, 8, 0.158, 0.128, RD.LEN[f"thigh{sfx}"] + 0.04,
              F[f"thigh{sfx}"] @ Matrix.Translation((0, RD.LEN[f"thigh{sfx}"] / 2 - 0.02, 0))
              @ Matrix.Rotation(-math.pi / 2, 4, 'X'))
        done(bm, meta)
        # 무릎 구 — 회전축을 덮는다
        bm, meta = new(f"knee{sfx}", "plate", f"shin{sfx}")
        _sphere(bm, 6, 3, F[f"shin{sfx}"] @ Matrix.Diagonal((0.128, 0.128, 0.128, 1.0)))
        done(bm, meta)

    # ---- 골반 / 허리치마
    bm, meta = new("pelvis", "plate", "hips")
    _cone(bm, 8, 0.345, 0.265, 0.30,
          Matrix.Translation((0, -0.03, 0.845)) @ Matrix.Diagonal((1, 0.86, 1, 1)))
    done(bm, meta)
    bm, meta = new("belt", "leather", "hips")
    _cone(bm, 8, 0.268, 0.272, 0.095,
          Matrix.Translation((0, -0.035, 0.975)) @ Matrix.Diagonal((1, 0.84, 1, 1)))
    done(bm, meta)

    # ---- 몸통 판금
    bm, meta = new("torso", "plate", "chest")
    _cone(bm, 8, 0.262, 0.312, 0.37,
          Matrix.Translation((0, -0.052, 1.085)) @ Matrix.Diagonal((1, 0.92, 1, 1)))
    done(bm, meta)

    # ---- 뒤에 드리운 어두운 천 : 흰 모피가 튀어 보이게 하는 배경
    # ★★ 공식 마스터의 색 분포를 재 보면 **가장 넓은 한 색이 어두운 갈흑(34%)** 이다 —
    #   그 덩어리가 흰 모피를 튀게 하고 실루엣의 무게를 진다. 3차까지 내 망토는
    #   두께 0.075m 짜리 판때기라 옆모습에서 3px 실오라기였다(어두운 픽셀 21%).
    #   그래서 뼈를 **뒤로 흘려** 놓고 두께도 키웠다.
    # ★ 세 토막으로 나눠 **뒤로 휘어지게** 한다. 한 토막짜리 사다리꼴은 옆모습에서
    #   판때기 한 장으로 읽혔다 — 천이 아니라 널빤지였다. 토막마다 뒤로 밀면
    #   같은 12삼각형 세 벌로 드리운 곡선이 생긴다.
    bm, meta = new("cape", "cape", "cape")
    #  ★ 4차에는 뒤로 0.67m 나 뻗은 「지느러미」였다 — 옆모습에서는 어두운 덩어리를
    #    주지만 정면(S)에서는 종잇장이었다. 지금은 좌우 폭(t)과 뒤 폭(w)을 둘 다 준다.
    L = RD.LEN["cape"]
    _taper(bm, F["cape"], 0.00, L * 0.32, 0.21, 0.38, 0.24, 0.39, 0.00, 0.045)
    _taper(bm, F["cape"], L * 0.32, L * 0.64, 0.40, 0.48, 0.40, 0.46, 0.035, 0.105)
    _taper(bm, F["cape"], L * 0.64, L + 0.04, 0.48, 0.55, 0.46, 0.50, 0.105, 0.225)
    done(bm, meta)

    # ---- 어깨 망토(모피) : 「넓은 어깨」를 지는 덩어리
    # ★ 옆모습에서 「넓은 어깨」를 지는 덩어리. **뒤·위로** 물려 두는 것이 요점이다 —
    #   가운데에 두면 앞가슴 판금을 통째로 덮어서 파란색이 화면에서 사라진다.
    bm, meta = new("mantle", "mantle", "chest")
    _cone(bm, 8, 0.412, 0.272, 0.235,
          Matrix.Translation((0, 0.040, 1.272)) @ Matrix.Diagonal((1, 0.96, 1, 1)))
    done(bm, meta)

    # ---- 팔
    for sfx, sgn in (("R", -1), ("L", 1)):
        a, f, hd = f"arm{sfx}", f"fore{sfx}", f"hand{sfx}"
        bm, meta = new(f"pad{sfx}", "mantle", a)
        _sphere(bm, 6, 4, F[a] @ Matrix.Translation((0, 0.040, 0))
                @ Matrix.Diagonal((0.182, 0.160, 0.182, 1.0)))
        done(bm, meta)
        bm, meta = new(a, "plate", a)
        _cone(bm, 8, 0.098, 0.086, RD.LEN[a] + 0.05,
              F[a] @ Matrix.Translation((0, RD.LEN[a] / 2, 0))
              @ Matrix.Rotation(-math.pi / 2, 4, 'X'))
        done(bm, meta)
        bm, meta = new(f"elbow{sfx}", "plate", f)
        _sphere(bm, 6, 3, F[f] @ Matrix.Diagonal((0.094, 0.094, 0.094, 1.0)))
        done(bm, meta)
        bm, meta = new(f, "plate", f)
        _cone(bm, 8, 0.088, 0.076, RD.LEN[f] + 0.05,
              F[f] @ Matrix.Translation((0, RD.LEN[f] / 2, 0))
              @ Matrix.Rotation(-math.pi / 2, 4, 'X'))
        done(bm, meta)
        bm, meta = new(hd, "leather", hd)
        _cone(bm, 6, 0.082, 0.070, 0.13,
              F[hd] @ Matrix.Translation((0, 0.045, 0)) @ Matrix.Rotation(-math.pi / 2, 4, 'X'))
        done(bm, meta)

    # ---- 머리 (살결) + 눈 두 점
    # ★ 얼굴은 후드보다 **앞으로** 나와 있어야 한다. 1차에서는 후드 구가 얼굴을
    #   통째로 삼켜서 96px 에서 「눈사람 머리」로 읽혔다.
    bm, meta = new("head", "skin", "head")
    _cube(bm, (0.245, 0.215, 0.27), Matrix.Translation((0, -0.160, 1.470)))
    done(bm, meta)
    # ★★ 눈은 머리 상자의 **옆으로 튀어나오게** 둔다. 옆모습에서 카메라가 보는 것은
    #   머리의 옆면뿐이라, 앞면에 박아 두면 눈이 상자 속에 묻혀 한 점도 안 보인다.
    bm, meta = new("eyes", "eye", "head")
    for ex in (-0.126, 0.126):
        _cube(bm, (0.034, 0.052, 0.052), Matrix.Translation((ex, -0.243, 1.508)))
    done(bm, meta)

    # ---- ★ 모피 후드 + 수염 + 목도리 = **한 덩어리**
    #      나누면 흰 덩어리 한가운데에 이음매가 생기고, 그 이음매가 곧 실루엣의 금이다.
    #  ★ 후드는 **뒤·위**로 물려 얼굴 앞을 비운다(앞끝 y=-0.13).
    #    수염은 턱에서 **앞·아래**로 흘러 그 빈자리를 채운다. 셋이 한 덩어리다.
    bm, meta = new("furhood", "fur", "head")
    _sphere(bm, 8, 5, Matrix.Translation((0, 0.086, 1.556))
            @ Matrix.Diagonal((0.248, 0.206, 0.220, 1.0)))          # 후드 돔
    _cone(bm, 8, 0.232, 0.256, 0.25,
          Matrix.Translation((0, 0.076, 1.352)) @ Matrix.Diagonal((1, 0.86, 1, 1)))  # 뒷목·목도리
    _cone(bm, 8, 0.058, 0.196, 0.385,
          Matrix.Translation((0, -0.236, 1.252))
          @ Matrix.Rotation(math.radians(-27), 4, 'X'))              # 수염
    done(bm, meta)

    # ---- 대검
    S = F["sword"]
    bm, meta = new("grip", "leather", "sword")
    _cone(bm, 6, 0.040, 0.038, 0.235,
          S @ Matrix.Translation((0, -0.035, 0)) @ Matrix.Rotation(-math.pi / 2, 4, 'X'))
    done(bm, meta)
    bm, meta = new("pommel", "steel", "sword")
    _cube(bm, (0.085, 0.085, 0.085), S @ Matrix.Translation((0, -0.175, 0)))
    done(bm, meta)
    bm, meta = new("guard", "steel", "sword")
    _taper(bm, S, 0.070, 0.150, 0.430, 0.345, 0.070, 0.058)
    done(bm, meta)
    bm, meta = new("blade", "blade", "sword")
    _taper(bm, S, 0.135, 0.735, 0.180, 0.120, 0.050, 0.038)
    _taper(bm, S, 0.735, 0.900, 0.120, 0.022, 0.038, 0.014)
    done(bm, meta)

    # ---- 빈 손의 카드 (설계서의 결. 96px 에서는 밝은 네모 한 장이다)
    bm, meta = new("card", "steel", "handL")
    _cube(bm, (0.105, 0.012, 0.150),
          F["handL"] @ Matrix.Translation((0.03, 0.10, 0))
          @ Matrix.Rotation(math.radians(18), 4, 'Y'))
    done(bm, meta)

    tris = 0
    for ob in obs:
        ob.data.calc_loop_triangles()
        tris += len(ob.data.loop_triangles)
    return obs, tris


# ---------------------------------------------------------------- 액션
def make_action(arm, vl, name, frames, posefn):
    arm.animation_data_create()
    act = bpy.data.actions.new(name)
    arm.animation_data.action = act
    for i in range(frames + 1):          # 마지막 한 칸 더 = 루프 이음매
        apply_pose(arm, vl, posefn(i % frames))
        for pb in arm.pose.bones:
            pb.keyframe_insert("rotation_quaternion", frame=i + 1)
    for fc in act.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = 'LINEAR'
    # ★ 안 켜면 .blend 로 구울 때 **쓰는 이가 없는 액션이 조용히 사라진다.**
    #   idle 하나만 남고 attack/walk 가 없어져서 5단계가 KeyError 로 죽는다.
    act.use_fake_user = True
    return act


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="build/b3d/cand_a/2_model/jokull.blend")
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    a = ap.parse_args(argv)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc, vl = bpy.context.scene, bpy.context.view_layer
    sc.render.engine = 'BLENDER_EEVEE'

    M = {k: toon_mat(k, *v) for k, v in RD.MATS.items()}
    arm = build_rig(sc, vl)
    obs, tris = build_blocks(arm, M)

    acts = {}
    for act_name, cfg in spec.ACTIONS.items():
        fn = {"idle": RD.pose_idle, "attack": RD.pose_attack,
              "walk": RD.pose_walk}[act_name]
        acts[act_name] = make_action(arm, vl, act_name, cfg["frames"], fn).name
    arm.animation_data.action = bpy.data.actions["idle"]
    apply_pose(arm, vl, RD.pose_idle(0))

    out = Path(a.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out.resolve()))
    rep = {"blend": str(out), "objects": len(obs), "tris": tris,
           "bones": len(RD.BONES), "materials": len(M), "actions": acts}
    print("BUILD_JSON " + json.dumps(rep))


# ★ 가드를 둔다 — blender 는 --python 으로 돌릴 때 __name__ 이 "__main__" 이라
#   이 파일을 **다른 스크립트가 import** 해서 함수만 빌려 쓸 수 있다(디버그 렌더).
if __name__ == "__main__":
    main()
