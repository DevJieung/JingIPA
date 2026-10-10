#!/usr/bin/env python3
"""Finish a real TRELLIS.2 PBR mesh in Blender; preserve its sculpt and UV maps.

bl -b --factory-startup --python tools/3d/finish_limne_pro.py -- \
  --input build/limne-pro/source/limne-pbr.glb --front +y

This stage normalizes the real generated mesh, creates a continuous five-bone
skin and the five existing game control pivots, and exports the runtime GLB.
The reconstruction supplies hair/clothes/body. Blender adds a continuous
authored face/neck, curved eyes/lids, and machined equipment; this is a hybrid.
"""
import argparse
import bpy
import bmesh
import json
import hashlib
import struct
import math
import sys
from pathlib import Path
from mathutils import Vector, Matrix

sys.path.insert(0,str(Path(__file__).resolve().parent))
from limne_surface_finish import finish_surface
from limne_bake import bake_surface
from limne_local_polish import polish

ROOT=Path(__file__).resolve().parents[2]
args=argparse.ArgumentParser()
args.add_argument('--input',required=True)
args.add_argument('--front',choices=['+x','-x','+y','-y'],default='+y')
args.add_argument('--triangles',type=int,default=200000)
args.add_argument('--height',type=float,default=1.63)
args.add_argument('--bake',action='store_true',help='experimental atlas rebuild; rejected in current visual QA')
args.add_argument('--experimental-atlas-rebuild',action='store_true',help='explicitly allow destructive reduction or rebake for experiments')
args.add_argument('--legacy-surface-finishing',action='store_true',help='explicitly replace the accepted animated model with the older surface-finishing branch')
opts=args.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
if (opts.bake or opts.triangles<200000) and not opts.experimental_atlas_rebuild:
    raise RuntimeError('Current validated path preserves source UV/PBR. Reduction/rebake requires --experimental-atlas-rebuild and fresh visual QA.')
out=ROOT/'art/models/limne';source=ROOT/'build/limne-pro/source'
if (out/'provenance.json').exists() and json.loads((out/'provenance.json').read_text()).get('motion_bones') and not opts.legacy_surface_finishing:
    raise RuntimeError('Animated Limne is current. Legacy surface regeneration requires --legacy-surface-finishing; use style_animate_limne.py for accepted shape/style/motion.')
out.mkdir(parents=True,exist_ok=True);source.mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(Path(opts.input).resolve()))
objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
if not objects:raise RuntimeError('No actual mesh in input GLB')

# Preserve UVs/materials while applying the source transform and a single yaw.
yaw={'+y':0,'-y':math.pi,'+x':math.pi/2,'-x':-math.pi/2}[opts.front]
turn=Matrix.Rotation(yaw,4,'Z')
for o in objects:
    bpy.context.view_layer.objects.active=o
    if o.data.has_custom_normals:bpy.ops.mesh.customdata_custom_splitnormals_clear()
    o.data.use_auto_smooth=False
    o.data.transform(turn@o.matrix_world)
    o.matrix_world=Matrix.Identity(4)
    o.parent=None
for o in list(bpy.context.scene.objects):
    if o not in objects:bpy.data.objects.remove(o,do_unlink=True)
points=[v.co for o in objects for v in o.data.vertices]
minimum=Vector(tuple(min(v[i] for v in points) for i in range(3)))
maximum=Vector(tuple(max(v[i] for v in points) for i in range(3)))
scale=opts.height/(maximum.z-minimum.z)
center=Vector(((minimum.x+maximum.x)/2,(minimum.y+maximum.y)/2,minimum.z))
for o in objects:
    for v in o.data.vertices:v.co=(v.co-center)*scale
    # UV charts use loop UVs; weld coincident geometry so smooth normals and
    # continuous skin do not turn every chart edge into a hard polygon seam.
    bm=bmesh.new();bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=0.00001)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(o.data);bm.free()
    o.data.validate(verbose=True,clean_customdata=True)
    for face in o.data.polygons:face.use_smooth=True
    o.data.update()

authored=finish_surface(objects)

