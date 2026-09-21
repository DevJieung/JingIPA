#!/usr/bin/env python3
"""★ 3D 길에만 있는 이점을 **실제로 굽는다** — Blender 안에서 도는 유일한 스크립트.

    env -u DISPLAY bl -b --factory-startup --python tools/blender3d/extras/bl_render.py -- \
        --job recolor
    env -u DISPLAY bl -b --factory-startup --python tools/blender3d/extras/bl_render.py -- \
        --job dirs8

`tools/blender3d/mk/` 는 **읽고 import 만** 한다 (다른 에이전트가 쓰고 있다).
쓰는 곳은 `build/b3d/extras/` 뿐이다.

## 왜 mk/render.py 를 그대로 안 부르는가
`render.main()` 은 산출물 자리를 `spec.paths(unit)` 으로 못 박아서 `5_raw` 를
**남의 디렉터리에** 쓴다. 그래서 정렬 고리(산수 한 번 + 픽셀 세 번)만 여기로 옮겨
베끼고, 장면·카메라·조명·선화는 `render` 모듈의 것을 **그대로 부른다** — 그래야
여기서 나온 그림이 본선 파이프라인의 그림과 같은 자로 잰 것이 된다.

## 두 가지 일
1. `--job recolor` — 재질의 툰 램프를 **속성 다섯**으로 갈아 끼워 idle 6칸씩 굽는다.
   갈아 끼우는 규칙은 「얼음 램프의 몇 번째 칸인가」를 그대로 옮기는 것뿐이다
   (`spec.RAMP["ice"].index(hex)` → `spec.RAMP[elem][같은 번호]`).
   공용 8색(살결·쇠·가죽·검정)은 속성이 없으므로 **안 건드린다.**
2. `--job dirs8` — idle 첫 칸과 attack 여섯 칸을 **여덟 방향 전부** 굽는다.
   본선은 `--dirs-of idle` 이라 attack 이 게임 방향(SE) 하나뿐이다.
"""
import sys, os, math, time, json, argparse, tempfile
from pathlib import Path

import bpy
import numpy as np
from PIL import Image
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "mk"))
sys.path.insert(0, str(HERE.parent))
import spec          # noqa: E402
import rigdef as RD  # noqa: E402
import lineart       # noqa: E402
import render as RN  # noqa: E402  ← mk/render.py. 읽기만 한다.

OUT = spec.OUT / "extras"
ICE = spec.RAMP["ice"]


# ---------------------------------------------------------------- 리컬러
def remap_hex(hx: str, elem: str) -> str:
    """얼음 램프의 칸 번호를 그대로 지켜 다른 속성 램프로 옮긴다.

    ★ 공용 8색은 그대로 둔다 — 살결과 쇠와 가죽은 속성이 아니다.
      (그것까지 갈면 불 요쿨의 **얼굴색**이 바뀐다)
    """
    if hx in ICE:
        return spec.RAMP[elem][ICE.index(hx)]
    return hx


def recolor_materials(elem: str) -> dict:
    """씬 안의 툰 재질 램프 세 칸을 그 속성으로 갈아 끼운다. 돌려주는 것은 표."""
    table = {}
    for name, (sh, mid, li) in RD.MATS.items():
        m = bpy.data.materials.get(name)
        if m is None or not m.use_nodes:
            continue
        ramp = next((n for n in m.node_tree.nodes
                     if n.bl_idname == "ShaderNodeValToRGB"), None)
        if ramp is None:
            continue
        new = [remap_hex(h, elem) for h in (sh, mid, li)]
        els = sorted(ramp.color_ramp.elements, key=lambda e: e.position)
        for el, hx in zip(els, new):
            el.color = spec.hex2linear(hx) + (1.0,)
        table[name] = {"ice": [sh, mid, li], elem: new,
                       "changed": [a != b for a, b in zip((sh, mid, li), new)]}
    return table


