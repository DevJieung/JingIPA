#!/usr/bin/env python3
"""Quick EEVEE frame sheets of the authored native clips straight from game.blend.

    env -u DISPLAY bl -b --factory-startup --python tools/3d/native_motion_sheet.py -- --id echo
    python3 tools/3d/native_motion_sheet.py --compose --id echo     # contact sheet from the frames

This is an authoring-side preview of the Blender clips (the same data that is
exported into the runtime GLB); the real Godot GL captures remain the review of
record (tools/3d/native_character_review.py).
"""
import argparse, json, math, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FRAMES = {
    'IdleLoop': [0, 60, 120],
    'WalkLoop': [0, 4, 8, 11, 15, 19, 23, 26],
    'Attack': [0, 9, 18, 26, 30, 31, 33, 36, 40, 45],
}
VIEWS = {'IdleLoop': ['three_quarter'], 'WalkLoop': ['three_quarter', 'side'], 'Attack': ['three_quarter', 'front', 'top']}


def compose(cid: str, out: Path) -> None:
    from PIL import Image, ImageDraw, ImageFont
    font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 16)
    rows = []
    for clip, frames in FRAMES.items():
        for view in VIEWS.get(clip, ['three_quarter']):
            paths = [out / f'{clip}_{view}_{f:03d}.png' for f in frames]
            if all(p.exists() for p in paths): rows.append((clip + ' / ' + view, paths))
    if not rows: return
    cell = (300, 360)
    columns = max(len(r[1]) for r in rows)
    sheet = Image.new('RGB', (columns * cell[0], len(rows) * cell[1]), (15, 27, 40))
    draw = ImageDraw.Draw(sheet)
    for r, (label, paths) in enumerate(rows):
        for c, path in enumerate(paths):
            im = Image.open(path).convert('RGB'); im.thumbnail((cell[0] - 10, cell[1] - 40))
            sheet.paste(im, (c * cell[0] + 5, r * cell[1] + 32))
            draw.text((c * cell[0] + 8, r * cell[1] + 8), f'{label} f{path.stem.split("_")[-1]}', font=font, fill=(235, 243, 247))
    sheet.save(out / 'sheet.jpg', quality=88)
    print('MOTION_SHEET', out / 'sheet.jpg')


def main() -> None:
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    p = argparse.ArgumentParser()
    p.add_argument('--id', required=True)
    p.add_argument('--compose', action='store_true')
    p.add_argument('--samples', type=int, default=12)
    p.add_argument('--scale', type=int, default=36)
    a = p.parse_args(argv)
    out = ROOT / 'build/motion-overhaul/blender-sheets' / a.id
    out.mkdir(parents=True, exist_ok=True)
    if a.compose:
        compose(a.id, out); return
    import bpy
    from mathutils import Vector, Matrix
    spec = json.loads((ROOT / 'tools/3d/native_visual_specs.json').read_text())['heroes'][a.id]
    height = float(spec.get('height', 1.65))
    bpy.ops.wm.open_mainfile(filepath=str(ROOT / 'build/character-3d/source' / a.id / 'game.blend'))
    for o in list(bpy.context.scene.objects):
        if o.type in ['LIGHT', 'CAMERA']: bpy.data.objects.remove(o, do_unlink=True)
    s = bpy.context.scene
    rig = next(o for o in s.objects if o.type == 'ARMATURE')
    s.render.engine = 'BLENDER_EEVEE'; s.render.resolution_x = 1000; s.render.resolution_y = 1250
    s.render.resolution_percentage = a.scale; s.eevee.taa_render_samples = a.samples
    s.eevee.use_gtao = True; s.eevee.use_soft_shadows = False
    s.render.image_settings.file_format = 'PNG'; s.view_settings.view_transform = 'AgX'
    s.world.use_nodes = True
    s.world.node_tree.nodes['Background'].inputs['Color'].default_value = (.035, .05, .075, 1)
    s.world.node_tree.nodes['Background'].inputs['Strength'].default_value = .45
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -.003)); floor = bpy.context.object
    mat = bpy.data.materials.new('ReviewGround'); mat.use_nodes = True
    mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (.06, .08, .10, 1)
    floor.data.materials.append(mat)
    for name, pos, power, color, size in [('Key', (-2.5, 3.5, 4), 240, (1, .9, .8), 3), ('Fill', (3, 2, 2.5), 110, (.75, .86, 1), 3), ('Rim', (1, -3, 3), 200, (.84, .91, 1), 2.4)]:
        d = bpy.data.lights.new(name, 'AREA'); d.energy = power; d.color = color; d.size = size
        o = bpy.data.objects.new(name, d); s.collection.objects.link(o); o.location = pos
        o.rotation_euler = (Vector((0, 0, .92)) - o.location).to_track_quat('-Z', 'Y').to_euler()
    d = bpy.data.cameras.new('Cam'); camera = bpy.data.objects.new('Cam', d)
    s.collection.objects.link(camera); s.camera = camera; d.type = 'ORTHO'; d.ortho_scale = height * 1.75
    views = {'three_quarter': (2.4, 4.5, 1.85), 'side': (4.5, 0.0, 1.05), 'front': (0.0, 4.5, 1.05), 'top': (0.0, 0.02, 6.0)}
    for clip, frames in FRAMES.items():
        action = bpy.data.actions.get(clip)
        if action is None: continue
        rig.animation_data.action = action
        for view in VIEWS.get(clip, ['three_quarter']):
            camera.location = views[view]
            camera.rotation_euler = (Vector((0, 0, height * .5)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
            if view == 'top': camera.rotation_euler = (0.0, 0.0, 0.0)
            for f in frames:
                s.frame_set(f)
                s.render.filepath = str(out / f'{clip}_{view}_{f:03d}.png')
                bpy.ops.render.render(write_still=True)
    rig.animation_data.action = None
    print('MOTION_FRAMES', out)


main()
