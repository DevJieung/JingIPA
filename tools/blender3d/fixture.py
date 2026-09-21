#!/usr/bin/env python3
"""7단계 **시험대** — pack.py 를 돌려 보기 위한 낱장을 Blender 로 굽는다.

    env -u DISPLAY bl -b --factory-startup \
        --python tools/blender3d/fixture.py -- --unit fixture

★★ **이것은 후보들의 2~5단계가 아니다.** 요쿨을 모델링하는 일은 후보 셋이 저마다
   한다. 여기서 굽는 것은 **나무 인형**(박스와 원기둥으로 짠 대검잡이)이고, 쓰임은
   딱 둘이다:
     1. `pack.py` 를 **실제로 돌려 볼** 96x96 RGBA 낱장을 만든다. 더미 그림을
        손으로 그려서는 「발이 안 튀는가」·「알파가 이진인가」 같은 검사가 늘
        통과해 버려서 검사가 검사 노릇을 못 한다.
     2. **5단계가 남겨야 할 `meta.json` 의 꼴을 못 박는다.** 7단계가 총구를
        픽셀에서 더듬어 찾지 않고 **렌더가 아는 3D 좌표**를 그대로 받는 것이
        이 길의 이점인데, 그 이점은 5단계와 7단계가 같은 꼴을 약속해야만 산다.
        여기서 실제로 써 보고, pack.py 가 실제로 읽는다.

★ 규격은 `spec.py` 하나만 본다 — 셀·FPS·동작·방향·카메라가 전부 거기 있다.
★ 렌더 설정 넷(filter_size 0 · dither 0 · film_transparent · view_transform Standard)은
  앞 단계가 실측으로 못 박은 것이다. 하나라도 빠지면 도트가 망가진다.

내놓는 것:
    build/b3d/<uid>/5_frames/<action>/<dir>/f_%04d.png   96x96 RGBA
    build/b3d/<uid>/5_frames/meta.json                   ← ★ 총구 좌표가 여기 있다
"""
import json
import math
import os
import sys
import time

import bpy
from mathutils import Vector

# --- spec.py 를 읽어 온다 (Blender 내장 파이썬이라 sys.path 를 직접 놓는다) ----
HERE = os.path.dirname(os.path.abspath(bpy.data.filepath or __file__))
if "--python" in sys.argv:
    HERE = os.path.dirname(os.path.abspath(sys.argv[sys.argv.index("--python") + 1]))
sys.path.insert(0, HERE)
import spec  # noqa: E402

ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def arg(name, default):
    return ARGV[ARGV.index(name) + 1] if name in ARGV else default


UID = arg("--unit", "fixture")
ELEM = arg("--elem", "ice")
ONLY_DIR = arg("--only-dir", "")          # "E" 처럼 주면 그 방향만 (빠른 시험)

CELL_W, CELL_H = spec.CELL
#: 발이 앉을 칸 안 세로 자리(px). 밑에 여유 6px — 1도트 테두리와 눌린 자세를 위한 몫.
FOOT_PY = 90.0


# ------------------------------------------------------------------ 장면
def scene_setup():
    sc = bpy.context.scene
    # ★ 4.0 이라 EEVEE_NEXT 가 아니다. Cycles 는 Shader to RGB 를 조용히 무시한다.
    sc.render.engine = 'BLENDER_EEVEE'
    sc.render.resolution_x, sc.render.resolution_y = CELL_W, CELL_H
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    sc.render.film_transparent = True       # 알파
    sc.render.filter_size = 0.0             # 반투명 가장자리를 0개로
    sc.render.dither_intensity = 0.0        # 밴드가 ±1 로 흩어지지 않게
    sc.view_settings.view_transform = 'Standard'   # ★AgX 면 색이 통째로 밀린다
    sc.eevee.taa_render_samples = 16
    return sc