# Keep the genuine dense geometry for studio inspection and later bake/LOD work.
bpy.ops.wm.save_as_mainfile(filepath=str(source/'limne_high.blend'))
high_meshes=[o.data.copy() for o in objects] if opts.bake else []
original_triangles=sum(sum(len(f.vertices)-2 for f in o.data.polygons) for o in objects)
ratio=min(1,opts.triangles/max(1,original_triangles))
for o in objects:
    if ratio<.999:
        bpy.context.view_layer.objects.active=o
        mod=o.modifiers.new('mobile_surface_reduction','DECIMATE');mod.ratio=ratio
        mod.use_collapse_triangulate=True
        bpy.ops.object.modifier_apply(modifier=mod.name)

# A fresh Mesh removes stale evaluated CustomData/normal caches inherited from
# imported nonmanifold charts and modifier application. Copy actual loop UVs
# and material/corner colour information explicitly, before baking or skinning.
for o in objects:
    old=o.data
    coords=[v.co[:] for v in old.vertices];faces=[tuple(f.vertices) for f in old.polygons]
    uv_values=[d.uv[:] for d in old.uv_layers.active.data]
    color_values=[d.color[:] for d in old.color_attributes['SkinComplexion'].data]
    indices=[f.material_index for f in old.polygons];materials=list(old.materials)
    fresh=bpy.data.meshes.new('Limne_clean_game_surface')
    fresh.from_pydata(coords,[],faces)
    for m in materials:fresh.materials.append(m)
    uv=fresh.uv_layers.new(name='UVMap')
    col=fresh.color_attributes.new(name='SkinComplexion',type='FLOAT_COLOR',domain='CORNER')
    # Get a fresh UV-data view after the color layer allocation.
    for i,d in enumerate(fresh.uv_layers.active.data):d.uv=uv_values[i]
    for i,d in enumerate(col.data):d.color=color_values[i]
    for i,f in enumerate(fresh.polygons):f.material_index=indices[i];f.use_smooth=True
    fresh.validate(verbose=True,clean_customdata=True);fresh.update();fresh.calc_loop_triangles()
    o.data=fresh;bpy.data.meshes.remove(old)

for o in objects:
    if len(o.data.materials)>1 and o.data.color_attributes.get('SkinComplexion'):
        colors=o.data.color_attributes['SkinComplexion'].data
        for face in o.data.polygons:
            skin=o.data.materials[face.material_index].name=='Skin_soft_warm_volume'
            for li in face.loop_indices:colors[li].color=(.59,.345,.245,1) if skin else (1,1,1,1)
if opts.bake:
    for i,o in enumerate(objects):bake_surface(o,high_meshes[i],source/'textures')
objects.extend(authored)
for o in objects:
    bpy.context.view_layer.objects.active=o
    if o.data.has_custom_normals:bpy.ops.mesh.customdata_custom_splitnormals_clear()
    o.data.use_auto_smooth=False
    for face in o.data.polygons:face.use_smooth=True
    if len(o.data.materials)>1 and o.data.color_attributes.get('SkinComplexion'):
        colors=o.data.color_attributes['SkinComplexion'].data
        for face in o.data.polygons:
            skin=o.data.materials[face.material_index].name=='Skin_soft_warm_volume'
            for li in face.loop_indices:colors[li].color=(.59,.345,.245,1) if skin else (1,1,1,1)
    o.data.update()


def xyz(x,y,z):return (x,-z,y)
def smooth(a,b,x):
    t=max(0,min(1,(x-a)/(b-a)));return t*t*(3-2*t)


arm_data=bpy.data.armatures.new('LimneContinuousSkin')
rig=bpy.data.objects.new('LimneSkin',arm_data)
bpy.context.collection.objects.link(rig)
bpy.context.view_layer.objects.active=rig;rig.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
starts={'Body':(0,0,0),'ArmL':(-.32,1.035,0),'ArmR':(.32,1.035,0),
        'LegL':(-.15,.45,0),'LegR':(.15,.45,0)}
for name,start in starts.items():
    bone=arm_data.edit_bones.new('Skin'+name)
    bone.head=xyz(*start)
    end=(start[0],start[1]+.40,start[2]) if name=='Body' else (start[0],start[1]-.31,start[2])
    bone.tail=xyz(*end)
    # Separate root bones let the original world-space pivot motion remain exact.
