#!/usr/bin/env python3
"""Finish the retained closed-v2 plant surface, without remesh or atlas bake.

This is an ID-specific authored finish, not a universal creature builder.
Native UV/skin/clips and the reconstructed roots/body PBR remain real. Soft
rest-surface polish and locally assigned matte flower/leaf materials remove
reconstruction grain while preserving the plant's original anatomy.
"""
import hashlib, json, math, struct, sys
from pathlib import Path
import bpy

ROOT = Path(__file__).resolve().parents[2]
if '--rejected-polish' not in sys.argv:
    raise SystemExit('Rejected historical experiment. Do not overwrite accepted Titan; current repair is tools/3d/repair_titan_bloom.py. Use --rejected-polish only in a preserved experimental checkout.')
work = ROOT/'build/character-3d/monster-source/titan_bloom'
dest = ROOT/'art/models/monsters/titan_bloom/titan_bloom.glb'
source = work/'game.blend'
bpy.ops.wm.open_mainfile(filepath=str(source))
rig = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
rig.animation_data.action = None
for bone in rig.pose.bones:
    bone.matrix_basis.identity()
bpy.context.scene.frame_set(0)
objects = [o for o in bpy.context.scene.objects if o.type == 'MESH']
H = 1.55

def material(name, color):
    mat = bpy.data.materials.new('Titan_'+name)
    mat.use_nodes = True
    shader = mat.node_tree.nodes['Principled BSDF']
    shader.inputs['Base Color'].default_value = (*color,1)
    shader.inputs['Roughness'].default_value = .85
    shader.inputs['Metallic'].default_value = 0
    shader.inputs['Specular IOR Level'].default_value = .14
    return mat

colors = [material('PalePetal',(.78,.24,.30)),
          material('MagentaPetal',(.42,.025,.085)),
          material('OliveLeaf',(.16,.23,.045)),
          material('DarkOliveLeaf',(.075,.13,.025))]
stats = {'petals':0,'leaves':0,'retained_native_pbr':0}
for ob in objects:
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    # Change only rest positions. Topology, UVs, skin weights and face winding
    # survive; unlike collapse, this cannot reconnect distant native sheets.
    group = ob.vertex_groups.new(name='Titan_LocalSurfacePolish')
    for v in ob.data.vertices:
        z = v.co.z/H
        if z > .16:
            group.add([v.index], .65 if z > .48 else .35, 'REPLACE')
    modifier = ob.modifiers.new('Authored_soft_surface_finish','SMOOTH')
    modifier.factor = .35
    modifier.iterations = 4
    modifier.vertex_group = group.name
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    ob.data.update()
    uv = ob.data.uv_layers.active
    original = ob.data.materials[0]
    image = next(n.image for n in original.node_tree.nodes
                 if n.type == 'TEX_IMAGE' and n.image and n.image.colorspace_settings.name == 'sRGB')
    pixels = list(image.pixels)
    width, height = image.size
    offset = len(ob.data.materials)
    for mat in colors:
        ob.data.materials.append(mat)
    for face in ob.data.polygons:
        center = face.center/H
        coord = sum((uv.data[i].uv for i in face.loop_indices), start=uv.data[face.loop_indices[0]].uv*0)/len(face.loop_indices)
        u = max(0,min(width-1,int(coord.x*width)))
        v = max(0,min(height-1,int(coord.y*height)))
        i = (v*width+u)*4
        r,g,b = pixels[i:i+3]
        # Only actual reddish reconstructed flower surfaces above the root
        # body. Brown roots and the dark open maw retain their native texture.
        if center.z > .47 and r > .08 and r > g*1.28 and r > b*1.10:
            # Coherent alternating petal volumes, not noisy per-face texture.
            angle = math.atan2(center.z-.70,center.x-.10)
            pale = math.sin(angle*4+.8) > -.1
            face.material_index = offset+(0 if pale else 1)
            stats['petals'] += 1
        elif center.z > .18 and g > .07 and g > r*1.05 and g > b*1.23:
            face.material_index = offset+(2 if center.y > -.05 else 3)
            stats['leaves'] += 1
        else:
            stats['retained_native_pbr'] += 1
    for face in ob.data.polygons:
        face.use_smooth = True
    ob.data.update()
for image in bpy.data.images:
    if image.type == 'IMAGE' and image.size[0] > 1:
        image.pack()
bpy.ops.wm.save_as_mainfile(filepath=str(source))
bpy.ops.object.select_all(action='SELECT')
temporary = work/'polished-native-export.glb'
bpy.ops.export_scene.gltf(filepath=str(temporary),export_format='GLB',export_apply=False,
    export_materials='EXPORT',export_extras=True,export_yup=True,export_animations=True,
    export_nla_strips=True,export_anim_single_armature=True,export_cameras=False,export_lights=False)
payload = temporary.read_bytes()
temporary.replace(dest)
count = struct.unpack_from('<I',payload,12)[0]
gltf = json.loads(payload[20:20+count])
sha = hashlib.sha256(payload).hexdigest()
pp = dest.parent/'provenance.json'
prov = json.loads(pp.read_text())
raw = Path(prov['input']).read_bytes()
count = struct.unpack_from('<I',raw,12)[0]
raw_gltf = json.loads(raw[20:20+count])
prov['raw_gltf_triangles'] = sum(raw_gltf['accessors'][p['indices']]['count']//3 for mesh in raw_gltf['meshes'] for p in mesh['primitives'])
prov.update(glb_sha256=sha,glb_bytes=len(payload),material_count=len(gltf['materials']),
    embedded_images=len(gltf['images']),game_triangles=sum(gltf['accessors'][p['indices']]['count']//3 for mesh in gltf['meshes'] for p in mesh['primitives']),
    creator='Actual TRELLIS closed-v2 native volume retained without collapse; Blender rest-surface smoothing and locally authored matte petal/leaf material finishing; original UV/PBR on roots/body, skin and authored IdleLoop/MoveLoop retained.',
    authored_finish=stats,quality_status='candidate: actual final multiview/motion/Godot QA required')
pp.write_text(json.dumps(prov,indent=2)+'\n')
path = ROOT/'art/models/native_monsters.json'
manifest = json.loads(path.read_text())
manifest['monsters']['titan_bloom']['glb_sha256'] = sha
manifest['monsters']['titan_bloom']['ready'] = False
temp = path.with_suffix('.tmp')
temp.write_text(json.dumps(manifest,indent=2)+'\n');temp.replace(path)
print('TITAN_NATIVE_SURFACE_POLISH',sha,stats)
