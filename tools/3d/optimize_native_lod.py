#!/usr/bin/env python3
"""Mobile budget pass for the native characters: fewer triangles, one clean albedo atlas.

Driver (system python, one Blender process per model, in parallel):
    python3 tools/3d/optimize_native_lod.py --all --jobs 7 --candidates
    python3 tools/3d/optimize_native_lod.py --ids brasa,echo --candidates
then tools/3d/publish_native_lod.py installs the candidates and records them.
Inside Blender (what the driver spawns):
    bl -b --factory-startup --python tools/3d/optimize_native_lod.py -- --id brasa [--candidate out.glb]

Measured facts that shaped it (2026-10-15):
  * the reviewed 55k game surfaces carry the reconstruction's atlas: 3,975-5,359 UV islands,
    30 % of all edges on a seam and ~1,500 pinched vertices from welding the charts, so a
    UV-keeping collapse cannot reach 6k (Blender stalls at 10.2k for Brasa)
  * they are not one sheet: 94-99 % of faces have a twin within 1 % of the height, and a
    DropSlime cross-section shows the visible sheet, a ~1.7 cm wall and a doubled inner
    cavity sheet whose texture was never seen by the generator (dark noise). Decimating all
    sheets spends half the budget on surfaces nobody sees, and bake rays that reach the
    inner sheet paint dark blotches (Frost imp)
  * an outer voxel hull (lod_reduce_vtk.py --pitch) would be one clean sheet, but real
    openings connect cavities to the outside (Frost imp's eye holes), so it is not used

Steps per model:
  1. open the reviewed editable source (hero game.blend, monster game.blend, Limne's
     limne_game.blend); its mesh, skin weights, rig and clips are the shipped ones
  2. keep two bake copies: the visible faces and every sheet as it is
  3. delete the faces that cannot be seen from outside (fewer than 3 of 128 directions leave
     the model unobstructed); the inner wall seen through a real opening stays
  4. tools/3d/lod_reduce_vtk.py (TRELLIS venv): VTK quadric decimation of what is left to
     the budget, skin weights interpolated along every collapse, then an xatlas atlas
     (Limne: eyes, lashes and lip are reduced on their own and join the same atlas)
  5. Cycles EMIT bake of the exact source colour (image texel, vertex colour decoded the
     way the GL Compatibility renderer shows it, or flat material colour; no lighting,
     metallic or roughness), selected-to-active with a cage from the measured deviation;
     visible faces first, all sheets as fallback
  6. nearest-texel fill of ray misses and of the whole gutter (mip levels never pull in a
     neighbouring island), then box downsample to the shipped size
  7. export, then graft the reviewed high-poly runtime GLB's animation bytes onto the new
     geometry (tools/3d/glb_animation_merge.py), so clips, rig, sockets and release timing
     stay byte-identical; only meshes, material image and vertex data change

Nothing overwrites the reviewed source: the low-poly editable result is saved next to it as
game-lod.blend (Limne: build/limne-game-motion/limne_game-lod.blend). The high-poly runtime
GLBs are kept in build/character-3d/highpoly-2026-10-15/. Re-finishing a model from its raw
reconstruction (finish_native_character.py / finish_native_monster.py) brings back a 55k
runtime GLB: run this pass and publish_native_lod.py again afterwards.

--retexture (2026-10-18 casual overhaul, WP-A "painted skins"): opens game-lod.blend instead
of game.blend, appends the game.blend surfaces only as bake sources, re-runs steps 2-3 and the
two EMIT passes on the shipped geometry (no reduce, no rebuild: positions, UVs, weights, rig,
sockets and height stay byte-identical), then bakes an AO pass (reduced mesh alone, ray length
0.25 H, monsters 0.30 H, 64 spp) and a height pass (clamp(z / H)) and grades the atlas inside
the chart mask with tools/3d/grade_native_albedo.py (de-speckle, chart-flatten, light
posterise, levels, OKLab chroma, painted light, cool shade, edge light, face paint-back). The
clip bytes are grafted from the *shipped* art/models GLB (never the high-poly backup), the
report records before/after atlas statistics and a geometry fingerprint, and --work points
every output at a new work dir:
    python3 tools/3d/optimize_native_lod.py --ids carmen,isa,brasa --candidates --retexture \
        --work build/character-3d/lod-2026-10-18
"""
import argparse, json, math, os, re, sys, hashlib, subprocess, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HEROES = ROOT / 'art/models/native_heroes.json'
MONSTERS = ROOT / 'art/models/native_monsters.json'
WORK = ROOT / 'build/character-3d/lod-2026-10-15'
TRELLIS_PY = Path.home() / '.local/opt/trellis/venv/bin/python'
REDUCE = Path(__file__).resolve().parent / 'lod_reduce_vtk.py'

# Budgets: whole runtime model triangles / shipped albedo size. The 2026-10-15 request set
# upper limits (hero 8k, Limne 10k with <= 4 surfaces, monster 4k, slime ~2k, boss 10k);
# the targets sit below them. Monster kind comes from core/roster.gd.
HERO_TRIANGLES = 6000
LIMNE_TRIANGLES = 9400
BOSS_TRIANGLES = 9000
MONSTER_TRIANGLES = {'swarm': 3000, 'fast': 3600, 'caster': 3600, 'tank': 3800}
SLIME_TRIANGLES = 2000


def monster_kind(cid: str) -> str:
    roster = (ROOT / 'core/roster.gd').read_text()
    match = re.search(r'"id": "%s"[^}]*"kind": "([a-z]+)"' % cid, roster)
    return match.group(1) if match else 'tank'


def budget(kind: str, cid: str, height: float) -> dict:
    """Triangles, bake/shipped texture size and the outer-hull voxel pitch (m)."""
    if kind == 'limne':
        return {'triangles': LIMNE_TRIANGLES, 'bake': 1024, 'texture': 512, 'pitch': 0.0}
    if kind == 'hero':
        return {'triangles': HERO_TRIANGLES, 'bake': 1024, 'texture': 512, 'pitch': 0.0}
    mkind = monster_kind(cid)
    pitch = 0.0
    if mkind == 'boss':
        return {'triangles': BOSS_TRIANGLES, 'bake': 1024, 'texture': 512, 'monster_kind': mkind, 'pitch': pitch}
    if cid == 'drop_slime':
        return {'triangles': SLIME_TRIANGLES, 'bake': 512, 'texture': 256, 'monster_kind': mkind, 'pitch': pitch}
    size = 512 if mkind in ('tank', 'caster') else 256
    return {'triangles': MONSTER_TRIANGLES.get(mkind, 3600), 'bake': size * 2, 'texture': size, 'monster_kind': mkind, 'pitch': pitch}