# ---------------------------------------------------------------- 한 칸 굽기
class Rig:
    """정렬까지 포함한 한 칸 굽기 — mk/render.main() 의 고리를 그대로 옮겼다."""

    def __init__(self, arm, sc, vl, cam, sh, elev, noline, line_rgb):
        self.arm, self.sc, self.vl, self.cam = arm, sc, vl, cam
        self.sh, self.elev = sh, elev
        self.noline, self.line_rgb = noline, line_rgb
        self.ce = math.cos(math.radians(elev))
        self.fixes = 0

    def shoot(self, out_png, raw_png=None, lines=True):
        arm, vl = self.arm, self.vl
        arm.location = (0.0, 0.0, 0.0)
        vl.update()
        arm.location.z = -RN.min_screen_v(self.elev) / self.ce
        vl.update()
        col = self.sh.color()
        for _ in range(3):                       # 픽셀로 갚는다
            bb = Image.fromarray(col).getbbox()
            if bb is None:
                break
            err = bb[3] - RN.FOOT_BOTTOM
            if err == 0:
                break
            arm.location.z += err / (spec.PX_PER_M * self.ce)
            vl.update()
            col = self.sh.color()
            self.fixes += 1
        for _ in range(8):                       # 가로로 넘치면 밀어 넣는다
            al0 = col[:, :, 3] > 0
            l, r = int(al0[:, 0].sum()), int(al0[:, 95].sum())
            if (not l and not r) or (l and r):
                break
            arm.location.x += (2 if l else -2) / spec.PX_PER_M
            vl.update()
            col = self.sh.color()
            self.fixes += 1
        n_line = 0
        if lines:
            idp = self.sh.idpass()
            col2, n_line = lineart.apply_lines(col, idp[:, :, :3],
                                               self.line_rgb, self.noline)
        else:
            col2 = col
        Path(out_png).parent.mkdir(parents=True, exist_ok=True)
        Image.fromarray(col2).save(out_png)
        if raw_png:
            Path(raw_png).parent.mkdir(parents=True, exist_ok=True)
            Image.fromarray(col).save(raw_png)
        al = col2[:, :, 3] > 0
        bb = Image.fromarray(col2).getbbox()
        return {"bbox": list(bb) if bb else None, "fill": int(al.sum()),
                "line_px": n_line}


def boot(blend, elev, zoom):
    bpy.ops.wm.open_mainfile(filepath=str(Path(blend).resolve()))
    sc, vl = bpy.context.scene, bpy.context.view_layer
    cam, cz = RN.setup_scene(sc, vl, elev, spec.ORTHO_SCALE, spec.CELL[0], 1)
    arm = bpy.data.objects["Rig"]
    arm.scale = (zoom, zoom, zoom)
    idmat = bpy.data.materials["IDDEPTH"]
    noline = {ob.pass_index for ob in RN.meshes() if not ob.get("b3d_line", True)}
    tmp = Path(tempfile.mkdtemp(prefix="b3dx_"))
    shooter = RN.Shooter(sc, vl, idmat, tmp)
    rig = Rig(arm, sc, vl, cam, shooter, elev, noline, spec.hex2rgb(RN.LINE_HEX))
    return sc, vl, arm, cam, shooter, rig


# ---------------------------------------------------------------- job 1
def job_recolor(a):
    """속성 다섯 벌 — 같은 모델 · 램프만 갈아 끼운다."""
    elems = [s.strip() for s in a.elems.split(",") if s.strip()]
    root = OUT / "recolor"
    per = {}
    t_all = time.time()
    sc, vl, arm, cam, shooter, rig = boot(a.blend, a.elev, a.zoom)
    t_boot = time.time() - t_all
    n = spec.ACTIONS["idle"]["frames"]
    arm.animation_data.action = bpy.data.actions["idle"]
    yaw = spec.DIRS[spec.GAME_DIR]
    for elem in elems:
        t0 = time.time()
        table = recolor_materials(elem)
        t_swap = time.time() - t0
        t1 = time.time()
        n0, s0 = shooter.n, shooter.t
        frames = []
        for i in range(n):
            sc.frame_set(i + 1)
            arm.rotation_euler = (0, 0, math.radians(yaw))
            vl.update()
            frames.append(rig.shoot(root / elem / "raw" / ("%04d.png" % (i + 1))))
        per[elem] = {
            "frames": n,
            "wall_sec": round(time.time() - t1, 3),
            "render_sec": round(shooter.t - s0, 3),
            "renders": shooter.n - n0,
            "swap_sec": round(t_swap, 4),
            "sec_per_frame": round((shooter.t - s0) / max(1, shooter.n - n0), 4),
            "ramp": spec.RAMP[elem],
            "mats": table,
            "fill": [f["fill"] for f in frames],
        }
        print("  %-6s %d칸 · %.2f초 (렌더 %.2f · 램프 갈기 %.4f)"
              % (elem, n, per[elem]["wall_sec"], per[elem]["render_sec"], t_swap))
    rep = {"job": "recolor", "unit": a.unit, "dir": spec.GAME_DIR,
           "elems": elems, "frames_each": n,
           "boot_sec": round(t_boot, 2),
           "total_sec": round(time.time() - t_all, 2),
           "total_render_sec": round(shooter.t, 2),
           "renders_total": shooter.n,
           "align_fixes": rig.fixes,
           "per": per}
    (root / "report.json").parent.mkdir(parents=True, exist_ok=True)
    (root / "report.json").write_text(json.dumps(rep, ensure_ascii=False, indent=1))
    print("RECOLOR_JSON " + json.dumps({k: v for k, v in rep.items() if k != "per"}))


