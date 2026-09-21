# 후보 C — 5단계. 직교 툰 렌더. **한 프로세스 안에서** 전부 돈다.
#
#   env -u DISPLAY bl -b --factory-startup --python tools/blender3d/cand_c/render.py \
#       -- --variant flat --probe
#
# ★ 프레임마다 blender 를 새로 띄우지 마라 — EEVEE 첫 렌더에 GPU 컨텍스트 1초가
#   붙는다(앞 단계 실측). 한 번 띄우면 96x96 한 장이 0.106초다.
# ★ Xvfb 를 쓰지 마라. 헤드리스가 EGL 로 GB10 을 직접 잡아 2.6배 빠르다.
#
# ---------------------------------------------------------------------------
# ★★ 카메라를 **스스로 맞춘다**(auto-frame). 두 가지를 동시에 지켜야 하기 때문이다:
#     · 발밑이 칸 맨 아래에 닿을 것            → 세로는 **발 덩어리**로 맞춘다
#     · 어느 칸에서도 틀 밖으로 안 나갈 것      → 가로는 **모든 칸·모든 방향의 합집합**으로 맞춘다
#   손으로 숫자를 넣으면 액션을 한 번 고칠 때마다 칼끝이 잘린다. 실제로 그래서 넣었다.
#   ★ 세로를 합집합으로 맞추면 안 된다 — 칼이 발보다 아래로 내려가는 칸이 하나라도
#     있으면 그 칸 때문에 **모든 칸의 발이 떠오른다.** 그래서 발로 맞추고, 칼이
#     발 밑으로 내려가는지는 따로 재서 경고한다.
# ---------------------------------------------------------------------------
import json
import math
import os
import sys
import time

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import spec  # noqa: E402

OUT = os.path.join(spec.ROOT, "build", "b3d", "cand_c")
CELL = spec.CELL[0]
HALF = spec.ORTHO_SCALE / 2.0
ELEV = math.radians(spec.ELEV)
UPV = Vector((0.0, math.sin(ELEV), math.cos(ELEV)))     # 화면 세로 축(월드)
RGT = Vector((1.0, 0.0, 0.0))                            # 화면 가로 축(월드)

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def opt(name, default=None):
    return argv[argv.index(name) + 1] if name in argv else default


VARIANT = opt("--variant", "flat")          # flat | tex
PROBE = "--probe" in argv
TAG = opt("--tag", "")
ONLY_E = "--only-e" in argv
SAMPLES = int(opt("--samples", "16"))
#: 태양 방향 — E(오른쪽을 보는 자세)에서 **얼굴과 가슴이 밝은 쪽**이 되게 잡았다.
SUN_DIR = Vector((-0.90, 0.50, -1.10)).normalized()
SUN_E = float(opt("--sun", str(math.pi)))
FILL_E = float(opt("--fill", "0.55"))
FILL_DIR = Vector((0.80, -0.30, -0.55)).normalized()


def setup_scene():
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_EEVEE'          # ★ 4.0 은 EEVEE_NEXT 가 아니다
    sc.eevee.taa_render_samples = SAMPLES
    sc.render.resolution_x = sc.render.resolution_y = CELL
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    sc.render.film_transparent = True           # ★ 알파
    sc.render.filter_size = 0.0                 # ★ 반투명 픽셀이 0 이 된다
    sc.render.dither_intensity = 0.0            # ★ 안 끄면 밴드가 ±1 로 흩어진다
    sc.view_settings.view_transform = 'Standard'  # ★ 기본 AgX 면 색이 통째로 밀린다
    sc.view_settings.look = 'None'
    sc.render.use_freestyle = False             # 테두리는 6단계(post)가 두른다
    w = bpy.data.worlds.new("W")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0, 0, 0, 1)

    cd = bpy.data.cameras.new("C")
    cd.type = 'ORTHO'
    cd.ortho_scale = spec.ORTHO_SCALE
    cam = bpy.data.objects.new("C", cd)
    cam.rotation_euler = (math.radians(90.0 - spec.ELEV), 0, 0)
    sc.collection.objects.link(cam)
    sc.camera = cam

    for nm, d, e in (("key", SUN_DIR, SUN_E), ("fill", FILL_DIR, FILL_E)):
        ld = bpy.data.lights.new(nm, 'SUN')
        ld.energy = e
        ld.angle = 0.0                          # 그림자 가장자리를 딱 끊는다
        lo = bpy.data.objects.new(nm, ld)
        lo.rotation_euler = Vector((0, 0, -1)).rotation_difference(d).to_euler()
        sc.collection.objects.link(lo)
    return sc, cam