def camera(sc):
    """직교 · 내림각 ELEV. 발밑(z=0)이 칸의 FOOT_PY 줄에 오게 높이를 푼다.

    ★ 산수: 화면 세로 좌표 v = -z0*cos(e) (발밑 z=0 일 때) 이고
      픽셀 = 48 - v*PX_PER_M 이므로  z0 = (FOOT_PY - 48) / (PX_PER_M * cos(e)).
      카메라를 눈대중으로 놓으면 방향마다 발높이가 달라져 7단계의 「발 흔들림」
      검사가 터진다 — 여기서 한 번 풀어 두면 여덟 방향이 저절로 같은 줄에 선다.
    """
    e = math.radians(spec.ELEV)
    z0 = (FOOT_PY - CELL_H * 0.5) / (spec.PX_PER_M * math.cos(e))
    cd = bpy.data.cameras.new("Cam")
    cd.type = 'ORTHO'
    cd.ortho_scale = spec.ORTHO_SCALE
    cam = bpy.data.objects.new("Cam", cd)
    d = spec.CAM_DIST
    cam.location = (0.0, -d * math.cos(e), z0 + d * math.sin(e))
    cam.rotation_euler = (math.radians(90.0 - spec.ELEV), 0.0, 0.0)
    sc.collection.objects.link(cam)
    sc.camera = cam
    return cam


def toon_mat(name, shadow_hex, mid_hex, lit_hex):
    """툰 3톤 — Diffuse → ShaderToRGB → ColorRamp(CONSTANT) → Emission.

    ★ 색은 **선형**으로 넣는다(spec.hex2linear). hex 를 그대로 넣으면 한 톤 밝게
      떠서 양자화가 의도한 칸이 아니라 한 칸 위로 접는다.
    """
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    dif = nt.nodes.new("ShaderNodeBsdfDiffuse")
    s2r = nt.nodes.new("ShaderNodeShaderToRGB")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = 'CONSTANT'
    cr = ramp.color_ramp
    cr.elements[0].position = 0.00
    cr.elements[0].color = spec.hex2linear(shadow_hex) + (1.0,)
    cr.elements[1].position = 0.34
    cr.elements[1].color = spec.hex2linear(mid_hex) + (1.0,)
    cr.elements.new(0.72).color = spec.hex2linear(lit_hex) + (1.0,)
    emi = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(dif.outputs[0], s2r.inputs[0])
    nt.links.new(s2r.outputs[0], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], emi.inputs[0])
    nt.links.new(emi.outputs[0], out.inputs["Surface"])
    return m


def box(name, size, loc, parent, mat):
    """상자 하나. `loc` 은 **부모 기준 국소 좌표**다.

    ★ `primitive_cube_add(location=…)` 는 **세계 좌표**에 놓는다. 거기에 부모를
      붙이면서 `matrix_parent_inverse` 로 부모 변환을 지워 버리면, 국소 좌표로
      적어 놓은 숫자가 통째로 세계 좌표가 되어 인형이 땅바닥에 뭉친다
      (처음에 실제로 그랬다 — 다리가 칸 밖으로 나갔다).
      그래서 원점에 만든 뒤 부모를 붙이고 **국소 위치를 따로** 준다.
    """
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    o = bpy.context.object
    o.name = name
    o.scale = Vector(size)
    o.data.materials.append(mat)
    o.parent = parent
    o.location = Vector(loc)
    return o


def empty(name, loc, parent=None):
    o = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(o)
    if parent is not None:
        o.parent = parent
    o.location = Vector(loc)
    return o


# ------------------------------------------------------------------ 인형
#: 골반 높이(m) · 다리 길이 · 칼이 손에서 뻗는 길이
PELVIS_Z = 0.80
LEG_LEN = 0.78
REACH = 0.84
#: 부츠 밑면이 골반 피벗에서 얼마나 아래인가 · 부츠 y 반폭(발 흔들림 보정에 쓴다)
BOOT_DROP = LEG_LEN
BOOT_Y = 0.16


