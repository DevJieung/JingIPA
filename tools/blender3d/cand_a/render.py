#!/usr/bin/env python3
"""후보 A · 5단계 — 직교 툰 렌더. **한 프로세스 안에서 전부 돈다.**

    env -u DISPLAY bl -b --factory-startup --python tools/blender3d/cand_a/render.py -- \
        --blend build/b3d/cand_a/2_model/jokull.blend --out build/b3d/cand_a/5_frames

★ 프로세스마다 blender 를 새로 띄우면 EEVEE 의 GPU 컨텍스트 잡는 데 매번 1초가
  든다(앞 단계 실측). 여기서는 한 번 잡고 96x96 한 장에 0.106초로 돈다.

## 반드시 박아야 하는 넷 (하나라도 빠지면 도트가 망가진다)
  filter_size = 0        → 반투명 가장자리가 **정확히 0개**가 된다
  dither_intensity = 0   → 같은 띠가 ±1 로 흩어지지 않는다
  film_transparent       → 알파
  view_transform='Standard' → 넣은 색이 그대로 찍힌다 (기본 AgX 면 통째로 밀린다)

## 카메라 — 「발밑 원점」을 못 박는다
직교라 캐릭터를 **아마추어 오브젝트째로** yaw 돌린다. 원점이 발밑(0,0,0)이라
어느 방향으로 돌려도 발이 같은 줄에 선다 — 발밑 흔들림이 **산수로 0** 이다.
카메라 높이는 발이 칸 밑에서 세 줄쯤 위에 오도록 역산했다(아래 CAM_Z).
"""
import sys, os, math, time, json, argparse
from pathlib import Path

import bpy
from mathutils import Vector

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))
import spec        # noqa: E402
import rigdef as RD  # noqa: E402

#: 채움광 세기 (리스트로 둔 것은 --fill 로 갈아 끼우기 위해서다)
FILL = [0.35]

#: 발이 칸의 몇 번째 줄에 오게 할까 (0=맨 위). 96칸에서 93 이면 밑에 3px 여유.
#: ★ 2차에 90 이었는데 S·NE·SW 방향에서 **앞발이 칸 아래로 잘렸다.**
#:   내림각 20도라 카메라에 가까운 발이 화면에서 더 아래로 내려간다 —
#:   그 몫(0.342 x 깊이)을 안 빼면 방향을 돌릴 때마다 발이 칸을 넘는다.
#:   88 로도 S·SW 방향의 앞발이 **맨 아랫줄(95)** 에 닿아 후처리가 두를
#:   1도트 테두리가 잘렸다. 86 이면 여덟 방향이 다 안쪽에 든다.
FOOT_ROW = 86.0


def cam_z_for(foot_row, elev_deg, ortho, cell):
    """발밑(월드 z=0)이 `foot_row` 줄에 오도록 카메라가 볼 높이를 역산한다.

    화면 세로축 u = (0, sin(e), cos(e)). 임의의 점 Q 의 화면 오프셋(미터)은
        off = 0.342*qy + cos(e)*qz - cos(e)*z_c
    발(0,0,0)이 가운데에서 (foot_row - cell/2) 픽셀만큼 **아래**여야 하므로
        cos(e)*z_c = (foot_row - cell/2) / px_per_m
    """
    px_per_m = cell / ortho
    e = math.radians(elev_deg)
    return ((foot_row - cell / 2.0) / px_per_m) / math.cos(e)


