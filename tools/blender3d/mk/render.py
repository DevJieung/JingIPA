#!/usr/bin/env python3
"""최종본 · 5단계 — 직교 툰 렌더 + **내부 선화** + `meta.json`. 한 프로세스 안에서 다 돈다.

    env -u DISPLAY bl -b --factory-startup --python tools/blender3d/mk/render.py -- \
        --blend build/b3d/jokull/2_model/jokull.blend

## 반드시 박는 다섯 (하나라도 빠지면 도트가 망가진다)
  filter_size=0 · dither=0 · film_transparent · view_transform='Standard'
  + `taa_render_samples=1`  ← 이것이 있어야 툰이 **정확히 3톤**이 된다.
    16 샘플이면 지터가 램프 문턱을 걸쳐서 한 재질이 9색으로 흩어진다(실측).

## 프레임마다 두 장을 굽는다
  1) 색 — 툰 3톤
  2) 번호+깊이 — `material_override` + `view_transform='Raw'` (lineart.py 가 읽는다)
그리고 둘을 합쳐 `5_frames/<act>/<dir>/*.png` 로 낸다. 6단계는 이것만 본다.

## ★★ 발밑을 **픽셀로** 맞춘다 (숙제 11·14번)
후보 셋이 공통으로 걸린 자리다 — 내림각 20도라 화면 세로는 `y·sin20 + z·cos20`
이고, 발의 앞뒤 비대칭이 yaw 에 따라 바닥선을 움직인다(3~4px). 그래서:
  1. 정점을 훑어 화면 세로 최솟값을 재고 리그를 그만큼 내린다(산수).
  2. **실제로 한 장 굽고 알파 아래끝을 재서** 남은 오차를 갚는다(픽셀).
2번이 있어서 자세 표가 못 푸는 몫(발이 몇 mm 파고드는 것)까지 사라진다 —
walk 도 attack 도 여덟 방향도 **발밑 흔들림이 0** 이 된다.
"""
import sys, os, math, time, json, argparse, tempfile
from pathlib import Path

import bpy
import numpy as np
from PIL import Image
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))
import spec          # noqa: E402
import lineart       # noqa: E402
#: ★ 캐릭터마다 다른 것은 `rigdef*` 모듈 하나뿐이다 — `--rigdef` 로 고른다.
#:   여기서 읽는 것은 `MUZ_BONE`(총구가 붙은 뼈) · `MUZ_LOCAL`(그 뼈 공간의 점) ·
#:   `FAMILY`(anim.json 의 무리) 셋뿐이라, 새 캐릭터가 와도 이 파일은 안 는다.

#: 알파 아래끝(getbbox()[3])이 앉을 자리. 6단계가 테두리를 1px 더 두르므로
#: 여기가 91 이면 최종 92 — 칸 밑에 4px 이 남는다(테두리가 안 잘린다).
FOOT_BOTTOM = 91
#: 그러려면 제일 낮은 점이 픽셀 세로 90.5(=90번 줄의 한가운데)에 와야 한다.
FOOT_ROW = FOOT_BOTTOM - 0.5

LINE_HEX = "#000000"        # 내부 선 색
FILL_ENERGY = 0.42
SUN_ENERGY = 3.14


def cam_z_for(foot_row, elev_deg, ortho, cell):
    px_per_m = cell / ortho
    e = math.radians(elev_deg)
    return ((foot_row - cell / 2.0) / px_per_m) / math.cos(e)