bpy.ops.object.mode_set(mode='OBJECT')
for o in objects:
    groups={name:o.vertex_groups.new(name='Skin'+name) for name in starts}
    for v in o.data.vertices:
        x,z,y=v.co.x,v.co.y,v.co.z
        # The front of the finished character is +Blender Y (= -Godot Z).
        front=z
        weights={'Body':1.0}
        if y<.58:
            leg=1-smooth(.42,.58,y)
            weights={'Body':1-leg,'LegR' if x>=0 else 'LegL':leg}
        if .54<y<1.18:
            arm=smooth(.24,.355,abs(x))*(1-smooth(1.065,1.18,y))
            arm*=smooth(-.105,.065,front)
            arm*=smooth(.54,.66,y)
            if arm>.001:
                weights={k:w*(1-arm) for k,w in weights.items()}
                weights['ArmR' if x>=0 else 'ArmL']=arm
        if 'limne_hose_side' in o:
            t=o.data.attributes['HoseBend'].data[v.index].value
            bend=t*t*(3-2*t)
            weights={'Body':1-bend,o['limne_hose_side']:bend}
        elif 'limne_control' in o:weights={o['limne_control']:1.0}
        for name,w in weights.items():
            if w>.0001:groups[name].add([v.index],w,'REPLACE')
    mod=o.modifiers.new('continuous_clothing_and_skin','ARMATURE');mod.object=rig
    o.parent=rig
    o.name='Limne_PBR_Surface'

objects.extend(polish(objects[0],rig))

# The old game manipulates these five direct child nodes. The adapter applies
# their transforms to the five skin bones without rewriting the battle clock.
for name,start in starts.items():
    control=bpy.data.objects.new(name,None)
    bpy.context.collection.objects.link(control)
    control.location=xyz(*start)

bpy.ops.wm.save_as_mainfile(filepath=str(source/'limne_game.blend'))
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=str(out/'limne.glb'),export_format='GLB',
    export_apply=False,export_materials='EXPORT',export_extras=True,
    export_yup=True,export_cameras=False,export_lights=False,
    export_draco_mesh_compression_enable=False)
final_triangles=sum(sum(len(f.vertices)-2 for f in o.data.polygons) for o in objects)
payload=(out/'limne.glb').read_bytes()
native=Path(opts.input).read_bytes()
raw_json=json.loads(native[20:20+struct.unpack_from('<I',native,12)[0]])
glb_json=json.loads(payload[20:20+struct.unpack_from('<I',payload,12)[0]])
raw_triangles=sum(raw_json['accessors'][p['indices']]['count']//3 for m in raw_json['meshes'] for p in m['primitives'])
record={'creator':'Hybrid TRELLIS.2 hair/clothing/body + Blender authored continuous face/neck/hands, curved eyes and machinery',
    'input':str(Path(opts.input)),'quality_reference':'build/limne-pro/concept/limne_target.png',
    'concept_type':'built-in image_gen raster; separate from real GLB',
    'glb':'art/models/limne/limne.glb','blender':bpy.app.version_string,
    'high_source':'build/limne-pro/source/limne_high.blend',
    'game_source':'build/limne-pro/source/limne_game.blend',
    'raw_source_triangles':raw_triangles,'cleaned_retained_surface_before_local_polish_triangles':original_triangles,
    'game_triangles_before_gltf':final_triangles,
    'surface_strategy':'preserved original 2048 base-color/ORM UV maps; no reduction or atlas rebake',
    'runtime_normal_map':False,
    'runtime_color_correction':'LimneModel enables radial iris COLOR_0 omitted by Godot material import; skin COLOR_0 already active',
    'quality_status':'improved editable experiment; target-concept parity not achieved',
    'glb_bytes':len(payload),'glb_meshes':len(glb_json['meshes']),
    'glb_materials':len(glb_json['materials']),'embedded_images':len(glb_json['images']),
    'source_sha256':hashlib.sha256(native).hexdigest(),'glb_sha256':hashlib.sha256(payload).hexdigest(),
    'height':opts.height,'source_front':opts.front,
    'rig':'five continuous skin bones, driven by five existing direct child pivots'}
(out/'provenance.json').write_text(json.dumps(record,indent=2)+'\n')
print('LIMNE_PRO_FINISH',json.dumps(record))
