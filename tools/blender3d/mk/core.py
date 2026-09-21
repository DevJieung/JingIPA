#!/usr/bin/env python3
"""★ **캐릭터를 안 가리는 부분**만 모은 곳 — 프리미티브 · 재질 · 리그 · 액션 · 드라이버.

원래 `mk/build.py` 한 파일에 있던 것을 **둘째 캐릭터(솔라나)를 만들면서** 갈랐다.
가른 자리가 곧 「양산했을 때 무엇이 공짜인가」의 답이다:

  * 여기 있는 것(이 파일)      = 캐릭터가 늘어도 **한 줄도 안 는다**
  * `char_*.py` 의 `blocks()` = 캐릭터마다 **새로 쓴다** (덩어리 지오메트리)
  * `rigdef*.py`              = 캐릭터마다 **새로 쓴다** (뼈 · 색 · 자세)

## 캐릭터 모듈이 지켜야 할 계약
`rigdef` 쪽 (숫자만, bpy 를 안 쓴다):
    BONES        [(이름, head, tail, 부모, 이어붙임), …]  ★ 부모가 먼저 온다
    MATS         {재질이름: (그늘, 중간, 빛)}
    RAMP_STOPS   (0.0, 중간문턱, 빛문턱)
    REST, LEN    BONES 에서 저절로 나온다
    POSE         {"idle": fn(i), "walk": fn(i), "attack": fn(i)}  → {뼈이름: 방향}
                 ★ 방향은 **아마추어 공간(=월드)** 벡터다. `aim()` 이 그 방향으로 겨눈다.
                 ★ `"_scale"` 열쇠에 {뼈이름: (sx,sy,sz)} 를 넣으면 그 뼈의 **크기**도 건다.
    MUZ_BONE, MUZ_LOCAL, FAMILY   5단계가 총구를 찍을 자리와 `anim.json` 의 무리
    UP_HINT      {뼈이름: up 벡터}  — 뼈 좌표계의 옆축을 잡는다(넓은 면이 카메라를 보게)
`char` 쪽:
    blocks(ctx)  덩어리를 만든다. `ctx.make(...)` 로 하나씩 짓는다.

## ★★ `_scale` 를 왜 넣었나 — 활 때문이다
요쿨(검)은 회전만으로 다 됐다. 그런데 활은 **시위가 늘었다 줄었다** 해야 한다 —
당기면 V 가 깊어지고 놓으면 앞으로 튄다. 강체 뼈 부착에서는 그것이 **뼈 크기**로만
난다(뼈에 물린 덩어리가 뼈 크기를 그대로 받는다). 회전만 거는 옛 `make_action` 으로는
「당긴다」를 아예 못 그린다.
☆ 자세 표에 `_scale` 이 없으면 크기는 1 그대로라, **요쿨의 결과는 한 픽셀도 안 바뀐다.**
"""
import sys
import math
import json
import argparse
from pathlib import Path

import bpy
import bmesh
from mathutils import Matrix, Vector

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))
import spec                  # noqa: E402


# ---------------------------------------------------------------- 뼈 좌표계
def frame_of(direction, up_hint=(0, 0, 1)):
    y = Vector(direction).normalized()
    up = Vector(up_hint) if abs(y.z) < 0.95 else Vector((0, 1, 0))
    x = up.cross(y).normalized()
    z = y.cross(x).normalized()
    return x, y, z


def author_frame(RD, name):
    """덩어리를 짜 넣을 때 쓰는 프레임 (원점=뼈 머리 · y=뼈 방향 · up=UP_HINT)."""
    up_hint = getattr(RD, "UP_HINT", {})
    for (n, h, t, _p, _c) in RD.BONES:
        if n == name:
            x, y, z = frame_of(Vector(t) - Vector(h), up_hint.get(name, (0, 0, 1)))
            M = Matrix((x, y, z)).transposed().to_4x4()
            M.translation = Vector(h)
            return M
    raise KeyError(name)


# ---------------------------------------------------------------- 프리미티브
def _cone(bm, seg, r1, r2, depth, M, caps=True):
    bmesh.ops.create_cone(bm, cap_ends=caps, cap_tris=False, segments=seg,
                          radius1=r1, radius2=r2, depth=depth, matrix=M)