def setup_scene(sc, vl, elev, ortho, cell, samples):
    sc.render.engine = 'BLENDER_EEVEE'
    sc.render.resolution_x = sc.render.resolution_y = cell
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    sc.render.image_settings.color_depth = '8'
    sc.render.image_settings.compression = 0
    sc.render.film_transparent = True
    sc.render.filter_size = 0.0
    sc.render.dither_intensity = 0.0
    sc.render.use_file_extension = True
    sc.view_settings.view_transform = 'Standard'
    sc.view_settings.look = 'None'
    sc.view_settings.exposure = 0.0
    sc.view_settings.gamma = 1.0
    sc.eevee.taa_render_samples = samples
    for attr in ("use_bloom", "use_gtao", "use_ssr", "use_soft_shadows"):
        if hasattr(sc.eevee, attr):
            setattr(sc.eevee, attr, False)

    w = bpy.data.worlds.new("W")
    w.use_nodes = False
    w.color = (0, 0, 0)
    sc.world = w

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

    # 해 — 화면 오른쪽 위·카메라 쪽. **월드에 고정**한다(방향마다 다른 면이 밝다)
    ld = bpy.data.lights.new("Sun", 'SUN')
    ld.energy = SUN_ENERGY
    ld.angle = 0.0
    ld.use_shadow = False
    lo = bpy.data.objects.new("Sun", ld)
    lo.rotation_euler = (math.radians(51), 0.0, math.radians(38))
    sc.collection.objects.link(lo)
    ld2 = bpy.data.lights.new("Fill", 'SUN')
    ld2.energy = FILL_ENERGY
    ld2.angle = 0.0
    ld2.use_shadow = False
    lo2 = bpy.data.objects.new("Fill", ld2)
    lo2.rotation_euler = (math.radians(112), 0.0, math.radians(-140))
    sc.collection.objects.link(lo2)
    return cam, cz


def meshes():
    return [o for o in bpy.data.objects if o.type == 'MESH']


def min_screen_v(elev):
    """정점을 훑어 **화면 세로 최솟값**(m)을 잰다. 곧 「제일 낮게 찍히는 점」이다."""
    e = math.radians(elev)
    se, ce = math.sin(e), math.cos(e)
    lo = 1e9
    for ob in meshes():
        M = ob.matrix_world
        for v in ob.data.vertices:
            p = M @ v.co
            s = p.y * se + p.z * ce
            if s < lo:
                lo = s
    return lo