def build(pal):
    """대검잡이 나무 인형. **국소 -Y 가 앞**이고 칼팔은 국소 -X 쪽이다.

    ★ 방향 yaw 는 국소 -Y 를 돌린다: yaw 90(=E)에서 -Y → +X(화면 오른쪽).
      그래서 칼끝이 오른쪽으로 뻗고 **총구 x 가 양수**로 나온다 — 7단계가 못 박은 것.
    ★ 칼팔을 국소 -X 에 둔 것도 같은 까닭이다 — E 에서 -X → -Y(카메라 앞쪽)이라
      칼을 든 팔이 몸에 안 가린다.

    ★★ **골반과 가슴을 갈라 놓는다.** 숨쉬기·내려찍기로 상체가 눌릴 때 다리까지
      같이 움직이면 발이 칸 안에서 오르내려서, 7단계의 「발 높이 흔들림 <= 2px」
      검사가 **원리상 통과할 수 없다.** 다리는 골반에, 나머지는 가슴에 매단다.
    """
    steel = toon_mat("steel", pal[0], pal[2], pal[4])
    cloth = toon_mat("cloth", pal[1], pal[3], pal[5])
    skin = toon_mat("skin", "#2b1a12", "#b9835a", "#eec49a")
    blade = toon_mat("blade", pal[3], pal[5], pal[6])

    root = empty("root", (0, 0, 0))
    pelvis = empty("pelvis", (0, 0, PELVIS_Z), root)
    chest = empty("chest", (0, 0, 0), pelvis)

    box("torso", (0.46, 0.30, 0.62), (0, 0, 0.18), chest, cloth)
    box("belt", (0.50, 0.34, 0.09), (0, 0, -0.11), chest, steel)
    box("head", (0.28, 0.26, 0.28), (0, 0, 0.66), chest, skin)
    box("hood", (0.40, 0.38, 0.24), (0, 0.03, 0.74), chest, cloth)
    box("beard", (0.22, 0.16, 0.22), (0, -0.14, 0.53), chest, blade)

    legL = empty("legL", (0.14, 0, 0.0), pelvis)
    legR = empty("legR", (-0.14, 0, 0.0), pelvis)
    for nm, leg in (("L", legL), ("R", legR)):
        box("thigh" + nm, (0.18, 0.18, LEG_LEN), (0, 0, -LEG_LEN * 0.5), leg, cloth)
        # ★ 부츠는 **앞뒤로 대칭**이어야 한다. 발끝을 앞으로 내밀면 다리를
        #   앞으로 흔들 때와 뒤로 흔들 때 제일 낮은 모서리가 서로 달라져서,
        #   골반을 아무리 정확히 되돌려도 발이 한 칸 걸러 1~2px 오르내린다.
        box("boot" + nm, (0.22, BOOT_Y * 2, 0.14), (0, 0, -LEG_LEN + 0.07),
            leg, steel)

    # 칼팔 — 국소 -X 쪽
    armR = empty("armR", (-0.28, 0, 0.40), chest)
    box("upperR", (0.15, 0.15, 0.44), (0, 0, -0.20), armR, cloth)
    box("foreR", (0.14, 0.34, 0.14), (0, -0.20, -0.38), armR, skin)
    grip = empty("grip", (0, -0.30, -0.40), armR)
    box("guard", (0.34, 0.07, 0.07), (0, -0.05, 0), grip, steel)
    box("blade", (0.11, 0.74, 0.05), (0, -0.44, 0), grip, blade)
    tip = empty("tip", (0, -REACH, 0), grip)          # ★ 총구 — 칼끝

    armL = empty("armL", (0.28, 0, 0.40), chest)
    box("upperL", (0.15, 0.15, 0.44), (0, 0, -0.20), armL, cloth)
    box("foreL", (0.14, 0.14, 0.40), (0, -0.06, -0.56), armL, skin)

    return {"root": root, "pelvis": pelvis, "chest": chest,
            "legL": legL, "legR": legR, "armR": armR, "armL": armL,
            "grip": grip, "tip": tip}