def _cube(bm, size, M):
    bmesh.ops.create_cube(bm, size=1.0,
                          matrix=M @ Matrix.Diagonal((size[0], size[1], size[2], 1.0)))


def _sphere(bm, u, v, M):
    bmesh.ops.create_uvsphere(bm, u_segments=u, v_segments=v, radius=1.0, matrix=M)


def _shell(bm, cx, cy, z0, z1, r0, r1, a0, a1, seg, thick=0.055):
    """★ **곡면 껍질** — 몸을 감싸며 드리우는 천. 납작한 판때기는 바닥에 깔린 검은
    삼각형(그림자)으로 읽힌다. 각은 +X 가 0도 · +Y(등 뒤)가 90도."""
    top, bot = [], []
    for k in range(seg + 1):
        a = math.radians(a0 + (a1 - a0) * k / seg)
        top.append(bm.verts.new((cx + r0 * math.cos(a), cy + r0 * math.sin(a), z0)))
        bot.append(bm.verts.new((cx + r1 * math.cos(a), cy + r1 * math.sin(a), z1)))
    bm.verts.ensure_lookup_table()
    fs = [bm.faces.new((top[k], top[k + 1], bot[k + 1], bot[k])) for k in range(seg)]
    bmesh.ops.solidify(bm, geom=fs, thickness=thick)


def _taper(bm, M, y0, y1, w0, w1, t0, t1, cz0=0.0, cz1=0.0):
    """뼈 공간에서 y0→y1 로 뻗는 가늘어지는 상자. 8정점 12삼각형.
    `w` 는 뼈 z 방향, `t` 는 뼈 x 방향, `cz` 는 z 중심 밀기(휘어진 드리움)."""
    P = []
    for (y, w, t, cz) in ((y0, w0, t0, cz0), (y1, w1, t1, cz1)):
        for sz in (-1, 1):
            for sx in (-1, 1):
                P.append(M @ Vector((sx * t / 2, y, sz * w / 2 + cz)))
    vs = [bm.verts.new(p) for p in P]
    bm.verts.ensure_lookup_table()
    q = lambda *i: bm.faces.new([vs[k] for k in i])
    q(0, 1, 3, 2); q(6, 7, 5, 4); q(0, 4, 5, 1)
    q(2, 3, 7, 6); q(0, 2, 6, 4); q(1, 5, 7, 3)


def _ribbon(bm, M, pts, w, t):
    """★ 점을 이어 만드는 **띠** — 활채·불꽃 혀처럼 휜 것에 쓴다.

    `pts` 는 뼈 공간의 (y, z) 목록이고, 띠는 그 선을 따라 두께 `t`(뼈 x 방향) ·
    폭 `w`(선의 법선 방향)로 부푼다. `_taper` 를 여러 도막 이어 붙이는 것보다
    이음매가 안 생긴다 — 96px 에서 이음매는 곧 검은 점 하나다.
    """
    ws = w if isinstance(w, (list, tuple)) else [w] * len(pts)
    ts = t if isinstance(t, (list, tuple)) else [t] * len(pts)
    rings = []
    for k, (py, pz) in enumerate(pts):
        if k == 0:
            dy, dz = pts[1][0] - py, pts[1][1] - pz
        elif k == len(pts) - 1:
            dy, dz = py - pts[-2][0], pz - pts[-2][1]
        else:
            dy, dz = pts[k + 1][0] - pts[k - 1][0], pts[k + 1][1] - pts[k - 1][1]
        L = math.hypot(dy, dz) or 1.0
        ny, nz = -dz / L, dy / L                      # 선의 법선
        hw, ht = ws[k] / 2.0, ts[k] / 2.0
        ring = []
        for (sn, sx) in ((-1, -1), (-1, 1), (1, 1), (1, -1)):
            ring.append(bm.verts.new(
                M @ Vector((sx * ht, py + sn * hw * ny, pz + sn * hw * nz))))
        rings.append(ring)
    bm.verts.ensure_lookup_table()
    for k in range(len(rings) - 1):
        a, b = rings[k], rings[k + 1]
        for j in range(4):
            bm.faces.new((a[j], a[(j + 1) % 4], b[(j + 1) % 4], b[j]))
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[-1])