def locate(cid: str) -> dict:
    if cid == 'limne':
        return {'kind': 'limne', 'blend': ROOT / 'build/limne-game-motion/limne_game.blend',
                'glb': ROOT / 'art/models/limne/limne.glb', 'out_dir': ROOT / 'art/models/limne',
                'lod_blend': ROOT / 'build/limne-game-motion/limne_game-lod.blend', 'height': 1.62}
    heroes = json.loads(HEROES.read_text())['heroes']
    if cid in heroes:
        return {'kind': 'hero', 'blend': ROOT / 'build/character-3d/source' / cid / 'game.blend',
                'glb': ROOT / 'art/models' / cid / f'{cid}.glb', 'out_dir': ROOT / 'art/models' / cid,
                'lod_blend': ROOT / 'build/character-3d/source' / cid / 'game-lod.blend',
                'height': float(heroes[cid].get('height', 1.65))}
    monsters = json.loads(MONSTERS.read_text())['monsters']
    if cid in monsters:
        return {'kind': 'monster', 'blend': ROOT / 'build/character-3d/monster-source' / cid / 'game.blend',
                'glb': ROOT / 'art/models/monsters' / cid / f'{cid}.glb', 'out_dir': ROOT / 'art/models/monsters' / cid,
                'lod_blend': ROOT / 'build/character-3d/monster-source' / cid / 'game-lod.blend',
                'height': float(monsters[cid].get('height', 1.0))}
    raise SystemExit('unknown id ' + cid)


# ----------------------------------------------------------------------------
# Driver mode
# ----------------------------------------------------------------------------
def _driver() -> None:
    import concurrent.futures
    p = argparse.ArgumentParser()
    p.add_argument('--ids', default='')
    p.add_argument('--all', action='store_true')
    p.add_argument('--jobs', type=int, default=4)
    p.add_argument('--blender', default=str(Path.home() / '.local/bin/bl'))
    p.add_argument('--candidates', action='store_true', help='write build/.../candidates/<id>.glb, not the runtime GLB')
    p.add_argument('--work', default=str(WORK), help='work dir for candidates, logs and per-model reports')
    p.add_argument('--retexture', action='store_true', help='re-bake and grade the albedo on the shipped geometry (game-lod.blend)')
    a = p.parse_args()
    work = Path(a.work).resolve()
    ids = [i for i in a.ids.split(',') if i]
    if a.all:
        ids = list(json.loads(HEROES.read_text())['ready_ids']) + ['limne'] + list(json.loads(MONSTERS.read_text())['ready_ids'])
    if not ids:
        raise SystemExit('give --ids a,b or --all')
    env = dict(os.environ)
    env.pop('DISPLAY', None)
    logs = work / 'logs'
    logs.mkdir(parents=True, exist_ok=True)

    def run(cid: str):
        cmd = [a.blender, '-b', '--factory-startup', '--python', str(Path(__file__).resolve()), '--', '--id', cid, '--work', str(work)]
        if a.retexture: cmd.append('--retexture')
        if a.candidates: cmd += ['--candidate', str(work / 'candidates' / f'{cid}.glb')]
        started = time.time()
        result = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=3600)
        log = result.stdout + '\n' + result.stderr
        (logs / f'{cid}.log').write_text(log)
        ok = result.returncode == 0 and 'NATIVE_LOD ' in log and 'Traceback' not in log
        line = next((l for l in log.splitlines() if l.startswith('NATIVE_LOD ')), '')
        return cid, ok, line, time.time() - started

    failures = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, a.jobs)) as pool:
        for cid, ok, line, seconds in pool.map(run, ids):
            print(('ok   ' if ok else 'FAIL ') + f'{cid} {seconds:5.0f}s ' + line[:300], flush=True)
            if not ok: failures.append(cid)
    if failures:
        raise SystemExit('failed: ' + ','.join(failures))


try:
    import bpy  # noqa: F401
    IN_BLENDER = True
except ImportError:
    IN_BLENDER = False

if not IN_BLENDER:
    _driver()
    sys.exit(0)

# ----------------------------------------------------------------------------
# Blender mode
# ----------------------------------------------------------------------------
import bmesh
import numpy as np
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
from scipy import ndimage
from PIL import Image as PILImage, ImageDraw
sys.path.insert(0, str(Path(__file__).resolve().parent))
from glb_animation_merge import merge_animations, _read_glb, _write_glb  # noqa: E402
import grade_native_albedo as grading  # noqa: E402

argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
ap = argparse.ArgumentParser()
ap.add_argument('--id', required=True)
ap.add_argument('--triangles', type=int, default=0)
ap.add_argument('--bake', type=int, default=0)
ap.add_argument('--texture', type=int, default=0)
ap.add_argument('--pitch', type=float, default=-1, help='outer hull voxel size; 0 decimates the source sheets as they are')
ap.add_argument('--candidate', default='', help='write the GLB here instead of the runtime path')
ap.add_argument('--work', default='', help='work dir (default build/character-3d/lod-2026-10-15)')
ap.add_argument('--retexture', action='store_true', help='re-bake + grade the albedo on the shipped geometry')
args = ap.parse_args(argv)
if args.work: WORK = Path(args.work).resolve()
RETEXTURE = bool(args.retexture)
CID = args.id
INFO = locate(CID)
B = budget(INFO['kind'], CID, INFO['height'])
if args.triangles: B['triangles'] = args.triangles
if args.bake: B['bake'] = args.bake
if args.texture: B['texture'] = args.texture
if args.pitch >= 0: B['pitch'] = args.pitch
H = INFO['height']
OUT = WORK / CID
OUT.mkdir(parents=True, exist_ok=True)
# Limne's small facial parts are reduced on their own and keep their own atlas islands.
LIMNE_DETAIL = ('Eye_warm_sclera', 'Eye_deep_pupil', 'Eye_upper_lash', 'Lip_soft_warm')


def tri_count(ob) -> int:
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def select_only(objects, active):
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects: ob.select_set(True)
    bpy.context.view_layer.objects.active = active


