# -*- coding: utf-8 -*-
"""후보 B — 5단계. 직교 툰 렌더. **한 프로세스 안에서** 전부 돈다.

    env -u DISPLAY bl -b --factory-startup --python tools/blender3d/cand_b/render.py -- [옵션]

★ 프레임마다 blender 를 새로 띄우면 EEVEE 의 GPU 컨텍스트 1초가 매번 든다.
  한 번 띄워 두면 96x96 한 장이 0.1초다.
"""
import bpy, math, os, sys, json, time
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import spec  # noqa: E402

OUT = os.path.join(spec.ROOT.as_posix(), "build", "b3d", "cand_b")
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def arg(name, default, cast=float):
    if name in argv:
        return cast(argv[argv.index(name) + 1])
    return default


ELEV = arg("--elev", spec.ELEV)
CAMC = arg("--camc", 1.075)        # 카메라 중심의 「화면 위쪽」 좌표(m). 발밑을 칸 밑으로 민다
CAMX = arg("--camx", 0.07)         # 카메라를 +X 로 밀면 그림이 칸에서 왼쪽으로 온다
#   ★ 0.14 로 밀었더니 E 는 가운데로 왔지만 **W 방향에서 칼이 x=0 에 닿아 잘렸다**.
#     여덟 방향을 한 카메라로 받으므로 가운데 맞추기는 양쪽 다 봐야 한다.
SAMPLES = int(arg("--samples", 1))
TAG = arg("--tag", "", str)
SUN = arg("--sun", 0.0)            # 해 방위 미세 조정(도)
FRAMES_DIR = os.path.join(OUT, "5_frames" + TAG)


def setup_scene():
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_EEVEE'          # ★ Cycles 는 Shader to RGB 를 조용히 버린다
    sc.render.resolution_x, sc.render.resolution_y = spec.CELL
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    sc.render.image_settings.color_depth = '8'
    sc.render.film_transparent = True           # 알파
    sc.render.filter_size = 0.0                 # 반투명 가장자리 0개
    sc.render.dither_intensity = 0.0            # 밴드가 ±1 로 흩어지는 것을 막는다
    sc.render.use_freestyle = False             # 테두리는 후처리(pixels.add_outline)가 두른다
    sc.view_settings.view_transform = 'Standard'  # ★ AgX 면 넣은 색과 다른 색이 찍힌다
    sc.view_settings.look = 'None'
    sc.view_settings.exposure = 0.0
    sc.view_settings.gamma = 1.0
    sc.display_settings.display_device = 'sRGB'
    sc.eevee.taa_render_samples = SAMPLES
    for k, v in (("use_gtao", False), ("use_bloom", False), ("use_ssr", False),
                 ("use_soft_shadows", False), ("use_motion_blur", False)):
        if hasattr(sc.eevee, k):
            setattr(sc.eevee, k, v)

    w = bpy.data.worlds.new("W")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0, 0, 0, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.0

    # --- 카메라: 직교 · 내림각 ELEV. 캐릭터가 원점에서 돌고 카메라는 못 박혀 있다.
    e = math.radians(ELEV)
    view = Vector((0, math.cos(e), -math.sin(e)))
    up = Vector((0, math.sin(e), math.cos(e)))
    target = up * CAMC
    cd = bpy.data.cameras.new("Cam")
    cd.type = 'ORTHO'
    cd.ortho_scale = spec.ORTHO_SCALE
    cam = bpy.data.objects.new("Cam", cd)
    cam.location = target - view * spec.CAM_DIST + Vector((CAMX, 0, 0))
    cam.rotation_euler = (math.radians(90.0 - ELEV), 0, 0)
    sc.collection.objects.link(cam)
    sc.camera = cam

    # --- 해. 화면 왼쪽 위 앞에서 온다(캐릭터가 E 를 볼 때 앞얼굴이 밝다).
    #     세기 π 라 ShaderToRGB 값이 그대로 N·L 이 된다 → 램프 위치가 곧 각도다.
    #     ★ 앞·위·카메라쪽에서 온다 — 등(화면 왼쪽)이 어두워야 곰가죽 망토가 실루엣을 진다.
    ld = bpy.data.lights.new("Sun", 'SUN')
    ld.energy = math.pi
    ld.angle = 0.0
    ld.use_shadow = False                       # 96px 에서 그림자는 읽히지 않고 밴드만 흐린다
    lo = bpy.data.objects.new("Sun", ld)
    d = Vector((math.cos(math.radians(SUN)) * 0.45, 0.55, -0.70))
    lo.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    sc.collection.objects.link(lo)
    return sc, cam