# ---------------------------------------------------------------- 재질
def toon_mat(name, shadow, mid, light, stops):
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
    cr.elements[0].position = stops[0]
    cr.elements[1].position = stops[1]
    e3 = cr.elements.new(stops[2])
    for el, hx in zip((cr.elements[0], cr.elements[1], e3), (shadow, mid, light)):
        el.color = spec.hex2linear(hx) + (1.0,)
    emi = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(dif.outputs[0], s2r.inputs[0])
    nt.links.new(s2r.outputs[0], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], emi.inputs[0])
    nt.links.new(emi.outputs[0], out.inputs["Surface"])
    return m


def id_depth_mat():
    """★ **번호+깊이 재질.** 5단계가 `material_override` 로 통째로 갈아 끼워
    한 장을 더 굽는다. R = 오브젝트 번호 · G,B = 카메라 깊이(16비트).
    ★ 이 한 장을 굽는 동안만 뷰 트랜스폼이 **'Raw'** 여야 한다."""
    m = bpy.data.materials.new("IDDEPTH")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    obj = nt.nodes.new("ShaderNodeObjectInfo")
    cam = nt.nodes.new("ShaderNodeCameraData")

    def math(op, a=None, b=None):
        n = nt.nodes.new("ShaderNodeMath")
        n.operation = op
        if a is not None:
            n.inputs[0].default_value = a
        if b is not None:
            n.inputs[1].default_value = b
        return n

    idn = math('DIVIDE', b=255.0)
    nt.links.new(obj.outputs["Object Index"], idn.inputs[0])
    sub = math('SUBTRACT', b=spec.CAM_DIST - 2.0)
    nt.links.new(cam.outputs["View Z Depth"], sub.inputs[0])
    dv = math('DIVIDE', b=4.0)
    nt.links.new(sub.outputs[0], dv.inputs[0])
    cl = math('MINIMUM', b=0.999)
    nt.links.new(dv.outputs[0], cl.inputs[0])
    cl2 = math('MAXIMUM', b=0.0)
    nt.links.new(cl.outputs[0], cl2.inputs[0])
    m255 = math('MULTIPLY', b=255.0)
    nt.links.new(cl2.outputs[0], m255.inputs[0])
    fl = math('FLOOR')
    nt.links.new(m255.outputs[0], fl.inputs[0])
    hi = math('DIVIDE', b=255.0)
    nt.links.new(fl.outputs[0], hi.inputs[0])
    lo = math('FRACT')
    nt.links.new(m255.outputs[0], lo.inputs[0])

    comb = nt.nodes.new("ShaderNodeCombineColor")
    nt.links.new(idn.outputs[0], comb.inputs[0])
    nt.links.new(hi.outputs[0], comb.inputs[1])
    nt.links.new(lo.outputs[0], comb.inputs[2])
    emi = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(comb.outputs[0], emi.inputs["Color"])
    nt.links.new(emi.outputs[0], out.inputs["Surface"])
    return m


# ---------------------------------------------------------------- 리그
def build_rig(RD, sc, vl):
    up_hint = getattr(RD, "UP_HINT", {})
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
        _x, _y, z = frame_of(Vector(t) - Vector(h), up_hint.get(n, (0, 0, 1)))
        b.align_roll(z)
    bpy.ops.object.mode_set(mode='OBJECT')
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    return arm


def aim(arm, vl, name, direction):
    """뼈를 그 방향으로 겨눈다 — 쉬는 자세에서 **최소 회전**으로."""
    pb = arm.pose.bones[name]
    rest = arm.data.bones[name].matrix_local.to_3x3()
    y_rest = Vector(rest.col[1]).normalized()
    q = y_rest.rotation_difference(Vector(direction).normalized())
    M = (q.to_matrix() @ rest).to_4x4()
    M.translation = pb.matrix.translation
    pb.matrix = M
    vl.update()


def apply_pose(RD, arm, vl, pose):
    """자세 하나를 건다. `_scale` 이 있으면 뼈 크기도 같이 건다(활 시위)."""
    sc = pose.get("_scale", {})
    for pb in arm.pose.bones:
        pb.scale = sc.get(pb.name, (1.0, 1.0, 1.0))
    for (n, _h, _t, _p, _c) in RD.BONES:          # 부모가 먼저다
        aim(arm, vl, n, pose.get(n, RD.REST[n]))