# ---------------------------------------------------------------- job 2
def job_dirs8(a):
    """여덟 방향 — idle 첫 칸 + attack 여섯 칸 전부."""
    root = OUT / "dirs8"
    t_all = time.time()
    sc, vl, arm, cam, shooter, rig = boot(a.blend, a.elev, a.zoom)
    sword = arm.pose.bones["sword"]
    y_muz = RD.BLADE_Y0 + RD.MUZ_T * (RD.BLADE_Y1 - RD.BLADE_Y0)
    log = []
    muz_all = {}
    for act, cnt in (("idle", spec.ACTIONS["idle"]["frames"]),
                     ("attack", spec.ACTIONS["attack"]["frames"])):
        arm.animation_data.action = bpy.data.actions[act]
        muz_all[act] = {}
        for dname, yaw in spec.DIRS.items():
            pts = []
            for i in range(cnt):
                sc.frame_set(i + 1)
                arm.rotation_euler = (0, 0, math.radians(yaw))
                vl.update()
                m = rig.shoot(root / act / dname / ("%04d.png" % (i + 1)))
                wp = arm.matrix_world @ (sword.matrix @ Vector((0.0, y_muz, 0.0)))
                v = world_to_camera_view(sc, cam, wp)
                mp = [round(v.x * spec.CELL[0], 2), round((1.0 - v.y) * spec.CELL[1], 2)]
                pts.append(mp)
                m.update({"act": act, "dir": dname, "i": i, "muz": mp})
                log.append(m)
            muz_all[act][dname] = pts
        print("  %s · 8방향 x %d칸" % (act, cnt))
    meta = {
        "unit": a.unit, "elem": a.elem,
        "source": "tools/blender3d/extras (8방향 · mk/render.py 의 장면을 그대로 쓴다)",
        "cell": {"w": spec.CELL[0], "h": spec.CELL[1]},
        "fps": spec.FPS,
        "actions": {k: dict(v) for k, v in spec.ACTIONS.items() if k in ("idle", "attack")},
        "dirs": list(spec.DIRS), "game_dir": spec.GAME_DIR, "family": "slash",
        "camera": {"ortho_scale": spec.ORTHO_SCALE, "px_per_m": spec.PX_PER_M,
                   "elev_deg": a.elev, "foot_bottom": RN.FOOT_BOTTOM},
        "muzzle_origin": "cell_topleft", "muzzle_y_down": True,
        "muzzle_px": {k: v[spec.GAME_DIR] for k, v in muz_all.items()},
        "muzzle_px_dirs": muz_all,
        "frames_log": log,
    }
    root.mkdir(parents=True, exist_ok=True)
    (root / "meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent=1))
    print("DIRS8_JSON " + json.dumps({
        "frames": shooter.n, "render_sec": round(shooter.t, 2),
        "sec_per_frame": round(shooter.t / max(1, shooter.n), 4),
        "total_sec": round(time.time() - t_all, 2),
        "align_fixes": rig.fixes, "out": str(root)}))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--job", required=True, choices=["recolor", "dirs8"])
    ap.add_argument("--blend", default="build/b3d/jokull/2_model/jokull.blend")
    ap.add_argument("--unit", default="jokull")
    ap.add_argument("--elem", default="ice")
    ap.add_argument("--elems", default="fire,elec,ice,water,none")
    ap.add_argument("--elev", type=float, default=spec.ELEV)
    ap.add_argument("--zoom", type=float, default=1.05)
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    a = ap.parse_args(argv)
    {"recolor": job_recolor, "dirs8": job_dirs8}[a.job](a)


if __name__ == "__main__":
    main()