class Shooter:
    def __init__(self, sc, vl, idmat, tmp):
        self.sc, self.vl, self.idmat, self.tmp = sc, vl, idmat, tmp
        self.n = 0
        self.t = 0.0

    def _one(self, path):
        self.sc.render.filepath = str(Path(path).with_suffix(""))
        t0 = time.time()
        bpy.ops.render.render(write_still=True)
        self.t += time.time() - t0
        self.n += 1

    def color(self):
        p = self.tmp / "c.png"
        self._one(p)
        return np.array(Image.open(p).convert("RGBA"))

    def idpass(self):
        """★ 번호+깊이. 뷰 트랜스폼을 'Raw' 로 바꾸지 않으면 번호가 뭉개진다."""
        self.vl.material_override = self.idmat
        old = self.sc.view_settings.view_transform
        self.sc.view_settings.view_transform = 'Raw'
        p = self.tmp / "i.png"
        self._one(p)
        self.sc.view_settings.view_transform = old
        self.vl.material_override = None
        return np.array(Image.open(p).convert("RGBA"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--blend", default="build/b3d/jokull/2_model/jokull.blend")
    ap.add_argument("--out", default="")
    ap.add_argument("--unit", default="jokull")
    ap.add_argument("--elem", default="ice")
    ap.add_argument("--elev", type=float, default=spec.ELEV)
    ap.add_argument("--samples", type=int, default=1)
    ap.add_argument("--fill", type=float, default=FILL_ENERGY)
    ap.add_argument("--no-lines", action="store_true")
    #: ★ 리그를 통째로 키운다. 공식 마스터의 몸높이가 79px 인데 우리는 85px 이라
    #:   이미 크지만, **채운 넓이**는 아직 모자란다(0.386 vs 0.441). 칸에 남은
    #:   여백만큼 키우는 손잡이다 — 너무 키우면 감는 칸의 칼이 칸 위를 뚫는다.
    ap.add_argument("--zoom", type=float, default=1.0)
    #: ★ 정렬을 끄고 굽는다 — 「발목 뼈만으로 얼마나 되는가」를 재는 자(ablation).
    ap.add_argument("--no-align", action="store_true")
    ap.add_argument("--rigid-foot", action="store_true",
                    help="발목을 정강이에 붙여 굴린다 — 후보 A 의 강체 막대를 흉내 낸다")
    ap.add_argument("--rigdef", default="rigdef",
                    help="캐릭터의 뼈·자세 모듈 이름 (rigdef | rigdef_solana …)")
    ap.add_argument("--acts", default="idle,walk,attack")
    ap.add_argument("--dirs-of", default="idle")
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    a = ap.parse_args(argv)

    RD = __import__(a.rigdef)

    t_all = time.time()
    bpy.ops.wm.open_mainfile(filepath=str(Path(a.blend).resolve()))
    sc, vl = bpy.context.scene, bpy.context.view_layer
    globals()["FILL_ENERGY"] = a.fill
    cam, cz = setup_scene(sc, vl, a.elev, spec.ORTHO_SCALE, spec.CELL[0], a.samples)
    arm = bpy.data.objects["Rig"]
    arm.scale = (a.zoom, a.zoom, a.zoom)
    idmat = bpy.data.materials["IDDEPTH"]
    noline = {ob.pass_index for ob in meshes() if not ob.get("b3d_line", True)}
    ids = {ob.name: ob.pass_index for ob in meshes()}

    p = spec.paths(a.unit)
    outroot = Path(a.out) if a.out else p["frames"]
    rawroot = p["root"] / "5_raw"
    for d in (outroot, rawroot):
        d.mkdir(parents=True, exist_ok=True)
    tmp = Path(tempfile.mkdtemp(prefix="b3d_"))
    sh = Shooter(sc, vl, idmat, tmp)
    line_rgb = spec.hex2rgb(LINE_HEX)
    ce = math.cos(math.radians(a.elev))
    px_per_m = spec.PX_PER_M

    #: ★ 총구는 「그 뼈 공간의 한 점」이다 — 검이면 날의 55% 지점, 활이면 활채 앞.
    #:   픽셀을 더듬지 않고 **뼈를 화면에 투영해** 잰다(18-8).
    muz_bone = arm.pose.bones[RD.MUZ_BONE]
    muz_local = Vector(RD.MUZ_LOCAL)

    log = []
    muz = {}
    muz_all = {}
    fixes = 0

    def shoot_frame(act, dname, i, path_out, path_raw):
        nonlocal fixes
        # --- 1) 산수로 맞춘다 ------------------------------------------------
        arm.location = (0.0, 0.0, 0.0)
        vl.update()
        if not a.no_align:
            arm.location.z = -min_screen_v(a.elev) / ce
            vl.update()
        col = sh.color()
        # --- 2) 픽셀로 갚는다 ------------------------------------------------
        for _ in range(0 if a.no_align else 3):
            bb = Image.fromarray(col).getbbox()
            if bb is None:
                break
            err = bb[3] - FOOT_BOTTOM
            if err == 0:
                break
            arm.location.z += err / (px_per_m * ce)
            vl.update()
            col = sh.color()
            fixes += 1
        # --- 2-1) 가로로 넘치면 밀어 넣는다 ------------------------------------
        #  ★ 게임 방향(SE)에서는 한 번도 안 걸린다. 걸리는 것은 **순수 옆모습**
        #    (E·W)뿐이다 — 팔 0.55m + 날 1.0m 이 통째로 화면 가로로 서면 62px 라
        #    반칸(48px)을 넘는다. SE 는 그 몫에 0.707 이 곱해져서 44px 로 준다.
        #    (그것이 GAME_DIR 을 SE 로 옮긴 값이 얼마인지를 재는 자다)
        #  ★★ **잘린 폭은 bbox 로 못 잰다.** 칸 밖으로 나간 몫은 bbox 에 안 잡히므로
        #    (x1 이 96 에서 포화한다) 한 번 밀어서는 모자란다 — 테두리에 닿은
        #    픽셀이 0 이 될 때까지 두 칸씩 민다.
        for _ in range(8):
            al0 = col[:, :, 3] > 0
            l, r = int(al0[:, 0].sum()), int(al0[:, 95].sum())
            if not l and not r:
                break
            if l and r:
                break                      # 좌우가 다 넘친다 — 밀어서 못 푼다
            arm.location.x += (2 if l else -2) / px_per_m
            vl.update()
            col = sh.color()
            fixes += 1
        idp = sh.idpass()
        n_line = 0
        if not a.no_lines:
            col2, n_line = lineart.apply_lines(col, idp[:, :, :3], line_rgb, noline)
        else:
            col2 = col
        Image.fromarray(col).save(path_raw)
        Image.fromarray(col2).save(path_out)
        # --- 3) 잣대 ---------------------------------------------------------
        im = Image.fromarray(col2)
        bb = im.getbbox()
        al = col2[:, :, 3] > 0
        edge = int(al[0, :].sum() + al[:, 0].sum() + al[:, 95].sum())
        # 총구 — 칼날 한가운데를 화면에 투영한다(픽셀을 더듬지 않는다)
        wp = arm.matrix_world @ (muz_bone.matrix @ muz_local)
        v = world_to_camera_view(sc, cam, wp)
        mp = [round(v.x * spec.CELL[0], 2), round((1.0 - v.y) * spec.CELL[1], 2)]
        log.append({"act": act, "dir": dname, "i": i, "bbox": list(bb) if bb else None,
                    "fill": int(al.sum()), "line_px": n_line, "edge_px": edge,
                    "z": round(arm.location.z, 5), "muz": mp})
        return mp

    for act in [s.strip() for s in a.acts.split(",") if s.strip()]:
        n = spec.ACTIONS[act]["frames"]
        arm.animation_data.action = bpy.data.actions[act]
        muz_all[act] = {}
        for dname, yaw in spec.DIRS.items():
            only_game = (dname != spec.GAME_DIR)
            if only_game and act != a.dirs_of:
                continue
            cnt = 1 if only_game else n
            od = outroot / act / dname
            rd = rawroot / act / dname
            od.mkdir(parents=True, exist_ok=True)
            rd.mkdir(parents=True, exist_ok=True)
            pts = []
            for i in range(cnt):
                sc.frame_set(i + 1)
                arm.rotation_euler = (0, 0, math.radians(yaw))
                vl.update()
                pts.append(shoot_frame(act, dname, i,
                                       od / ("%04d.png" % (i + 1)),
                                       rd / ("%04d.png" % (i + 1))))
            muz_all[act][dname] = pts
            if dname == spec.GAME_DIR:
                muz[act] = pts

    meta = {
        "unit": a.unit, "elem": a.elem,
        "source": "tools/blender3d/mk (Blender 4.0 low-poly toon · 내부 선화)",
        "cell": {"w": spec.CELL[0], "h": spec.CELL[1]},
        "fps": spec.FPS,
        "actions": {k: dict(v) for k, v in spec.ACTIONS.items()},
        "dirs": list(spec.DIRS),
        "game_dir": spec.GAME_DIR,
        "family": getattr(RD, "FAMILY", "slash"),
        "camera": {"ortho_scale": spec.ORTHO_SCALE, "px_per_m": px_per_m,
                   "elev_deg": a.elev, "foot_bottom": FOOT_BOTTOM, "cam_z": round(cz, 4)},
        # ★★ 7단계와의 계약 — 셋이 한 벌이다
        "muzzle_origin": "cell_topleft",
        "muzzle_y_down": True,
        "muzzle_px": muz,
        "muzzle_px_dirs": muz_all,
        "muzzle_note": getattr(RD, "MUZ_NOTE", "뼈를 화면에 투영해 잰다"),
        "ids": ids, "noline": sorted(noline),
        "lines": not a.no_lines,
        "frames_log": log,
    }
    (outroot / "meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent=1))

    feet = [x["bbox"][3] for x in log if x["bbox"]]
    tops = [x["bbox"][1] for x in log if x["bbox"]]
    print("RENDER_JSON " + json.dumps({
        "frames": sh.n, "render_sec": round(sh.t, 2),
        "sec_per_frame": round(sh.t / max(1, sh.n), 4),
        "total_sec": round(time.time() - t_all, 2),
        "align_fixes": fixes,
        "foot_bottom": [min(feet), max(feet)],
        "top": [min(tops), max(tops)],
        "edge_px_total": sum(x["edge_px"] for x in log),
        "line_px_avg": round(sum(x["line_px"] for x in log) / max(1, len(log)), 1),
        "fill_ratio_game": round(
            sum(x["fill"] for x in log if x["dir"] == spec.GAME_DIR)
            / max(1, sum(1 for x in log if x["dir"] == spec.GAME_DIR)) / 9216.0, 4),
        "out": str(outroot)}))


if __name__ == "__main__":
    main()