def place_cam(cam, xoff, zt):
    tgt = Vector((xoff, 0.0, zt))
    cam.location = tgt + spec.CAM_DIST * Vector((0, -math.cos(ELEV), math.sin(ELEV)))
    return tgt


def to_px(p: Vector, tgt: Vector):
    d = p - tgt
    return (CELL / 2 + d.dot(RGT) / HALF * (CELL / 2),
            CELL / 2 - d.dot(UPV) / HALF * (CELL / 2))


def main():
    bpy.ops.wm.open_mainfile(
        filepath=os.path.join(OUT, "2_model", "jokull.blend"))
    sc, cam = setup_scene()
    ob = bpy.data.objects["jokull"]
    arm = bpy.data.objects["rig"]
    vl = bpy.context.view_layer

    if VARIANT == "tex":
        tm = bpy.data.materials["tex_proj"]
        rep = json.load(open(os.path.join(OUT, "build_report.json")))
        for nm in rep["body_slots"]:
            ob.material_slots[rep["materials"].index(nm)].material = tm

    foot_vi = set()
    for g in ("foot_R", "foot_L"):
        gi = ob.vertex_groups[g].index
        for v in ob.data.vertices:
            if any(x.group == gi for x in v.groups):
                foot_vi.add(v.index)

    acts = {a.name: a for a in bpy.data.actions}
    dirs = {spec.GAME_DIR: spec.DIRS[spec.GAME_DIR]} if ONLY_E else spec.DIRS
    jobs = []                                   # (action, frame, dirname)
    for act in ("idle", "attack"):
        n = spec.ACTIONS[act]["frames"]
        for f in range(1, n + 1):
            jobs.append((act, f, spec.GAME_DIR))
    if not ONLY_E:
        for dn in spec.DIRS:
            if dn != spec.GAME_DIR:
                jobs.append(("idle", 1, dn))

    # ---- 1) 자동 프레이밍: 모든 칸을 한 번 훑어 화면 좌표를 잰다 -----------
    tgt0 = place_cam(cam, 0.0, 0.0)
    uni = [1e9, 1e9, -1e9, -1e9]
    foot_lo = -1e9
    per = {}
    for act, fr, dn in jobs:
        arm.animation_data.action = acts[act]
        arm.rotation_euler = (0, 0, math.radians(spec.DIRS[dn]))
        sc.frame_set(fr)
        vl.update()
        dg = vl.depsgraph
        ev = ob.evaluated_get(dg)
        m = ev.to_mesh()
        M = ev.matrix_world
        hs = []
        vs = []
        fv = []
        for i, v in enumerate(m.vertices):
            p = M @ v.co
            hs.append(p.dot(RGT))
            vs.append(p.dot(UPV))
            if i in foot_vi:
                fv.append(p.dot(UPV))
        ev.to_mesh_clear()
        uni[0] = min(uni[0], min(hs)); uni[2] = max(uni[2], max(hs))
        uni[1] = min(uni[1], min(vs)); uni[3] = max(uni[3], max(vs))
        foot_lo = max(foot_lo, min(fv))          # 가장 높이 뜬 「발밑」
        per[f"{act}/{dn}/{fr}"] = {"v_lo": round(min(vs), 4),
                                   "foot_lo": round(min(fv), 4),
                                   "h": [round(min(hs), 4), round(max(hs), 4)]}
    # 발밑을 아래에서 1.0px 자리에 놓는다 (테두리 한 겹이 들어갈 틈)
    # ★ **세로는 발로 맞춘다.** 합집합으로 맞추면 칼이 발보다 아래로 내려가는 칸이
    #   하나만 있어도 그 칸 때문에 **모든 칸의 발이 떠오른다.**
    foot_all = min(x["foot_lo"] for x in per.values())
    v_target = -HALF * (1.0 - 2.0 * 1.0 / CELL)
    zt = (foot_all - v_target) / math.cos(ELEV)
    # ★ 가로 중심은 **둘**이다. 게임에 나가는 것은 E 뿐인데, 여덟 방향을 다 담으려고
    #   가운데를 옮기면 정작 E 의 칼끝이 틀 밖으로 나간다(실측 -4.7 ~ 100.7px).
    #   세로(=발밑)는 한 값이므로 계약(발이 같은 줄)은 그대로 지켜진다.
    eh = [v["h"] for k, v in per.items() if f"/{spec.GAME_DIR}/" in k]
    xoff_e = (min(h[0] for h in eh) + max(h[1] for h in eh)) / 2.0
    xoff_all = (uni[0] + uni[2]) / 2.0
    xoff = xoff_e
    tgt = place_cam(cam, xoff, zt)

    diag = {"variant": VARIANT, "proj_tag": TAG, "xoff_e": round(xoff_e, 4),
            "xoff_all": round(xoff_all, 4), "zt": round(zt, 4), "jobs": len(jobs)}
    diag["e_px_x"] = [round(CELL / 2 + (min(h[0] for h in eh) - xoff_e) / HALF * (CELL / 2), 2),
                      round(CELL / 2 + (max(h[1] for h in eh) - xoff_e) / HALF * (CELL / 2), 2)]
    ef = [v["foot_lo"] for k, v in per.items() if f"/{spec.GAME_DIR}/" in k]
    diag["e_foot_spread_px"] = round((max(ef) - min(ef)) / HALF * (CELL / 2), 3)
    px = [to_px(Vector((0, 0, 0)), tgt)]
    bb = [CELL / 2 + (uni[0] - xoff) / HALF * (CELL / 2),
          CELL / 2 - (uni[3] - zt * math.cos(ELEV)) / HALF * (CELL / 2)]
    diag["union_px_x"] = [round(CELL / 2 + (uni[0] - xoff) / HALF * (CELL / 2), 2),
                          round(CELL / 2 + (uni[2] - xoff) / HALF * (CELL / 2), 2)]
    ylo = CELL / 2 - (uni[3] - tgt.dot(UPV)) / HALF * (CELL / 2)
    yhi = CELL / 2 - (uni[1] - tgt.dot(UPV)) / HALF * (CELL / 2)
    diag["union_px_y"] = [round(ylo, 2), round(yhi, 2)]
    diag["foot_px_y"] = round(CELL / 2 - (foot_all - tgt.dot(UPV)) / HALF * (CELL / 2), 2)
    diag["foot_spread_px"] = round((foot_lo - foot_all) / HALF * (CELL / 2), 2)
    diag["below_foot_px"] = round((foot_all - uni[1]) / HALF * (CELL / 2), 2)
    if PROBE:
        diag["per_frame"] = per
        print("PROBE_JSON " + json.dumps(diag, ensure_ascii=False))
        return

    # ---- 2) 렌더 ---------------------------------------------------------
    root = os.path.join(OUT, "5_frames" + TAG +
                        ("" if VARIANT == "flat" else "_" + VARIANT))
    t0 = time.time()
    for act, fr, dn in jobs:
        arm.animation_data.action = acts[act]
        arm.rotation_euler = (0, 0, math.radians(spec.DIRS[dn]))
        sc.frame_set(fr)
        # E(게임이 쓰는 방향)는 E 기준 중심으로, 나머지 일곱은 합집합 중심으로
        place_cam(cam, xoff_e if dn == spec.GAME_DIR else xoff_all, zt)
        d = os.path.join(root, act, dn)
        os.makedirs(d, exist_ok=True)
        sc.render.filepath = os.path.join(d, "%04d" % fr)
        bpy.ops.render.render(write_still=True)
    dt = time.time() - t0
    diag["total_sec"] = round(dt, 2)
    diag["sec_per_frame"] = round(dt / len(jobs), 4)
    diag["out"] = root
    with open(os.path.join(OUT, f"render_report{TAG}_{VARIANT}.json"), "w") as f:
        json.dump(diag, f, ensure_ascii=False, indent=1)
    print("RENDER_JSON " + json.dumps(diag, ensure_ascii=False))


main()
