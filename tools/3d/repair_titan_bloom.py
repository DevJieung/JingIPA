#!/usr/bin/env python3
"""Repair this plant's reconstructed volume; transfer real source UV and skin.

This is a bounded, ID-specific native-surface retopology, not a primitive
replacement or another image inference. Raw/high and rejected finishes survive.
"""
import hashlib, json, math, shutil, struct, subprocess
from pathlib import Path
import bpy
import numpy as np
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

ROOT=Path(__file__).resolve().parents[2]
work=ROOT/'build/character-3d/monster-source/titan_bloom'
out=ROOT/'art/models/monsters/titan_bloom'
archive=ROOT/'build/character-3d/monster-review/titan_bloom/rejected-polish'
archive.mkdir(parents=True,exist_ok=True)
for p in [work/'game.blend',work/'high.blend',out/'titan_bloom.glb',out/'provenance.json']:
    target=archive/p.name
    if not target.exists(): shutil.copy2(p,target)
(archive/'manifest.json').write_text(json.dumps({p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in archive.iterdir() if p.is_file() and p.name!='manifest.json'},indent=2)+'\n')

# Read the actual source skin and authored clips before replacing its surface.
bpy.ops.wm.open_mainfile(filepath=str(archive/'game.blend'))
rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
rig.animation_data.action=None
for bone in rig.pose.bones: bone.matrix_basis=Matrix.Identity(4)
bpy.context.scene.frame_set(0)
old=next(o for o in bpy.context.scene.objects if o.type=='MESH')
game_native_material=old.data.materials[0]
skin_names={g.index:g.name for g in old.vertex_groups if g.name in rig.data.bones}
old_co=[v.co.copy() for v in old.data.vertices]
old_weights=[{skin_names[g.group]:g.weight for g in v.groups if g.group in skin_names} for v in old.data.vertices]
kd=KDTree(len(old_co))
for i,co in enumerate(old_co): kd.insert(co,i)
kd.balance()
bpy.data.objects.remove(old,do_unlink=True)
with bpy.data.libraries.load(str(work/'high.blend'),link=False) as (src,dst):
    dst.objects=[name for name in src.objects if 'Mesh' in name or 'Surface' in name]
sources=[o for o in dst.objects if o and o.type=='MESH']
if len(sources)!=1: raise RuntimeError('Expected one reconstructed plant source')
ob=sources[0];bpy.context.collection.objects.link(ob)
ob.parent=None;ob.matrix_world=Matrix.Identity(4)
data=ob.data
data.calc_loop_triangles()
coords=[v.co.copy() for v in data.vertices]
faces=[tuple(t.vertices) for t in data.loop_triangles]
uv=data.uv_layers.active
face_uv=[tuple(uv.data[i].uv.copy() for i in t.loops) for t in data.loop_triangles]
tree=BVHTree.FromPolygons(coords,faces,all_triangles=True)
original_material=game_native_material
for mat in [original_material]:
    bsdf=mat.node_tree.nodes.get('Principled BSDF')
    for name,value in [('Metallic',0),('Roughness',.85),('Specular IOR Level',.14),('Coat Weight',0)]:
        socket=bsdf.inputs.get(name)
        if socket:
            for link in list(socket.links): mat.node_tree.links.remove(link)
            socket.default_value=value
bpy.ops.object.select_all(action='DESELECT');ob.select_set(True)
bpy.context.view_layer.objects.active=ob
# Rebuild native positions/faces into clean Blender CustomData. The imported
# remesh has stale/invalid internal mesh data despite valid GLB coordinates.
clean=bpy.data.meshes.new('Titan_native_volume_clean_data')
clean.from_pydata(coords,[],faces);clean.validate(clean_customdata=True);clean.update()
ob.data=clean
print('REMESH_INPUT',len(coords),len(faces),tuple(min(v[i] for v in coords) for i in range(3)),tuple(max(v[i] for v in coords) for i in range(3)),flush=True)
native_npz=work/'native-volume-input.npz';surface_npz=work/'repaired-volume.npz'
np.savez_compressed(native_npz,vertices=np.array(coords),faces=np.array(faces))
if not surface_npz.exists():
    subprocess.run(['/home/dgxmaruta/.local/opt/trellis/venv/bin/python',str(ROOT/'tools/3d/titan_surface_voxel.py'),str(native_npz),str(surface_npz),'.0062'],check=True)
result=np.load(surface_npz)
continuous=bpy.data.meshes.new('Titan_native_continuous_surface')
continuous.from_pydata(result['vertices'].tolist(),[],result['faces'].tolist());continuous.update()
ob.data=continuous
smooth=ob.modifiers.new('Local_continuous_surface_finish','SMOOTH')
smooth.factor=.32;smooth.iterations=3
bpy.ops.object.modifier_apply(modifier=smooth.name)
# Simplify the new, closed regular surface BEFORE transferring any UV charts.
# This does not collapse or interpolate the defective imported UV topology.
triangles=sum(len(f.vertices)-2 for f in ob.data.polygons)
if triangles>140000:
    lod=ob.modifiers.new('Clean_ret topology_geometry_LOD','DECIMATE')
    lod.ratio=140000/triangles;lod.use_collapse_triangulate=True
    bpy.ops.object.modifier_apply(modifier=lod.name)
mesh=ob.data;mesh.materials.clear();mesh.materials.append(original_material)
mesh.validate(clean_customdata=True);mesh.update()
new_uv=mesh.uv_layers.new(name='Transferred_source_UV')

