#!/usr/bin/env python3
"""Read actual rendered surface points/skin weights; never modify a source."""
import argparse, hashlib, json, sys
from pathlib import Path
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

p = argparse.ArgumentParser()
p.add_argument('--input', required=True)
p.add_argument('--camera', required=True)
p.add_argument('--view', default='three_quarter')
p.add_argument('--points', required=True, help='name:x,y;name:x,y')
p.add_argument('--output', required=True)
a = p.parse_args(sys.argv[sys.argv.index('--') + 1:])
source = Path(a.input)
before = hashlib.sha256(source.read_bytes()).hexdigest()
bpy.ops.wm.open_mainfile(filepath=str(source))
meta = json.loads(Path(a.camera).read_text())[a.view]
scene = bpy.context.scene
for ob in scene.objects:
    if ob.type != 'ARMATURE':
        continue
    if ob.animation_data:
        ob.animation_data.action = bpy.data.actions.get(meta['clip']) if meta['clip'] else None
        for track in ob.animation_data.nla_tracks:
            track.mute = True
    if not meta['clip']:
        for bone in ob.pose.bones:
            bone.matrix_basis = Matrix.Identity(4)
scene.frame_set(meta['frame'] if meta['clip'] else 0)
bpy.context.view_layer.update()
matrix = Matrix(meta['camera_matrix'])
width, height = meta['width'], meta['height']
scale = meta['ortho_scale']
direction = matrix.to_3x3() @ Vector((0, 0, -1))
trees = []
for ob in scene.objects:
    if ob.type != 'MESH':
        continue
    evaluated = ob.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = evaluated.to_mesh()
    vertices = [evaluated.matrix_world @ v.co for v in mesh.vertices]
    tree = BVHTree.FromPolygons(vertices, [list(f.vertices) for f in mesh.polygons])
    trees.append((ob, evaluated, mesh, vertices, tree))
result = []
for point in a.points.split(';'):
    name, xy = point.split(':')
    px, py = map(float, xy.split(','))
    local = Vector(((px / width - .5) * scale * width / height,
                    (.5 - py / height) * scale, 0))
    origin = matrix @ local
    hits = []
    for ob, evaluated, mesh, vertices, tree in trees:
        hit, normal, face, distance = tree.ray_cast(origin, direction)
        if hit is None:
            continue
        ids = list(mesh.polygons[face].vertices)
        weights = []
        for vid in ids:
            groups = {ob.vertex_groups[g.group].name: g.weight for g in ob.data.vertices[vid].groups}
            weights.append({'vertex': vid, 'rest_xyz': list(ob.data.vertices[vid].co), 'weights': groups})
        hits.append({'distance': distance, 'xyz': list(hit), 'normal': list(normal),
                     'mesh': ob.name, 'face': face, 'source_vertices': weights})
    nearest = min(hits, key=lambda v: v['distance']) if hits else None
    result.append({'name': name, 'pixel': [px, py], 'hit': nearest})
for ob, evaluated, mesh, vertices, tree in trees:
    evaluated.to_mesh_clear()
output = {'input': str(source), 'source_sha256': before, 'source_unchanged': before == hashlib.sha256(source.read_bytes()).hexdigest(),
          'height': meta['native_height'], 'coordinate_space': 'Blender xyz; divide by height for surface ROI', 'samples': result}
Path(a.output).write_text(json.dumps(output, indent=2) + '\n')
print(json.dumps(output, indent=2))