def setup_scene(sc, vl, elev, ortho, cell, samples, shadows):
    sc.render.engine = 'BLENDER_EEVEE'
    sc.render.resolution_x = sc.render.resolution_y = cell
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    sc.render.image_settings.color_depth = '8'
    sc.render.image_settings.compression = 0
    sc.render.film_transparent = True
    sc.render.filter_size = 0.0          # ★ 반투명 0
    sc.render.dither_intensity = 0.0     # ★ 밴딩이 흩어지지 않게
    sc.render.use_file_extension = True
    sc.view_settings.view_transform = 'Standard'   # ★ AgX 면 색이 밀린다
    sc.view_settings.look = 'None'
    sc.view_settings.exposure = 0.0
    sc.view_settings.gamma = 1.0
    sc.eevee.taa_render_samples = samples
    for attr, val in (("use_bloom", False), ("use_gtao", False),
                      ("use_ssr", False), ("use_soft_shadows", False)):
        if hasattr(sc.eevee, attr):
            setattr(sc.eevee, attr, val)

    # 월드는 새까맣게 — 그늘 쪽이 램프 0번 칸에 정확히 앉는다
    w = bpy.data.worlds.new("W")
    w.use_nodes = False
    w.color = (0, 0, 0)
    sc.world = w

    # 카메라
    cz = cam_z_for(FOOT_ROW, elev, ortho, cell)
    e = math.radians(elev)
    cd = bpy.data.cameras.new("Cam")
    cd.type = 'ORTHO'
    cd.ortho_scale = ortho
    cd.clip_start, cd.clip_end = 0.1, 60.0
    cam = bpy.data.objects.new("Cam", cd)
    cam.location = (0.0, -spec.CAM_DIST * math.cos(e), cz + spec.CAM_DIST * math.sin(e))
    cam.rotation_euler = (math.radians(90 - elev), 0.0, 0.0)
    sc.collection.objects.link(cam)
    sc.camera = cam

    # 해 하나 — 화면 오른쪽 위·카메라 쪽에서 온다.
    # ★ 빛은 **월드에 고정**한다. 캐릭터에 붙이면 여덟 방향이 전부 같은 음영으로
    #   나와서, 3D 길이 공짜로 주는 「돌면 다른 면이 밝다」가 통째로 사라진다.
    ld = bpy.data.lights.new("Sun", 'SUN')
    ld.energy = 3.14           # /pi → 정면이 1.0 에 닿는다
    ld.angle = 0.0
    ld.use_shadow = shadows
    lo = bpy.data.objects.new("Sun", ld)
    lo.rotation_euler = (math.radians(51), 0.0, math.radians(45))
    sc.collection.objects.link(lo)
    # 반대쪽 채움광 — 그늘이 통째로 램프 0번에 뭉치면 「3톤 중 1톤」이 된다
    ld2 = bpy.data.lights.new("Fill", 'SUN')
    ld2.energy = FILL[0]
    ld2.angle = 0.0
    ld2.use_shadow = False
    lo2 = bpy.data.objects.new("Fill", ld2)
    lo2.rotation_euler = (math.radians(112), 0.0, math.radians(-140))
    sc.collection.objects.link(lo2)
    return cam, cz


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--blend", default="build/b3d/cand_a/2_model/jokull.blend")
    ap.add_argument("--out", default="build/b3d/cand_a/5_frames")
    ap.add_argument("--elev", type=float, default=spec.ELEV)
    ap.add_argument("--samples", type=int, default=16)
    ap.add_argument("--shadows", action="store_true")
    ap.add_argument("--fill", type=float, default=FILL[0])
    ap.add_argument("--foot-row", type=float, default=FOOT_ROW)
    ap.add_argument("--acts", default="idle,attack")
    ap.add_argument("--dirs-of", default="idle", help="8방향 첫 칸을 뽑을 동작")
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    a = ap.parse_args(argv)

    FILL[0] = a.fill
    globals()["FOOT_ROW"] = a.foot_row
    t_all = time.time()
    bpy.ops.wm.open_mainfile(filepath=str(Path(a.blend).resolve()))
    sc, vl = bpy.context.scene, bpy.context.view_layer
    cam, cz = setup_scene(sc, vl, a.elev, spec.ORTHO_SCALE, spec.CELL[0],
                          a.samples, a.shadows)
    arm = bpy.data.objects["Rig"]

    outroot = Path(a.out)
    n_frames = 0
    t_render = 0.0

    def shoot(path):
        nonlocal n_frames, t_render
        path.parent.mkdir(parents=True, exist_ok=True)
        sc.render.filepath = str(path.with_suffix(""))
        t0 = time.time()
        bpy.ops.render.render(write_still=True)
        t_render += time.time() - t0
        n_frames += 1

    # ---- 게임이 쓰는 한 방향(E) 은 동작 전부를 다 뽑는다
    yaw_e = math.radians(spec.DIRS[spec.GAME_DIR])
    for act in a.acts.split(","):
        act = act.strip()
        if not act:
            continue
        arm.animation_data.action = bpy.data.actions[act]
        arm.rotation_euler = (0, 0, yaw_e)
        vl.update()
        for i in range(spec.ACTIONS[act]["frames"]):
            sc.frame_set(i + 1)
            vl.update()
            shoot(outroot / act / spec.GAME_DIR / f"{i + 1:04d}.png")

    # ---- 나머지 일곱 방향은 첫 칸만 (3D 길이 공짜로 주는 것의 증거)
    arm.animation_data.action = bpy.data.actions[a.dirs_of]
    sc.frame_set(1)
    for dname, yaw in spec.DIRS.items():
        if dname == spec.GAME_DIR:
            continue
        arm.rotation_euler = (0, 0, math.radians(yaw))
        vl.update()
        shoot(outroot / a.dirs_of / dname / "0001.png")

    total = time.time() - t_all
    print("RENDER_JSON " + json.dumps({
        "frames": n_frames, "render_sec": round(t_render, 2),
        "sec_per_frame": round(t_render / max(1, n_frames), 4),
        "total_sec": round(total, 2), "cam_z": round(cz, 4),
        "elev": a.elev, "samples": a.samples, "shadows": a.shadows,
        "out": str(outroot)}))


# ★ 가드를 둔다 — blender 는 --python 으로 돌릴 때 __name__ 이 "__main__" 이라
#   이 파일을 **다른 스크립트가 import** 해서 함수만 빌려 쓸 수 있다(디버그 렌더).
if __name__ == "__main__":
    main()