def make_action(RD, arm, vl, name, frames, posefn):
    arm.animation_data_create()
    act = bpy.data.actions.new(name)
    arm.animation_data.action = act
    #: ★ 크기를 쓰는 뼈가 하나라도 있으면 **모든 칸에** 크기를 건다. 한 칸만 걸면
    #:   블렌더가 그 사이를 쉬는 값에서 보간해 시위가 저 혼자 늘었다 줄었다 한다.
    use_scale = any("_scale" in posefn(i % frames) for i in range(frames))
    for i in range(frames + 1):          # 마지막 한 칸 더 = 루프 이음매
        apply_pose(RD, arm, vl, posefn(i % frames))
        for pb in arm.pose.bones:
            pb.keyframe_insert("rotation_quaternion", frame=i + 1)
            if use_scale:
                pb.keyframe_insert("scale", frame=i + 1)
    for fc in act.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = 'LINEAR'
    # ★ 안 켜면 쓰는 이가 없는 액션이 저장할 때 조용히 사라진다.
    act.use_fake_user = True
    return act


# ---------------------------------------------------------------- 덩어리 짓는 판
class Ctx:
    """`blocks()` 이 받는 판. `make()` 하나로 덩어리를 짓는다.

    ★ `pass_index` 를 순서대로 붙인다 — `lineart` 가 이 번호로 경계를 찾으므로
      **선을 넣고 싶은 곳마다 덩어리를 나누는 것**이 이 길의 손잡이다.
    """

    def __init__(self, RD, arm, mats):
        self.RD, self.arm, self.M = RD, arm, mats
        self.obs = []
        self._n = 0
        self.F = {n: author_frame(RD, n) for (n, _h, _t, _p, _c) in RD.BONES}

    def make(self, name, matname, bone, fn, line=True):
        bm = bmesh.new()
        fn(bm)
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        me.materials.append(self.M[matname])
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        bone_d = self.arm.data.bones[bone]
        ob.parent = self.arm
        ob.parent_type = 'BONE'
        ob.parent_bone = bone
        ob.matrix_parent_inverse = (
            self.arm.matrix_world @ bone_d.matrix_local
            @ Matrix.Translation((0, bone_d.length, 0))).inverted()
        self._n += 1
        ob.pass_index = self._n
        ob["b3d_line"] = bool(line)
        self.obs.append(ob)
        return ob


# ---------------------------------------------------------------- 드라이버
def run(RD, blocks, out_path):
    """2·3·4단계를 한 번에 — 캐릭터 모듈 둘만 받으면 나머지는 다 여기서 돈다."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc, vl = bpy.context.scene, bpy.context.view_layer
    sc.render.engine = 'BLENDER_EEVEE'

    stops = getattr(RD, "RAMP_STOPS", (0.0, 0.40, 0.86))
    M = {k: toon_mat(k, v[0], v[1], v[2], stops) for k, v in RD.MATS.items()}
    idm = id_depth_mat()
    idm.use_fake_user = True
    arm = build_rig(RD, sc, vl)

    ctx = Ctx(RD, arm, M)
    blocks(ctx)
    obs = ctx.obs
    tris = 0
    for ob in obs:
        ob.data.calc_loop_triangles()
        tris += len(ob.data.loop_triangles)

    acts = {}
    for act_name, cfg in spec.ACTIONS.items():
        acts[act_name] = make_action(RD, arm, vl, act_name, cfg["frames"],
                                     RD.POSE[act_name]).name
    arm.animation_data.action = bpy.data.actions["idle"]
    apply_pose(RD, arm, vl, RD.POSE["idle"](0))

    ids = {ob.name: ob.pass_index for ob in obs}
    noline = sorted(ob.pass_index for ob in obs if not ob.get("b3d_line", True))
    out = Path(out_path)
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out.resolve()))
    print("BUILD_JSON " + json.dumps({
        "blend": str(out), "objects": len(obs), "tris": tris,
        "bones": len(RD.BONES), "materials": len(M), "actions": acts,
        "ids": ids, "noline": noline}))


def cli(default_out):
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=default_out)
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return ap.parse_args(argv)
