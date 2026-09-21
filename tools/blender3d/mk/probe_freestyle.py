#!/usr/bin/env python3
"""숙제 10번의 갈래 (c) — **Freestyle 을 crease(내부 선)만 켜서** 재 본다.

    env -u DISPLAY bl -b --factory-startup \
        --python tools/blender3d/mk/probe_freestyle.py -- --blend <blend>

계약서가 「아무도 시도 안 했다. 재 봐라」라고 적은 자리라 실제로 켜서 잰다.
재는 것 셋: 반투명 픽셀 수 · 한 장 렌더 시간 · 선이 실제로 몇 픽셀인가.
"""
import sys, time, math, argparse
from pathlib import Path
import bpy
import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE)); sys.path.insert(0, str(HERE.parent))
import spec, render as R  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ap = argparse.ArgumentParser(); ap.add_argument("--blend", default="build/b3d/jokull/2_model/jokull.blend")
a = ap.parse_args(argv)

bpy.ops.wm.open_mainfile(filepath=str(Path(a.blend).resolve()))
sc, vl = bpy.context.scene, bpy.context.view_layer
R.setup_scene(sc, vl, spec.ELEV, spec.ORTHO_SCALE, spec.CELL[0], 1)
arm = bpy.data.objects["Rig"]
arm.rotation_euler = (0, 0, math.radians(spec.DIRS[spec.GAME_DIR]))
arm.scale = (1.05, 1.05, 1.05)
sc.frame_set(1); vl.update()
arm.location.z = -R.min_screen_v(spec.ELEV) / math.cos(math.radians(spec.ELEV))
vl.update()

tmp = Path("/tmp/b3d_fs")
tmp.mkdir(exist_ok=True)


def shoot(name):
    sc.render.filepath = str(tmp / name)
    t0 = time.time()
    bpy.ops.render.render(write_still=True)
    dt = time.time() - t0
    im = np.array(Image.open(tmp / (name + ".png")).convert("RGBA"))
    semi = int(((im[:, :, 3] > 0) & (im[:, :, 3] < 255)).sum())
    dark = int(((im[:, :, 3] > 0) & (im[:, :, :3].max(axis=2) < 40)).sum())
    return dt, semi, dark


d0, s0, k0 = shoot("off")

# --- Freestyle: crease(내부 접힘)만 --------------------------------------
sc.render.use_freestyle = True
fs = vl.freestyle_settings
fs.as_render_pass = False
fs.crease_angle = math.radians(120.0)
if not fs.linesets:
    fs.linesets.new("LS")
ls = fs.linesets[0]
ls.select_silhouette = False
ls.select_border = False
ls.select_contour = False
ls.select_external_contour = False
ls.select_material_boundary = False
ls.select_ridge_valley = False
ls.select_suggestive_contour = False
ls.select_crease = True
if ls.linestyle is None:
    ls.linestyle = bpy.data.linestyles.new("LSty")
ls.linestyle.thickness = 1.0
ls.linestyle.color = (0, 0, 0)
d1, s1, k1 = shoot("crease")

print("FS_JSON " + str({
    "off":    {"sec": round(d0, 3), "semi": s0, "dark_px": k0},
    "crease": {"sec": round(d1, 3), "semi": s1, "dark_px": k1},
    "slowdown": round(d1 / max(1e-6, d0), 2),
}))