def project(P, elev, camc):
    """월드 점 → 칸 안 픽셀. 직교라 산수로 딱 떨어진다.
    ★ 총구(muzzle_at)와 발밑 기준점을 여기 한 곳에서만 잰다."""
    e = math.radians(elev)
    up = Vector((0, math.sin(e), math.cos(e)))
    px = spec.CELL[0] * 0.5 + (P.x - CAMX) * spec.PX_PER_M
    py = spec.PX_PER_M * (camc + spec.ORTHO_SCALE * 0.5 - P.dot(up))
    return px, py


def sword_tip(arm):
    """휘두르는 칼끝 — 평가된 대검 메시에서 손목에서 가장 먼 정점."""
    sw = bpy.data.objects.get("Sword")
    if sw is None:
        return None
    dg = bpy.context.view_layer.depsgraph
    me = sw.evaluated_get(dg).to_mesh()
    hand = (arm.matrix_world @ arm.pose.bones["hand.R"].matrix).to_translation()
    best, bv = -1.0, None
    for v in me.vertices:
        w = sw.matrix_world @ v.co
        d = (w - hand).length
        if d > best:
            best, bv = d, w
    return bv


def render_to(sc, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    sc.render.filepath = path[:-4] if path.endswith(".png") else path
    t0 = time.time()
    bpy.ops.render.render(write_still=True)
    return time.time() - t0


def main():
    blend = os.path.join(OUT, "jokull_b.blend")
    bpy.ops.wm.open_mainfile(filepath=blend)
    sc, cam = setup_scene()
    arm = bpy.data.objects["Rig"]
    if arm.animation_data is None:
        arm.animation_data_create()

    times = []
    tips = {}
    R = {"elev": ELEV, "camc": CAMC, "camx": CAMX, "samples": SAMPLES,
         "ortho_scale": spec.ORTHO_SCALE, "px_per_m": spec.PX_PER_M, "frames": {}}

    # --- 게임 방향(E) 의 두 클립 전부
    for act, n in (("idle", spec.ACTIONS["idle"]["frames"]),
                   ("attack", spec.ACTIONS["attack"]["frames"])):
        arm.animation_data.action = bpy.data.actions[act]
        arm.rotation_euler = (0, 0, math.radians(spec.DIRS[spec.GAME_DIR]))
        for i in range(n):
            sc.frame_set(i + 1)
            bpy.context.view_layer.update()
            p = os.path.join(FRAMES_DIR, act, spec.GAME_DIR, "%04d.png" % (i + 1))
            times.append(render_to(sc, p))
            t = sword_tip(arm)
            g = (arm.matrix_world @ arm.pose.bones["hand.R"].matrix).to_translation()
            tp, gp = project(t, ELEV, CAMC), project(g, ELEV, CAMC)
            ang = math.degrees(math.atan2(-(tp[1] - gp[1]), tp[0] - gp[0]))
            tips.setdefault(act, []).append(
                {"f": i + 1, "tip_px": [round(tp[0], 1), round(tp[1], 1)],
                 "grip_px": [round(gp[0], 1), round(gp[1], 1)], "blade_deg": round(ang, 1)})
        R["frames"][act] = n

    # --- 3D 길에만 있는 이점: 여덟 방향 (아이들 0번 칸만)
    arm.animation_data.action = bpy.data.actions["idle"]
    sc.frame_set(1)
    for dname, yaw in spec.DIRS.items():
        arm.rotation_euler = (0, 0, math.radians(yaw))
        bpy.context.view_layer.update()
        p = os.path.join(FRAMES_DIR, "idle", dname, "0001.png")
        times.append(render_to(sc, p))

    R["sword"] = tips
    R["n_renders"] = len(times)
    R["sec_per_frame"] = round(sum(times[1:]) / max(1, len(times) - 1), 4)
    R["first_render_sec"] = round(times[0], 3)
    R["total_sec"] = round(sum(times), 2)
    with open(os.path.join(OUT, "render_report%s.json" % (TAG or "")), "w") as f:
        json.dump(R, f, ensure_ascii=False, indent=1)
    print("RENDER_JSON " + json.dumps(R, ensure_ascii=False))


main()