# ------------------------------------------------------------------ 자세
def _arm(rig, shoulder_deg, blade_deg):
    """어깨 각과 **칼날 각**을 따로 준다.

    ★ 칼날 각은 어깨 각과 손목 각의 **합**이다 (둘 다 X 축 회전이라 그냥 더해진다).
      손목 각을 직접 적으면 어깨를 조금 고칠 때마다 칼이 통째로 다른 데를 겨눈다.
      「칼이 어디를 겨누는가」가 곧 총구라, 그 각을 손잡이로 꺼내 둔다.
    """
    rig["armR"].rotation_euler = (math.radians(shoulder_deg), 0, 0)
    rig["grip"].rotation_euler = (math.radians(blade_deg - shoulder_deg), 0, 0)


def pose(rig, action, i, n):
    """키프레임 없이 **그 칸의 자세를 바로 놓는다.** 결정적이라 다시 돌려도 같다."""
    t = i / float(n)
    rig["pelvis"].location.z = PELVIS_Z
    rig["chest"].location.z = 0.0
    rig["legL"].rotation_euler = rig["legR"].rotation_euler = (0, 0, 0)

    if action == "idle":
        # 숨쉬기 — 가슴만 2cm 오르내린다. **다리는 안 움직인다**(발 흔들림 0).
        rig["chest"].location.z = 0.022 * math.sin(2 * math.pi * t)
        sw = 5.0 * math.sin(2 * math.pi * t)
        _arm(rig, -12 + sw, 52 + sw)          # 대검을 앞으로 비스듬히 내려 든다
        rig["armL"].rotation_euler = (math.radians(12 - sw), 0, 0)
    elif action == "walk":
        a = math.radians(26.0) * math.sin(2 * math.pi * t)
        rig["legL"].rotation_euler = (a, 0, 0)
        rig["legR"].rotation_euler = (-a, 0, 0)
        # ★★ 다리를 벌린 만큼 골반을 **정확히** 되돌린다. 안 하면 두 발이
        #   **같이** 뜬다 — cos 은 짝함수라 앞다리와 뒷다리가 똑같이 뜬다.
        #   ☆ 되돌릴 몫은 「발 가운데」가 아니라 **부츠의 제일 낮은 모서리**로 재야
        #     한다. 가운데로 재면(= LEG_LEN*(1-cos a)) 부츠가 같이 기울면서
        #     앞뒤 모서리가 그만큼 더 내려가는 몫을 놓쳐서, walk 만 발이 3px
        #     내려앉는다(실측: 93 → 96 — 검사선 2px 를 넘겼다).
        rig["pelvis"].location.z = (PELVIS_Z - BOOT_DROP * (1.0 - math.cos(a))
                                    + BOOT_Y * abs(math.sin(a)))
        rig["chest"].location.z = 0.012 * math.cos(4 * math.pi * t)
        _arm(rig, -12 - math.degrees(a) * 0.35, 52 - math.degrees(a) * 0.35)
        rig["armL"].rotation_euler = (math.radians(12) + a * 0.5, 0, 0)
    elif action == "attack":
        hit = spec.ACTIONS["attack"]["hit"]
        # ★★ 놓는 칸에서 **칼끝이 가슴 높이에 오게** 잡는다. 처음에는 땅까지
        #   내리찍게 짰는데, 7단계(pack.py)가 「총구 세로/몸높이 = -0.27」로
        #   `ns_check` 의 띠(-1.30~-0.30)를 넘겨서 잡았다 — 게임에서 탄이
        #   발목 높이에서 나간다는 뜻이다. 자세를 고칠 일이지 검사를 고칠 일이 아니다.
        if i <= hit:                                   # 0 → 놓는 칸: 젖혔다 베어 낸다
            k = i / float(hit)
            sh = -60.0 + 85.0 * k
            bl = -80.0 + 75.0 * k
            rig["chest"].location.z = -0.035 * math.sin(math.pi * k)
        else:                                          # 놓은 뒤 — 되돌아온다
            k = (i - hit) / float(n - 1 - hit)
            sh = 25.0 - 30.0 * k
            bl = -5.0 + 30.0 * k
        _arm(rig, sh, bl)
        rig["armL"].rotation_euler = (math.radians(16 - 6 * (i > hit)), 0, 0)
    bpy.context.view_layer.update()