def projected_bary(point,a,b,c):
    v0=b-a;v1=c-a;v2=point-a
    d00=v0.dot(v0);d01=v0.dot(v1);d11=v1.dot(v1)
    denom=d00*d11-d01*d01
    if abs(denom)<1e-18:return (1/3,1/3,1/3)
    v=(d11*v2.dot(v0)-d01*v2.dot(v1))/denom
    w=(d00*v2.dot(v1)-d01*v2.dot(v0))/denom
    values=[max(0,min(1,x)) for x in (1-v-w,v,w)]
    total=sum(values)
    return tuple(x/total for x in values) if total else (1/3,1/3,1/3)

# Each new small face projects onto ONE real source triangle. This preserves
# atlas chart continuity, avoiding interpolated spans across unrelated charts.
distances=[]
for f in mesh.polygons:
    center=sum((mesh.vertices[i].co for i in f.vertices),Vector())/len(f.vertices)
    loc,normal,index,distance=tree.find_nearest(center)
    if index is None: raise RuntimeError('No source surface for repaired polygon')
    distances.append(distance)
    a,b,c=(coords[i] for i in faces[index]);u0,u1,u2=face_uv[index]
    for li in f.loop_indices:
        point=mesh.vertices[mesh.loops[li].vertex_index].co
        aa,bb,cc=projected_bary(point,a,b,c)
        new_uv.data[li].uv=u0*aa+u1*bb+u2*cc
    f.use_smooth=True
mesh.update()
groups={name:ob.vertex_groups.new(name=name) for name in rig.data.bones.keys()}
assigned=[]
for v in mesh.vertices:
    w={};near=kd.find_n(v.co,4)
    norm=sum(1/max(d,.0002)**2 for _,_,d in near)
    for _,i,d in near:
        factor=1/max(d,.0002)**2/norm
        for name,weight in old_weights[i].items():w[name]=w.get(name,0)+factor*weight
    assigned.append(w)
adjacency=[[] for v in mesh.vertices]
for edge in mesh.edges:
    i,j=edge.vertices;adjacency[i].append(j);adjacency[j].append(i)
for _ in range(2):
    updated=[]
    for i,w in enumerate(assigned):
        blend={k:v*.75 for k,v in w.items()}
        for j in adjacency[i]:
            for k,v in assigned[j].items():blend[k]=blend.get(k,0)+v*.25/max(1,len(adjacency[i]))
        updated.append(blend)
    assigned=updated
for vertex,w in zip(mesh.vertices,assigned):
    total=sum(w.values())
    for name,weight in w.items():
        if weight>1e-6:groups[name].add([vertex.index],weight/total,'REPLACE')
modifier=ob.modifiers.new('Transferred_continuous_skin','ARMATURE');modifier.object=rig
ob.parent=rig;ob.name='titan_bloom_Repaired_Native_Surface'
for img in bpy.data.images:
    if img.type=='IMAGE' and img.size[0]>1:
        # Library-appended unused high-resolution maps need not be exported.
        if not img.has_data:
            try: img.reload()
            except RuntimeError: pass
        if img.has_data:img.pack()
bpy.ops.wm.save_as_mainfile(filepath=str(work/'game.blend'))
# Also preserve the newly editable clean high surface, with real packed atlas.
shutil.copy2(work/'game.blend',work/'repaired-high.blend')
bpy.ops.object.select_all(action='SELECT')
temp=work/'repaired-export.glb'
bpy.ops.export_scene.gltf(filepath=str(temp),export_format='GLB',export_apply=False,
    export_materials='EXPORT',export_extras=True,export_yup=True,export_animations=True,
    export_nla_strips=True,export_anim_single_armature=True,export_cameras=False,export_lights=False)
payload=temp.read_bytes();temp.replace(out/'titan_bloom.glb')
count=struct.unpack_from('<I',payload,12)[0];gltf=json.loads(payload[20:20+count])
sha=hashlib.sha256(payload).hexdigest()
prov=json.loads((out/'provenance.json').read_text())
prov.update(glb_sha256=sha,glb_bytes=len(payload),game_triangles=sum(gltf['accessors'][p['indices']]['count']//3 for m in gltf['meshes'] for p in m['primitives']),
    material_count=len(gltf.get('materials',[])),embedded_images=len(gltf.get('images',[])),
    creator='Actual TRELLIS closed-v2 volume repaired in Blender with 6.2mm voxel continuous-surface retopology, gentle surface polish, nearest-source triangle UV transfer and original six-bone skin/IdleLoop/MoveLoop transfer. No primitive replacement or further inference.',
    repaired_high_source=str(work/'repaired-high.blend'),
    topology_repair={'voxel_size_m':.0062,'source_uv_transfer':'one source triangle per new polygon, barycentric clipped projection; original embedded atlas retained',
    'skin_transfer':'nearest-four native source weights plus two adjacency blend passes','max_surface_projection_distance_m':max(distances),
    'rejected_polish_archive':str(archive)},quality_status='candidate: direct multi-view/motion and Godot QA required')
prov.pop('authored_finish',None)
(out/'provenance.json').write_text(json.dumps(prov,indent=2)+'\n')
path=ROOT/'art/models/native_monsters.json';manifest=json.loads(path.read_text())
manifest['monsters']['titan_bloom'].update(glb_sha256=sha,ready=False)
temp=path.with_suffix('.tmp');temp.write_text(json.dumps(manifest,indent=2)+'\n');temp.replace(path)
print('TITAN_NATIVE_TOPOLOGY_REPAIR',sha,prov['game_triangles'],len(mesh.vertices),max(distances))