def base_color_source(mat):
    """(node socket feeding Base Color or None, constant RGBA) of a Principled material."""
    if mat is None or not mat.use_nodes:
        return None, (0.8, 0.8, 0.8, 1.0)
    shader = next((n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
    if shader is None:
        return None, (0.8, 0.8, 0.8, 1.0)
    socket = shader.inputs['Base Color']
    if socket.links:
        return socket.links[0].from_socket, tuple(socket.default_value)
    return None, tuple(socket.default_value)


def textured(mat) -> bool:
    if mat is None or not mat.use_nodes: return False
    link, _ = base_color_source(mat)
    return link is not None and getattr(link.node, 'image', None) is not None


def srgb_to_linear(nt, socket):
    """Node chain decoding an sRGB-encoded colour socket (exact piecewise curve)."""
    sep = nt.nodes.new('ShaderNodeSeparateColor')
    nt.links.new(socket, sep.inputs['Color'])
    comb = nt.nodes.new('ShaderNodeCombineColor')
    for i in range(3):
        def math(op, a, b=None, c=None):
            n = nt.nodes.new('ShaderNodeMath'); n.operation = op
            for k, v in enumerate((a, b, c)):
                if v is None: continue
                if isinstance(v, float): n.inputs[k].default_value = v
                else: nt.links.new(v, n.inputs[k])
            return n.outputs[0]
        c = sep.outputs[i]
        high = math('POWER', math('MULTIPLY_ADD', c, 1 / 1.055, 0.055 / 1.055), 2.4)
        low = math('MULTIPLY', c, 1 / 12.92)
        is_low = math('LESS_THAN', c, 0.04045)
        mixed = math('MULTIPLY_ADD', math('SUBTRACT', low, high), is_low, high)
        nt.links.new(mixed, comb.inputs[i])
    return comb.outputs['Color']


def emission_copy(mat, name):
    """Copy of `mat` whose surface emits exactly its base colour (bake source)."""
    new = mat.copy() if mat is not None else bpy.data.materials.new(name)
    new.name = name
    new.use_nodes = True
    nt = new.node_tree
    out = next((n for n in nt.nodes if n.type == 'OUTPUT_MATERIAL'), None) or nt.nodes.new('ShaderNodeOutputMaterial')
    for n in nt.nodes:
        if n.type == 'OUTPUT_MATERIAL': n.is_active_output = n == out
    emit = nt.nodes.new('ShaderNodeEmission')
    emit.inputs['Strength'].default_value = 1.0
    link, value = base_color_source(new)
    if link is not None and link.node.type in ('VERTEX_COLOR', 'ATTRIBUTE'):
        # Godot's GL Compatibility renderer shows COLOR_0 as sRGB-space values (measured
        # 2026-10-15: a vertex colour of 0.667 renders 0.667, an albedo of linear 0.667
        # renders 0.836, with or without vertex_color_is_srgb). Limne's skin therefore
        # reads darker in game than Blender's linear attribute; bake what the game shows.
        nt.links.new(srgb_to_linear(nt, link), emit.inputs['Color'])
    elif link is not None:
        nt.links.new(link, emit.inputs['Color'])
    else:
        emit.inputs['Color'].default_value = (value[0], value[1], value[2], 1.0)
    for l in list(out.inputs['Surface'].links): nt.links.remove(l)
    nt.links.new(emit.outputs['Emission'], out.inputs['Surface'])
    return new


def decimate_blender(ob, ratio):
    select_only([ob], ob)
    mod = ob.modifiers.new('MobileLOD', 'DECIMATE'); mod.ratio = ratio; mod.use_collapse_triangulate = True
    while ob.modifiers.find('MobileLOD') > 0: bpy.ops.object.modifier_move_up(modifier='MobileLOD')
    bpy.ops.object.modifier_apply(modifier='MobileLOD')


def mesh_arrays(ob):
    """Welded positions, triangles, skin weight matrix and per-slot area membership."""
    me = ob.data
    me.calc_loop_triangles()
    n = len(me.vertices)
    v = np.zeros(n * 3, np.float32); me.vertices.foreach_get('co', v); v = v.reshape(-1, 3)
    t = np.zeros(len(me.loop_triangles) * 3, np.int32); me.loop_triangles.foreach_get('vertices', t); t = t.reshape(-1, 3)
    mi = np.zeros(len(me.loop_triangles), np.int32); me.loop_triangles.foreach_get('material_index', mi)
    skin = np.zeros((n, max(1, len(ob.vertex_groups))), np.float32)
    for vert in me.vertices:
        for g in vert.groups: skin[vert.index, g.group] = g.weight
    slots = max(1, len(me.materials))
    area = np.linalg.norm(np.cross(v[t[:, 1]] - v[t[:, 0]], v[t[:, 2]] - v[t[:, 0]]), axis=1) * 0.5
    member = np.zeros((n, slots), np.float32)
    for k in range(3): np.add.at(member, (t[:, k], mi), area)
    member /= np.maximum(member.sum(axis=1, keepdims=True), 1e-12)
    return v, t, skin, member


def sole_metrics(ob, legs):
    """Lowest point and leg-weighted sole band extents (game coords: y up, z back)."""
    me = ob.data
    idx = {g.index for g in ob.vertex_groups if g.name in legs}
    zs = [v.co.z for v in me.vertices]
    floor = min(zs)
    band = [v for v in me.vertices if v.co.z <= floor + 0.012 * H and any(g.group in idx and g.weight > 0.5 for g in v.groups)]
    ys = [v.co.y for v in band]            # Blender y = -game z
    return {'floor': floor, 'band_vertices': len(band), 'front': min(ys) if ys else 0.0, 'back': max(ys) if ys else 0.0}


# ---------------------------------------------------------------------------- open
bpy.ops.wm.open_mainfile(filepath=str(INFO['lod_blend'] if RETEXTURE else INFO['blend']))
scene = bpy.context.scene
rig = next(o for o in scene.objects if o.type == 'ARMATURE')
rig.data.pose_position = 'REST'
meshes = [o for o in scene.objects if o.type == 'MESH']
before = {'triangles': sum(tri_count(o) for o in meshes), 'meshes': len(meshes),
          'vertices': sum(len(o.data.vertices) for o in meshes)}
# The reviewed high-poly runtime GLB (preserved before this pass) is the reference for the
# triangle check and the donor of the clip bytes; once a model was reduced, the file in
# art/models is the low-poly one.
BACKUP = ROOT / 'build/character-3d/highpoly-2026-10-15/art-models'
reference = BACKUP / INFO['glb'].relative_to(ROOT / 'art/models')
if RETEXTURE:
    # Retexture: the shipped GLB is both the triangle reference and the clip donor; the
    # 2026-10-15 high-poly backup would silently revert any clip authored since.
    runtime_payload = INFO['glb'].read_bytes()
else:
    runtime_payload = (reference if reference.exists() else INFO['glb']).read_bytes()
runtime_gltf, _ = _read_glb(runtime_payload)
runtime_tris = sum(runtime_gltf['accessors'][p['indices']]['count'] // 3
                   for m in runtime_gltf['meshes'] for p in m['primitives'])
if abs(runtime_tris - before['triangles']) > max(40, before['triangles'] * 0.002):
    raise SystemExit(f'editable source {before["triangles"]} tris does not match runtime GLB {runtime_tris}')

# ---------------------------------------------------------------------------- classify
if RETEXTURE:
    # The opened file is the reduced, atlased, skinned result; its textured surface is the
    # bake target and stays untouched. The reviewed game.blend surfaces are appended only as
    # bake sources (their 55k sheets carry the source colour) and removed again afterwards.
    lod_textured = [o for o in meshes if any(textured(m) for m in o.data.materials)]
    if len(lod_textured) != 1:
        raise SystemExit(f'{CID}: expected one atlased surface in {INFO["lod_blend"]}, found {len(lod_textured)}')
    target = lod_textured[0]
    lod_accents = [o for o in meshes if o is not target]
    with bpy.data.libraries.load(str(INFO['blend']), link=False) as (data_from, data_to):
        data_to.objects = list(data_from.objects)
    appended = [o for o in data_to.objects if o is not None]
    for o in appended:
        if o.type != 'MESH': continue
        scene.collection.objects.link(o)
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
        for mod in list(o.modifiers):
            if mod.type == 'ARMATURE': o.modifiers.remove(mod)
    bpy.context.view_layer.update()
    meshes = [o for o in appended if o.type == 'MESH']
    if not meshes:
        raise SystemExit(f'{CID}: no mesh objects in {INFO["blend"]}')
if INFO['kind'] == 'limne':
    irises = [o for o in meshes if any(m and m.name == 'Eye_brown_radial_iris' for m in o.data.materials)]
    detail = [o for o in meshes if o not in irises and any(m and m.name in LIMNE_DETAIL for m in o.data.materials)]
    body = [o for o in meshes if o not in irises and o not in detail]
    accents = irises
else:
    body = [o for o in meshes if any(textured(m) for m in o.data.materials)]
    detail = []
    accents = [o for o in meshes if o not in body]
if len(body) == 0:
    raise SystemExit('no textured surface in ' + CID)
legs = {'SkinLegL', 'SkinLegR', 'LegL', 'LegR', 'RearL', 'RearR', 'FrontL', 'FrontR', 'Base', 'RootL', 'RootR'}
sole_before = sole_metrics(max(body, key=tri_count), legs)

# Untouched bake sources (object + mesh copies, original UVs and materials, no skin).
def bake_copies(tag):
    copies = []
    for ob in body + detail:
        src = ob.copy(); src.data = ob.data.copy(); src.name = f'LOD{tag}_' + ob.name
        scene.collection.objects.link(src)
        for mod in list(src.modifiers):
            if mod.type == 'ARMATURE': src.modifiers.remove(mod)
        src.parent = None
        src.matrix_world = ob.matrix_world.copy()
        copies.append(src)
    for src in copies:
        for i, mat in enumerate(src.data.materials):
            src.data.materials[i] = emission_copy(mat, f'LODEmit_{tag}_{i}_{mat.name if mat else "none"}')
    return copies


# Two bake sources: the faces visible from outside (first choice), and every sheet as it
# is (fallback for surfaces only seen through a real opening, e.g. Frost imp's eye holes,
# which keep the original dark interior instead of an arbitrary neighbouring colour).
sources = bake_copies('Source')
sources_full = bake_copies('Full')


def fibonacci(count):
    out = []
    for i in range(count):
        y = 1 - 2 * (i + 0.5) / count; r = math.sqrt(max(0.0, 1 - y * y)); phi = i * math.pi * (3 - math.sqrt(5))
        out.append(Vector((math.cos(phi) * r, math.sin(phi) * r, y)))
    return out


def occluder_tree(objects):
    occl = bmesh.new()
    for o in objects:
        tmp = o.data.copy(); tmp.transform(o.matrix_world); occl.from_mesh(tmp); bpy.data.meshes.remove(tmp)
    bmesh.ops.triangulate(occl, faces=occl.faces[:])
    tree = BVHTree.FromBMesh(occl)
    occl.free()
    return tree


def visible_faces(ob, tree, count=128, need=3):
    """Faces that can be seen from outside through a real opening, not a pinhole.

    The TRELLIS surfaces are not one sheet: 94-99 % of faces have a twin within 1 % of the
    height (Brasa, Frost imp, DropSlime) and DropSlime's cross-section shows the outer
    sheet, a ~1.7 cm wall and a doubled inner cavity sheet whose texture was never seen
    by the texture generator (dark, noisy). A face counts as visible when at least `need`
    of `count` directions (randomly turned per face) leave the whole model unobstructed
    from its centre or from one of three points towards its corners. Faces seen only
    through sub-millimetre cracks between sheets (1-2 directions) count as hidden; the
    inner wall seen through Frost imp's eye holes (a ~25 degree cone) stays visible."""
    import random
    dirs = fibonacci(count)
    rng = random.Random(20261015)
    eps = H * 2e-4
    me = ob.data
    mask = np.zeros(len(me.polygons), bool)
    mw = ob.matrix_world
    nmat = mw.to_3x3().inverted().transposed()
    for poly in me.polygons:
        c = mw @ poly.center
        n = (nmat @ poly.normal).normalized()
        corners = [mw @ me.vertices[i].co for i in poly.vertices]
        points = [c] + [c.lerp(q, 0.55) for q in corners[:3]]
        turn = Matrix.Rotation(rng.random() * math.tau, 3,
                               Vector((rng.random() - .5, rng.random() - .5, rng.random() - .5 + 1e-3)).normalized())
        escapes = 0
        for d0 in dirs:
            d = turn @ d0
            side = eps if d.dot(n) >= 0 else -eps
            if any(tree.ray_cast(q + n * side, d)[0] is None for q in points):
                escapes += 1
                if escapes >= need: break
        mask[poly.index] = escapes >= need
    return mask


def delete_faces(ob, hidden_mask):
    bm = bmesh.new(); bm.from_mesh(ob.data); bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[bm.faces[i] for i in np.nonzero(hidden_mask)[0]], context='FACES')
    bm.to_mesh(ob.data); bm.free()


# The cage is sized from the distance to *all* source sheets; the reduced surface and the
# first bake source keep only what the camera can see (the same faces, by index, since the
# copies mirror the skinned objects).
depsgraph = bpy.context.evaluated_depsgraph_get()
full_bvhs = [BVHTree.FromObject(s, depsgraph) for s in sources_full]
tree = occluder_tree(sources_full + accents)
hidden_info = {'removed_faces': 0, 'kept_faces': 0}
for ob, src in zip(body, sources[:len(body)]):
    seen = visible_faces(ob, tree)
    hidden_info['removed_faces'] += int((~seen).sum()); hidden_info['kept_faces'] += int(seen.sum())
    delete_faces(ob, ~seen)
    delete_faces(src, ~seen)

if RETEXTURE:
    # Sources are built; drop the appended originals (meshes, their armature and empties).
    for o in appended:
        try:
            bpy.data.objects.remove(o, do_unlink=True)
        except ReferenceError:
            pass
    # The appended armature brought copies of the clips (Attack.001 ...): purge every orphan so
    # nothing but the lod blend's own rig, actions and NLA tracks can reach the export.
    bpy.data.orphans_purge(do_recursive=True)
    body = [target]
    detail = []
    accents = lod_accents
else:
    # Limne: facial detail is reduced per part (they are clean small meshes), the body by VTK.
    for ob in detail:
        if tri_count(ob) > 120: decimate_blender(ob, 0.32)
    if len(body) > 1:
        keep = max(body, key=tri_count)
        select_only(body, keep)
        bpy.ops.object.join()
        body = [keep]
    target = body[0]
slot_materials = [m for m in target.data.materials]
atlas_mat = next((m for m in slot_materials if textured(m)), None)

# ---------------------------------------------------------------------------- reduce + atlas
if RETEXTURE:
    # Geometry, UVs and skin weights are the shipped ones; the chart count comes from the mask.
    atlas_info = {'charts': 0, 'utilization': None, 'skipped_faces': 0, 'reduce': 'retexture: geometry/UV/weights reused'}
else:
    for ob in accents:
        t = tri_count(ob)
        if INFO['kind'] == 'limne' and t > 200: decimate_blender(ob, 0.35)
        elif INFO['kind'] != 'limne' and t > 260: decimate_blender(ob, max(0.25, 220 / t))
    locked_tris = sum(tri_count(o) for o in accents + detail)
    goal = max(500, B['triangles'] - locked_tris)
    bm = bmesh.new(); bm.from_mesh(target.data)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=H * 1e-6)
    bm.to_mesh(target.data); bm.free()
    v, t, skin, member = mesh_arrays(target)
    lock = {'lock_v': np.zeros((0, 3), np.float32), 'lock_f': np.zeros((0, 3), np.int32),
            'lock_skin': np.zeros((0, skin.shape[1]), np.float32), 'lock_extra': np.zeros((0, member.shape[1]), np.float32)}
    if detail:
        names = [g.name for g in target.vertex_groups]
        to_target = target.matrix_world.inverted()
        vs, fs, ss = [], [], []
        count = 0
        for ob in detail:
            dv, dt, dskin, _ = mesh_arrays(ob)
            m = to_target @ ob.matrix_world
            dv = np.array([(m @ Vector(p.tolist()))[:] for p in dv], np.float32)
            mapped = np.zeros((len(dv), len(names)), np.float32)
            for gi, g in enumerate(ob.vertex_groups):
                if g.name in names: mapped[:, names.index(g.name)] = dskin[:, gi]
            vs.append(dv); fs.append(dt + count); ss.append(mapped); count += len(dv)
        lock = {'lock_v': np.concatenate(vs), 'lock_f': np.concatenate(fs), 'lock_skin': np.concatenate(ss),
                'lock_extra': np.zeros((count, member.shape[1]), np.float32)}
        for ob in detail: bpy.data.objects.remove(ob, do_unlink=True)
    np.savez(OUT / 'reduce-in.npz', v=v, f=t, skin=skin, extra=member, **lock)
    proc = subprocess.run([str(TRELLIS_PY), str(REDUCE), str(OUT / 'reduce-in.npz'), str(OUT / 'reduce-out.npz'),
                           '--triangles', str(goal), '--resolution', str(B['bake']), '--padding', str(max(4, B['bake'] // 128)),
                           '--pitch', str(B['pitch'])],
                          capture_output=True, text=True)
    if proc.returncode or 'LOD_REDUCE' not in proc.stdout:
        raise SystemExit('reduce failed:\n' + proc.stdout + proc.stderr)
    R = np.load(OUT / 'reduce-out.npz')
    rv, rf, rskin, rmember, ruv = R['v'], R['f'], R['skin'], R['extra'], R['corner_uv']

    # Rebuild the skinned body in place: object, name, parent, vertex group names, armature
    # modifier and material slots stay; geometry, weights and UVs are the reduced ones.
    bm = bmesh.new()
    deform = bm.verts.layers.deform.verify()
    uvl = bm.loops.layers.uv.new('UVMap')
    for co, w in zip(rv, rskin):
        vert = bm.verts.new(Vector(co.tolist()))
        for gi in np.nonzero(w > 1e-4)[0]: vert[deform][int(gi)] = float(w[gi])
    bm.verts.ensure_lookup_table()
    face_slot = rmember[rf].mean(axis=1).argmax(axis=1) if rmember.shape[1] > 1 else np.zeros(len(rf), np.int64)
    skipped = 0
    for k, (a, b, c) in enumerate(rf):
        try:
            face = bm.faces.new((bm.verts[int(a)], bm.verts[int(b)], bm.verts[int(c)]))
        except ValueError:
            skipped += 1
            continue
        face.smooth = True
        face.material_index = int(face_slot[k])
        for corner, loop in enumerate(face.loops): loop[uvl].uv = (float(ruv[k, corner, 0]), float(ruv[k, corner, 1]))
    # Consistent winding per connected part (UVs travel with the loops). The collapse can turn
    # a few faces over; their averaged vertex normals would otherwise shade dark seams.
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(target.data); bm.free()
    target.data.update()
    for attr in list(target.data.color_attributes): target.data.color_attributes.remove(attr)
    atlas_info = {'charts': int(R['charts']), 'utilization': float(R['utilization']), 'skipped_faces': skipped, 'reduce': str(R['stats'][0])}

    if INFO['kind'] == 'limne':
        # One atlas material for the whole joined body (facial parts included by the reduce stage).
        for i in range(len(target.data.materials)): target.data.materials[i] = atlas_mat
        for poly in target.data.polygons: poly.material_index = 0
        while len(target.data.materials) > 1: target.data.materials.pop(index=len(target.data.materials) - 1)
        slot_materials = [atlas_mat]

# ---------------------------------------------------------------------------- cage from the measured deviation
def nearest_any(co):
    best = None
    for tree in full_bvhs:
        hit = tree.find_nearest(co)
        if hit[0] is not None and (best is None or hit[3] < best[3]): best = hit
    return best
step = max(1, len(target.data.vertices) // 6000)
dist = np.array([nearest_any(target.data.vertices[i].co)[3] for i in range(0, len(target.data.vertices), step)])
dev = {'p50': float(np.percentile(dist, 50)), 'p99': float(np.percentile(dist, 99)), 'max': float(dist.max())}
extrusion = float(min(max(dev['p99'] * 1.5, H * 0.006), H * 0.03))
max_ray = extrusion * 2.6

# ---------------------------------------------------------------------------- bake
size = B['bake']
image = bpy.data.images.new(f'{CID}_lod_bake', size, size, alpha=True, float_buffer=False)
image.generated_color = (0, 0, 0, 0)
image.colorspace_settings.name = 'sRGB'
bake_mat = bpy.data.materials.new('LODBakeTarget'); bake_mat.use_nodes = True
node = bake_mat.node_tree.nodes.new('ShaderNodeTexImage'); node.image = image
bake_mat.node_tree.nodes.active = node; node.select = True
if RETEXTURE:
    # Surface = emission of clamp(z / H): the height pass bakes this chain (EMIT, target alone).
    bnt = bake_mat.node_tree
    bout = next((n for n in bnt.nodes if n.type == 'OUTPUT_MATERIAL'), None) or bnt.nodes.new('ShaderNodeOutputMaterial')
    geo = bnt.nodes.new('ShaderNodeNewGeometry'); sep = bnt.nodes.new('ShaderNodeSeparateXYZ')
    bnt.links.new(geo.outputs['Position'], sep.inputs['Vector'])
    div = bnt.nodes.new('ShaderNodeMath'); div.operation = 'DIVIDE'; div.use_clamp = True
    div.inputs[1].default_value = float(H)
    bnt.links.new(sep.outputs['Z'], div.inputs[0])
    hemit = bnt.nodes.new('ShaderNodeEmission'); hemit.inputs['Strength'].default_value = 1.0
    bnt.links.new(div.outputs[0], hemit.inputs['Color'])
    for l in list(bout.inputs['Surface'].links): bnt.links.remove(l)
    bnt.links.new(hemit.outputs['Emission'], bout.inputs['Surface'])
for i in range(len(target.data.materials)): target.data.materials[i] = bake_mat
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 4
scene.cycles.use_denoising = False
passes = []
for group in (sources, sources_full):
    image.pixels.foreach_set(np.zeros(size * size * 4, np.float32))
    select_only(group + [target], target)
    bpy.ops.object.bake(type='EMIT', use_selected_to_active=True, cage_extrusion=extrusion,
                        max_ray_distance=max_ray, margin=0, use_clear=False, target='IMAGE_TEXTURES')
    passes.append(np.array(image.pixels[:], dtype=np.float32).reshape(size, size, 4))
visible_hit = passes[0][..., 3] > 0.5
pixels = np.where(visible_hit[..., None], passes[0], passes[1])
# Diagnostic map (not shipped): green = visible surface, blue = interior fallback, red = no hit.
classes = np.zeros((size, size, 3), np.uint8)
classes[visible_hit] = (40, 200, 60)
classes[~visible_hit & (passes[1][..., 3] > 0.5)] = (40, 80, 230)
PILImage.fromarray(classes[::-1]).save(OUT / f'classes_{size}.png')

# ---------------------------------------------------------------------------- fill + downsample
coverage = PILImage.new('L', (size, size), 0)
draw = ImageDraw.Draw(coverage)
uvdata = target.data.uv_layers.active.data
for poly in target.data.polygons:
    draw.polygon([(uvdata[li].uv.x * size, (1 - uvdata[li].uv.y) * size) for li in poly.loop_indices], fill=255)
cover = ndimage.binary_erosion(np.array(coverage)[::-1] > 0)   # Blender rows run bottom-up
baked = pixels[..., 3] > 0.5
missed = cover & ~baked
fallback = cover & ~visible_hit & baked
retex = None
if RETEXTURE:
    # ------------------------------------------------------------ AO + height on the target alone
    for src in sources + sources_full: src.hide_render = True
    select_only([target], target)
    if scene.world is None: scene.world = bpy.data.worlds.new('LODWorld')
    ao_distance = (0.30 if INFO['kind'] == 'monster' else 0.25) * H
    scene.world.light_settings.distance = ao_distance
    aux = {}
    for name, kind, samples in (('ao', 'AO', 64), ('height', 'EMIT', 4)):
        img = bpy.data.images.new(f'{CID}_lod_{name}', size, size, alpha=False, float_buffer=False)
        img.colorspace_settings.name = 'Non-Color'
        node.image = img
        scene.cycles.samples = samples
        bpy.ops.object.bake(type=kind, use_selected_to_active=False, margin=8, margin_type='EXTEND', use_clear=True,
                            target='IMAGE_TEXTURES')
        aux[name] = np.array(img.pixels[:], dtype=np.float32).reshape(size, size, 4)[..., 0].copy()
        bpy.data.images.remove(img)
    node.image = image
    for src in sources + sources_full: src.hide_render = False
    ao_map = np.clip(aux['ao'], 0, 1); height_map = np.clip(aux['height'], 0, 1)
    PILImage.fromarray((ao_map[::-1] * 255 + 0.5).astype(np.uint8)).save(OUT / f'ao_{size}.png')
    PILImage.fromarray((height_map[::-1] * 255 + 0.5).astype(np.uint8)).save(OUT / f'height_{size}.png')
    # ------------------------------------------------------------ grade inside the chart mask
    source_rgb = grading.fill_nearest(np.clip(pixels[..., :3], 0, 1).astype(np.float32), baked)
    PILImage.fromarray((source_rgb[::-1] * 255 + 0.5).astype(np.uint8)).save(OUT / f'bake_{size}_source.png')
    specs_path = Path(__file__).resolve().parent / 'native_visual_specs.json'
    head_start = 0.675
    if INFO['kind'] == 'hero' and specs_path.exists():
        head_start = float(json.loads(specs_path.read_text()).get('heroes', {}).get(CID, {}).get('head_start', 0.675))
    grade_kind = 'monster' if INFO['kind'] == 'monster' else 'hero'

    def seam_samples(ob, labels, size, inset=1.5, steps=7):
        """Texel pairs across every UV seam of `ob`: for a mesh edge shared by two faces whose
        UVs differ, points along the edge are sampled in both faces' UV spaces (pushed `inset`
        texels toward each face's centre so the eroded chart mask still covers them)."""
        me = ob.data
        uvd = me.uv_layers.active.data
        edge_faces = {}
        for poly in me.polygons:
            loops = list(poly.loop_indices)
            centre = Vector((0.0, 0.0))
            for li in loops: centre += uvd[li].uv
            centre /= max(len(loops), 1)
            for k in range(len(loops)):
                l0, l1 = loops[k], loops[(k + 1) % len(loops)]
                v0, v1 = me.loops[l0].vertex_index, me.loops[l1].vertex_index
                uv0, uv1 = uvd[l0].uv.copy(), uvd[l1].uv.copy()
                if v0 > v1: v0, v1, uv0, uv1 = v1, v0, uv1, uv0
                edge_faces.setdefault((v0, v1), []).append((uv0, uv1, centre.copy()))
        ts = np.linspace(0.08, 0.92, steps)
        a_rc, b_rc, ws = [], [], []
        for (v0, v1), faces in edge_faces.items():
            if len(faces) != 2: continue
            (a0, a1, ca), (b0, b1, cb) = faces
            if (a0 - b0).length < 1e-5 and (a1 - b1).length < 1e-5: continue
            length = (me.vertices[v0].co - me.vertices[v1].co).length
            for tt in ts:
                pa = a0.lerp(a1, tt); pb = b0.lerp(b1, tt)
                da = (ca - pa); db = (cb - pb)
                if da.length > 1e-7: pa = pa + da.normalized() * (inset / size)
                if db.length > 1e-7: pb = pb + db.normalized() * (inset / size)
                a_rc.append((int(pa.y * size) % size, int(pa.x * size) % size))
                b_rc.append((int(pb.y * size) % size, int(pb.x * size) % size))
                ws.append(length)
        return {'a_rc': np.array(a_rc, np.int64).reshape(-1, 2), 'b_rc': np.array(b_rc, np.int64).reshape(-1, 2), 'w': np.array(ws, np.float32)}
    labels_full, chart_count, _ = grading.label_charts(cover)
    seams = seam_samples(target, labels_full, size)
    # The grade's inputs are kept so a parameter round can be re-graded without Blender
    # (grade_native_albedo.py regrade <work>/<id>): chart mask, seam samples, AO, height.
    PILImage.fromarray((cover[::-1]).astype(np.uint8) * 255).save(OUT / f'cover_{size}.png')
    np.savez_compressed(OUT / 'seams.npz', **seams)
    graded, grade_info, skin = grading.grade(source_rgb, cover, ao_map, height_map, grade_kind, CID, head_start, seams=seams)
    # The whole image takes the graded result (the bake's one-texel ring outside the eroded
    # mask and the nearest-filled gutters included): an ungraded ring would draw a thin line
    # of the old colour along every UV seam after mipmapping.
    pixels[..., :3] = graded
    pixels[..., 3] = 1.0
    baked = pixels[..., 3] > 0.5
    PILImage.fromarray((skin[::-1]).astype(np.uint8) * 255).save(OUT / f'skin_{size}.png')
    atlas_info['charts'] = int(chart_count)
    retex = {'mode': 'retexture', 'clip_donor': str(INFO['glb']), 'head_start': head_start, 'grade_kind': grade_kind,
             'ao': {'distance_m': round(ao_distance, 4), 'samples': 64, 'margin': 8},
             'grade': grade_info, 'source_bake': str(OUT / f'bake_{size}_source.png'),
             'ao_map': str(OUT / f'ao_{size}.png'), 'height_map': str(OUT / f'height_{size}.png')}
_, (iy, ix) = ndimage.distance_transform_edt(~baked, return_indices=True)
filled = pixels[iy, ix]
rgb8 = (np.clip(filled[..., :3], 0, 1)[::-1] * 255 + 0.5).astype(np.uint8)
full = PILImage.fromarray(rgb8, 'RGB')
full.save(OUT / f'bake_{size}.png')
PILImage.fromarray((missed[::-1]).astype(np.uint8) * 255).save(OUT / f'misses_{size}.png')
final = full.resize((B['texture'], B['texture']), PILImage.BOX) if B['texture'] != size else full
final_path = OUT / f'{CID}_lod_albedo.png'
final.save(final_path, optimize=True)
if RETEXTURE:
    tex = B['texture']; f = size // tex
    cover_small = cover.reshape(tex, f, tex, f).mean(axis=(1, 3)) > 0.5
    skin_small = skin.reshape(tex, f, tex, f).mean(axis=(1, 3)) > 0.5
    PILImage.fromarray((cover_small[::-1]).astype(np.uint8) * 255).save(OUT / f'cover_{tex}.png')
    PILImage.fromarray((skin_small[::-1]).astype(np.uint8) * 255).save(OUT / f'skin_{tex}.png')
    labels_s, _, slices_s = grading.label_charts(cover_small)
    after_rgb = np.asarray(final.convert('RGB')).astype(np.float32)[::-1] / 255.0
    retex['stats_after'] = grading.atlas_stats(after_rgb, cover_small, labels_s, slices_s, skin=skin_small)
    # "Before" = the atlas of the 2026-10-15 LOD pass (its candidate GLB, else the shipped GLB):
    # the editable blend already carries the previous retexture round after a re-run.
    def embedded_png(glb_payload):
        gl, binary = _read_glb(glb_payload)
        view = gl['bufferViews'][gl['images'][0]['bufferView']]
        start = view.get('byteOffset', 0)
        import io
        return PILImage.open(io.BytesIO(bytes(binary[start:start + view['byteLength']]))).convert('RGB')
    original_lod = ROOT / 'build/character-3d/lod-2026-10-15/candidates' / f'{CID}.glb'
    before_source = original_lod if original_lod.exists() else INFO['glb']
    try:
        old_pil = embedded_png(before_source.read_bytes())
        if old_pil.size != (tex, tex): old_pil = old_pil.resize((tex, tex), PILImage.BOX)
        old_rgb = np.asarray(old_pil).astype(np.float32)[::-1] / 255.0
        old_pil.save(OUT / f'{CID}_lod_albedo_before.png')
        old_skin = grading.skin_mask(old_rgb, cover_small, labels_s, slices_s)
        retex['stats_before'] = grading.atlas_stats(old_rgb, cover_small, labels_s, slices_s, skin=old_skin)
        retex['stats_before_source'] = str(before_source)
    except Exception as exc:  # noqa: BLE001 - the statistics are evidence, not a gate
        retex['stats_before'] = None
        retex['stats_before_source'] = f'unavailable: {exc}'

# ---------------------------------------------------------------------------- materials back
stale = bpy.data.images.get(f'{CID}_lod_albedo')
if stale is not None:
    # Retexture: the previous atlas keeps this name in game-lod.blend; the exported image (and
    # Godot's extracted <id>_<id>_lod_albedo.png) must keep it, so the old datablock goes first.
    bpy.data.images.remove(stale)
albedo = bpy.data.images.load(str(final_path))
albedo.name = f'{CID}_lod_albedo'
albedo.colorspace_settings.name = 'sRGB'
albedo.pack()
for i, mat in enumerate(slot_materials): target.data.materials[i] = mat
link, _ = base_color_source(atlas_mat)
link.node.image = albedo
shader = next(n for n in atlas_mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
for socket_name, value in [('Metallic', 0.0), ('Roughness', 0.86)]:
    # Only the albedo ships; a reconstruction ORM map (Limne's 2048 Image_1) is not exported.
    socket = shader.inputs[socket_name]
    if socket.links:
        for l in list(socket.links): atlas_mat.node_tree.links.remove(l)
        socket.default_value = value
for i, mat in enumerate(slot_materials):
    if textured(mat) and mat is not atlas_mat: target.data.materials[i] = atlas_mat
for src in sources + sources_full: bpy.data.objects.remove(src, do_unlink=True)
bpy.data.materials.remove(bake_mat)
for mat in list(bpy.data.materials):
    if mat.name.startswith('LODEmit_'): bpy.data.materials.remove(mat)
bpy.data.images.remove(image)
for img in list(bpy.data.images):
    if img.users == 0: bpy.data.images.remove(img)
rig.data.pose_position = 'POSE'

after_meshes = [o for o in scene.objects if o.type == 'MESH']
after = {'triangles': sum(tri_count(o) for o in after_meshes), 'meshes': len(after_meshes),
         'vertices': sum(len(o.data.vertices) for o in after_meshes)}
sole_after = sole_metrics(target, legs)
if RETEXTURE:
    keep = INFO['lod_blend'].with_name(INFO['lod_blend'].stem + '.pre-retexture.blend')
    if not keep.exists():
        import shutil
        shutil.copy2(INFO['lod_blend'], keep)
bpy.ops.wm.save_as_mainfile(filepath=str(INFO['lod_blend']))

# ---------------------------------------------------------------------------- export + graft clips
bpy.ops.object.select_all(action='SELECT')
temp = OUT / 'lod-export.glb'
export_kwargs = dict(filepath=str(temp), export_format='GLB', export_apply=False, export_materials='EXPORT',
                     export_extras=True, export_yup=True, export_animations=True, export_nla_strips=True,
                     export_cameras=False, export_lights=False)
if INFO['kind'] != 'limne': export_kwargs['export_anim_single_armature'] = True
bpy.ops.export_scene.gltf(**export_kwargs)
fresh = temp.read_bytes()
def splice_images(base_payload, fresh_payload):
    """The shipped GLB with only its embedded images replaced by the fresh export's: every
    mesh, skin, node, material and clip byte stays (retexture mode never re-exports geometry
    into the runtime; the exporter's normal recomputation is not bit-stable on every mesh)."""
    base, base_bin = _read_glb(base_payload)
    fresh_g, fresh_bin = _read_glb(fresh_payload)
    if len(base.get('images', [])) != len(fresh_g.get('images', [])) or not base.get('images'):
        raise SystemExit(f'{CID}: image count differs between the shipped GLB ({len(base.get("images", []))}) '
                         f'and the fresh export ({len(fresh_g.get("images", []))})')
    replaced = {}
    for bi, fi in zip(base['images'], fresh_g['images']):
        fv = fresh_g['bufferViews'][fi['bufferView']]
        start = fv.get('byteOffset', 0)
        replaced[bi['bufferView']] = bytes(fresh_bin[start:start + fv['byteLength']])
        if 'mimeType' in fi: bi['mimeType'] = fi['mimeType']
    out_bin = bytearray(); views = []
    for idx, view in enumerate(base['bufferViews']):
        view = dict(view)
        start = view.get('byteOffset', 0); size = view['byteLength']
        data = replaced.get(idx, bytes(base_bin[start:start + size]))
        out_bin += b'\0' * (-len(out_bin) % 4)
        view['byteOffset'] = len(out_bin); view['byteLength'] = len(data); view['buffer'] = 0
        out_bin += data
        views.append(view)
    base['bufferViews'] = views
    base['buffers'] = [{'byteLength': len(out_bin) + (-len(out_bin) % 4)}]
    return _write_glb(base, out_bin)


if RETEXTURE:
    payload = splice_images(runtime_payload, fresh)
else:
    # Limne's joined surfaces change the node list, so its clips are re-targeted by bone name.
    payload = merge_animations(fresh, runtime_payload, by_name=INFO['kind'] == 'limne')
dest = Path(args.candidate) if args.candidate else INFO['glb']
dest.parent.mkdir(parents=True, exist_ok=True)
dest.write_bytes(payload)
def geometry_fingerprint(glb_payload):
    """sha256 of every mesh/skin accessor's bytes plus the node list: equal fingerprints mean the
    shipped positions, normals, UVs, joints, weights, indices, bind matrices and rig are untouched."""
    gl, binary = _read_glb(glb_payload)
    digest = hashlib.sha256()

    def accessor_bytes(index):
        acc = gl['accessors'][index]; view = gl['bufferViews'][acc['bufferView']]
        start = view.get('byteOffset', 0) + acc.get('byteOffset', 0)
        return bytes(binary[start:view.get('byteOffset', 0) + view['byteLength']])
    for mesh in gl.get('meshes', []):
        for prim in mesh.get('primitives', []):
            for name in sorted(prim.get('attributes', {})):
                digest.update(name.encode()); digest.update(accessor_bytes(prim['attributes'][name]))
            if 'indices' in prim: digest.update(b'indices'); digest.update(accessor_bytes(prim['indices']))
    for skin in gl.get('skins', []):
        if 'inverseBindMatrices' in skin: digest.update(b'ibm'); digest.update(accessor_bytes(skin['inverseBindMatrices']))
        digest.update(json.dumps(skin.get('joints', [])).encode())
    nodes = [{k: v for k, v in n.items() if k not in ('mesh', 'skin')} for n in gl.get('nodes', [])]
    digest.update(json.dumps(nodes, sort_keys=True).encode())
    return digest.hexdigest()


g, _ = _read_glb(payload)
tris = sum(g['accessors'][p['indices']]['count'] // 3 for m in g['meshes'] for p in m['primitives'])
verts = sum(g['accessors'][p['attributes']['POSITION']]['count'] for m in g['meshes'] for p in m['primitives'])
surfaces = sum(len(m['primitives']) for m in g['meshes'])
report = {'id': CID, 'kind': INFO['kind'], 'budget': B, 'source_blend': str(INFO['blend']), 'lod_blend': str(INFO['lod_blend']),
          'before': dict(before, runtime_triangles=runtime_tris, glb_bytes=len(runtime_payload),
                         glb_sha256=hashlib.sha256(runtime_payload).hexdigest(), sole=sole_before),
          'after': dict(after, glb_triangles=tris, glb_vertices=verts, glb_surfaces=surfaces, glb_meshes=len(g['meshes']),
                        glb_materials=len(g.get('materials', [])), glb_bytes=len(payload),
                        glb_sha256=hashlib.sha256(payload).hexdigest(), texture=B['texture'], sole=sole_after),
          'atlas': atlas_info, 'bake_source_visibility': hidden_info, 'deviation_m': dev, 'cage_extrusion_m': extrusion, 'max_ray_m': max_ray,
          'bake': {'size': size, 'covered_texels': int(cover.sum()), 'missed_texels': int(missed.sum()),
                   'interior_fallback_texels': int(fallback.sum()),
                   'miss_fraction': float(missed.sum() / max(cover.sum(), 1))},
          'output': str(dest)}
if retex is not None:
    shipped_fp = geometry_fingerprint(runtime_payload); new_fp = geometry_fingerprint(payload)
    retex.update({'geometry_sha256_shipped': shipped_fp, 'geometry_sha256_candidate': new_fp,
                  'geometry_bytes_preserved': shipped_fp == new_fp,
                  'fresh_export_geometry_identical': geometry_fingerprint(fresh) == shipped_fp,
                  'assembly': 'shipped GLB with its embedded image bytes replaced by the fresh export (splice_images)',
                  'shipped_glb_sha256': hashlib.sha256(runtime_payload).hexdigest()})
    report['retexture'] = retex
(OUT / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
temp.unlink()
summary = {'id': CID, 'tris': tris, 'verts': verts, 'surfaces': surfaces, 'bytes': len(payload),
           'miss': round(report['bake']['miss_fraction'], 4), 'dev_p99': round(dev['p99'], 4), 'charts': atlas_info['charts'],
           'floor': [round(sole_before['floor'], 4), round(sole_after['floor'], 4)]}
if retex is not None:
    summary['geometry_preserved'] = retex['geometry_bytes_preserved']
    summary['mean_lstar'] = [retex['stats_before'].get('mean_lstar') if retex['stats_before'] else None, retex['stats_after']['mean_lstar']]
    summary['p10'] = [retex['stats_before'].get('lum_p10') if retex['stats_before'] else None, retex['stats_after']['lum_p10']]
print('NATIVE_LOD ' + json.dumps(summary), flush=True)