# ------------------------------------------------------------------ 총구
def px_of(sc, cam, world):
    """세계 좌표 → 칸 픽셀(좌상단 원점 · 아래로 +).

    ★★ **이것이 3D 길의 이점이다.** 2D 영상 길은 총구를 픽셀에서 더듬어 찾는다
      (`to_game.muzzle` — 몸통 위쪽 65% 안에서 제일 오른쪽 점). 그 자는 소품이
      길거나 앞발을 내디디면 엉뚱한 곳을 짚는다. 3D 는 **칼끝이 어디인지 애초에
      안다.**
    """
    from bpy_extras.object_utils import world_to_camera_view
    v = world_to_camera_view(sc, cam, world)
    return [round(v.x * CELL_W, 2), round((1.0 - v.y) * CELL_H, 2)]


# ------------------------------------------------------------------ 굽기
def main():
    t0 = time.time()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = scene_setup()
    cam = camera(sc)

    ld = bpy.data.lights.new("Sun", 'SUN')
    ld.energy = 3.2
    lo = bpy.data.objects.new("Sun", ld)
    # ★ 해는 **월드에 고정**이다. 인형만 돌므로 여덟 방향이 저마다 다른 면이 밝다.
    lo.rotation_euler = (math.radians(52), 0, math.radians(-38))
    sc.collection.objects.link(lo)

    rig = build(spec.RAMP[ELEM])

    p = spec.paths(UID)
    fr_root = p["frames"]
    dirs = {ONLY_DIR: spec.DIRS[ONLY_DIR]} if ONLY_DIR else spec.DIRS

    muz = {}          # 계약 꼴: {"attack": [[x,y], …]}  ← 게임 방향
    muz_all = {}      # 덤: 방향마다
    n_img = 0
    for act, cfg in spec.ACTIONS.items():
        n = cfg["frames"]
        muz_all[act] = {}
        for dname, yaw in dirs.items():
            rig["root"].rotation_euler = (0, 0, math.radians(yaw))
            outd = fr_root / act / dname
            outd.mkdir(parents=True, exist_ok=True)
            pts = []
            for i in range(n):
                pose(rig, act, i, n)
                pts.append(px_of(sc, cam, rig["tip"].matrix_world.translation))
                sc.render.filepath = str(outd / ("f_%04d" % (i + 1)))
                bpy.ops.render.render(write_still=True)
                n_img += 1
            muz_all[act][dname] = pts
            if dname == spec.GAME_DIR:
                muz[act] = pts

    meta = {
        "unit": UID, "elem": ELEM,
        "source": "tools/blender3d/fixture.py (나무 인형 · pack.py 시험대)",
        "cell": {"w": CELL_W, "h": CELL_H},
        "fps": spec.FPS,
        "actions": {a: dict(c) for a, c in spec.ACTIONS.items()},
        "dirs": list(dirs),
        "game_dir": spec.GAME_DIR,
        "camera": {"ortho_scale": spec.ORTHO_SCALE, "px_per_m": spec.PX_PER_M,
                   "elev_deg": spec.ELEV, "foot_py": FOOT_PY},
        # ★★ 7단계와의 계약. 아래 셋이 한 벌이다.
        "muzzle_origin": "cell_topleft",   # 칸 좌상단 원점
        "muzzle_y_down": True,             # 아래가 +
        "muzzle_px": muz,                  # {"attack": [[x,y], …]}  ← game_dir
        "muzzle_px_dirs": muz_all,         # 덤 — 방향마다 (7단계가 안 봐도 된다)
    }
    (fr_root / "meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent=1))
    dt = time.time() - t0
    print("FIXTURE_OK unit=%s imgs=%d dirs=%d %.1fs (%.3fs/장)"
          % (UID, n_img, len(dirs), dt, dt / max(1, n_img)))
    print("  → %s" % fr_root)
    hit = spec.ACTIONS["attack"]["hit"]
    print("  놓는 칸 %d 의 칼끝(%s) = %s" % (hit, spec.GAME_DIR, muz["attack"][hit]))


main()
