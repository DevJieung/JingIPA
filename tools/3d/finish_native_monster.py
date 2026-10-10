#!/usr/bin/env python3
"""Retain reconstructed creature surface/UV, fit body-specific skin and clips.

This produces a candidate, never publishes ready. Editable high/game .blend
sources remain in build; actual multi-view and Godot motion QA are required.
Bone landmarks use normalized Blender (x,y,height), not hero pivot axes.
"""
import argparse,fcntl,hashlib,json,math,os,statistics,struct,sys
from pathlib import Path
import bpy,bmesh
from mathutils import Matrix,Vector

ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--id',required=True);p.add_argument('--input',required=True)
p.add_argument('--replace-manual',action='store_true',help='Explicitly replace a preserved manual candidate; normal batch must not overwrite it')
a=p.parse_args(sys.argv[sys.argv.index('--')+1:] if '--'in sys.argv else [])
existing_provenance=ROOT/'art/models/monsters'/a.id/'provenance.json'
if existing_provenance.exists() and json.loads(existing_provenance.read_text()).get('topology_repair') and not a.replace_manual:
    raise SystemExit('Manual native topology repair is preserved. Use its recorded repair tool, not the generic batch finisher. Explicit --replace-manual is only for an intentional replacement experiment.')
spec=json.loads((ROOT/'tools/3d/native_monster_specs.json').read_text())['monsters'][a.id]
shape=spec['shape'];H=float(spec['height']);src=Path(a.input).resolve()
work=ROOT/'build/character-3d/monster-source'/a.id;out=ROOT/'art/models/monsters'/a.id
work.mkdir(parents=True,exist_ok=True);out.mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(src));objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
if not objects:raise ValueError('No actual reconstructed mesh')
turn=Matrix.Rotation(math.pi if spec.get('front','-y')=='-y' else 0,4,'Z')
raw_triangles=sum(sum(len(f.vertices)-2 for f in o.data.polygons)for o in objects)
for ob in objects:
    ob.data.transform(turn@ob.matrix_world);ob.matrix_world=Matrix.Identity(4);ob.parent=None
    bpy.context.view_layer.objects.active=ob
    if ob.data.has_custom_normals:bpy.ops.mesh.customdata_custom_splitnormals_clear()
    ob.data.use_auto_smooth=False
for ob in list(bpy.context.scene.objects):
    if ob not in objects:bpy.data.objects.remove(ob,do_unlink=True)
points=[v.co for ob in objects for v in ob.data.vertices]
lo=Vector([min(v[i]for v in points)for i in range(3)]);hi=Vector([max(v[i]for v in points)for i in range(3)])
center=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z));scale=H/(hi.z-lo.z)
for ob in objects:
    for v in ob.data.vertices:v.co=(v.co-center)*scale
    bm=bmesh.new();bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=H*1e-6)
    # Preserve winding of retained nonmanifold source faces.
    bm.normal_update();bm.to_mesh(ob.data);bm.free()
    for polygon in ob.data.polygons:polygon.use_smooth=True
    ob.data.update()
bpy.ops.wm.save_as_mainfile(filepath=str(work/'high.blend'))
ratio=min(1,spec['triangles']/max(raw_triangles,1))
for ob in objects:
    if ratio<.999:
        bpy.context.view_layer.objects.active=ob
        mod=ob.modifiers.new('Creature_UV_retained_LOD','DECIMATE');mod.ratio=ratio;mod.use_collapse_triangulate=True
        bpy.ops.object.modifier_apply(modifier=mod.name)
    for polygon in ob.data.polygons:polygon.use_smooth=True
    ob.data.update()
source_hash=hashlib.sha256(src.read_bytes()).hexdigest();texdir=work/'textures';texdir.mkdir(exist_ok=True)
for i,image in enumerate(list(bpy.data.images)):
    if image.type!='IMAGE'or image.size[0]<2:continue
    if max(image.size)>spec['texture']:image.scale(spec['texture'],spec['texture'])
    name=a.id+'_Texture_'+source_hash[:8]+'_'+str(i)
    image.filepath_raw=str(texdir/(name+'.png'));image.file_format='PNG';image.save();image.name=name;image.pack()
for mat in bpy.data.materials:
    if not mat.use_nodes:continue
    shader=next((n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
    if shader is None:continue
    for key,value in [('Metallic',spec.get('metallic',0.0)),('Roughness',.80),('Specular IOR Level',.18),('Coat Weight',0)]:
        socket=shader.inputs.get(key)
        if socket:
            for link in list(socket.links):mat.node_tree.links.remove(link)
            socket.default_value=value

# Repair only explicitly identified elemental surfaces. Keep the reconstructed
# UV/albedo on all other faces; do not paint the whole creature or rebake it.
for region in spec.get('surface_material_regions',[]):
    mat=bpy.data.materials.new(a.id+'_'+region['name']);mat.use_nodes=True
    shader=mat.node_tree.nodes['Principled BSDF']
    shader.inputs['Base Color'].default_value=tuple(region['color'])
    shader.inputs['Roughness'].default_value=.80
    shader.inputs['Metallic'].default_value=0
    shader.inputs['Emission Color'].default_value=tuple(region.get('emission',region['color']))
    shader.inputs['Emission Strength'].default_value=float(region.get('emission_strength',0))
    for ob in objects:
        ob.data.materials.append(mat);index=len(ob.data.materials)-1
        for polygon in ob.data.polygons:
            point=polygon.center/H
            if all(region['min'][i]<=point[i]<=region['max'][i]for i in range(3)):
                polygon.material_index=index

# Templates describe creature anatomy, not universal humanoid joints. Landmarks
# may be overridden only after inspecting this creature's actual reconstructed
# surface. All bones are independent absolute-transform controls for easy clips.
landmarks={'Body':(0,0,.35)}
if shape=='blob':landmarks.update(Base=(0,0,0),Crown=(0,0,.70))
elif shape=='quadruped':
    landmarks.update(Head=(0,.23,.67),Tail=(0,-.32,.44),
        FrontL=(-.16,.18,.24),FrontR=(.16,.18,.24),RearL=(-.16,-.18,.24),RearR=(.16,-.18,.24))
elif shape in ['dragon','ray']:
    landmarks.update(Head=(0,.12,.72),WingL=(-.20,0,.62),WingR=(.20,0,.62),Tail=(0,-.28,.25))
    if shape=='dragon':landmarks.update(ArmL=(-.18,.03,.54),ArmR=(.18,.03,.54),LegL=(-.13,0,.22),LegR=(.13,0,.22))
elif shape=='serpent':landmarks.update(Neck=(0,.04,.52),Head=(0,.12,.80),Tail=(0,-.20,.17),FinL=(-.18,0,.55),FinR=(.18,0,.55))
elif shape=='jelly':landmarks.update(Cap=(0,0,.78),TentacleL=(-.14,0,.30),TentacleR=(.14,0,.30))
elif shape=='idol':landmarks.update(Crown=(0,0,.83))
elif shape=='plant':landmarks.update(Maw=(0,.12,.70),VineL=(-.20,0,.55),VineR=(.20,0,.55),RootL=(-.16,0,.15),RootR=(.16,0,.15))
else:
    landmarks.update(Head=(0,0,.72),LegL=(-.12,0,.23),LegR=(.12,0,.23),ArmL=(-.20,0,.52),ArmR=(.20,0,.52))
landmarks.update({k:tuple(v)for k,v in spec.get('rig_landmarks',{}).items()})
starts={k:Vector(v)*H for k,v in landmarks.items()}
data=bpy.data.armatures.new(a.id+'_CreatureRig');rig=bpy.data.objects.new('CreatureRig',data)
bpy.context.collection.objects.link(rig);bpy.ops.object.select_all(action='DESELECT');rig.select_set(True)
bpy.context.view_layer.objects.active=rig;bpy.ops.object.mode_set(mode='EDIT')
for name,point in starts.items():
    bone=data.edit_bones.new(name);bone.head=point;bone.tail=point+Vector((0,0,H*.055))
bpy.ops.object.mode_set(mode='OBJECT')
def smooth(low,high,v):
    t=max(0,min(1,(v-low)/(high-low)));return t*t*(3-2*t)
def pair(weights,side,amount):
    amount=max(0,min(1,amount));weights={k:v*(1-amount)for k,v in weights.items()}
    weights[side]=weights.get(side,0)+amount;return weights
for ob in objects:
    groups={name:ob.vertex_groups.new(name=name)for name in starts};assigned=[]
    for vertex in ob.data.vertices:
        x,y,z=vertex.co/H;side='R'if x>=0 else'L';w={'Body':1.0}
        if shape=='blob':
            crown=smooth(.36,.82,z);base=1-smooth(.05,.20,z)
            w={'Base':base,'Body':(1-base)*(1-crown),'Crown':(1-base)*crown}
        elif shape=='quadruped':
            leg=(1-smooth(.24,.48,z))*smooth(.07,.16,abs(x))
            w=pair(w,('Front'if y>0 else'Rear')+side,leg)
            if z>.40:w=pair(w,'Head',smooth(.14,.28,y)*smooth(.42,.60,z))
            if y<-.23:w=pair(w,'Tail',smooth(.23,.36,-y)*(1-smooth(.62,.80,z)))
        elif shape in ['dragon','ray']:
            wing=smooth(.20,.39,abs(x))*smooth(.26,.48,z)
            w=pair(w,'Wing'+side,wing)
            if abs(x)<.26:w=pair(w,'Head',smooth(.69,.86,z))
            if y<-.22:w=pair(w,'Tail',smooth(.22,.39,-y)*(1-smooth(.36,.60,z)))
            if shape=='dragon':
                w=pair(w,'Leg'+side,(1-smooth(.23,.39,z))*smooth(.04,.10,abs(x)))
                w=pair(w,'Arm'+side,smooth(.10,.23,abs(x))*(1-smooth(.56,.67,z))*smooth(.35,.45,z)*smooth(.015,.12,y))
        elif shape=='serpent':
            w=pair(w,'Neck',smooth(.35,.60,z));w=pair(w,'Head',smooth(.73,.88,z))
            w=pair(w,'Tail',(1-smooth(.12,.32,z))*smooth(.10,.25,-y))
            w=pair(w,'Fin'+side,smooth(.14,.27,abs(x))*smooth(.36,.49,z)*(1-smooth(.62,.77,z)))
        elif shape=='jelly':
            w=pair(w,'Cap',smooth(.58,.76,z));w=pair(w,'Tentacle'+side,1-smooth(.28,.55,z))
        elif shape=='idol':w=pair(w,'Crown',smooth(.74,.87,z))
        elif shape=='plant':
            w=pair(w,'Root'+side,(1-smooth(.15,.32,z))*smooth(.10,.23,abs(x)))
            w=pair(w,'Vine'+side,smooth(.19,.38,abs(x))*smooth(.35,.60,z))
            if abs(x)<.34:w=pair(w,'Maw',smooth(.58,.79,z))
        else:
            w=pair(w,'Head',smooth(.65,.78,z))
            w=pair(w,'Leg'+side,(1-smooth(.21,.36,z))*smooth(.045,.09,abs(x)))
            w=pair(w,'Arm'+side,smooth(.12,.26,abs(x))*smooth(.25,.40,z)*(1-smooth(.65,.77,z)))
        for region in spec.get('rigid_regions',[]):
            if all(region['min'][i]<=vertex.co[i]/H<=region['max'][i]for i in range(3)):w={region['bone']:1.0}
        assigned.append(w)
    adjacency=[[]for v in ob.data.vertices]
    for edge in ob.data.edges:
        i,j=edge.vertices;adjacency[i].append(j);adjacency[j].append(i)
    for _ in range(int(spec.get('seam_blend_iterations',3))):
        updated=[]
        for i,w in enumerate(assigned):
            if not adjacency[i]:updated.append(w);continue
            blend={k:v*.75 for k,v in w.items()}
            for j in adjacency[i]:
                for k,v in assigned[j].items():blend[k]=blend.get(k,0)+v*.25/len(adjacency[i])
            updated.append(blend)
        assigned=updated
    for vertex,w in zip(ob.data.vertices,assigned):
        for name,weight in w.items():
            if weight>.00001:groups[name].add([vertex.index],weight,'REPLACE')
    mod=ob.modifiers.new('Creature_continuous_skin','ARMATURE');mod.object=rig;ob.parent=rig;ob.name=a.id+'_Native_Surface'

# Clip authoring is shared with tools/3d/author_monster_motion.py so a re-finished
# creature receives the same production clip set (IdleLoop/MoveLoop/Attack/Die).
sys.path.insert(0,str(Path(__file__).resolve().parent));import monster_motion
motion_params=monster_motion.motion_params(spec);motion_meta=monster_motion.author_clips(rig,spec,H,motion_params)
scene=bpy.context.scene
scene.frame_set(0);bpy.ops.wm.save_as_mainfile(filepath=str(work/'game.blend'))
bpy.ops.object.select_all(action='SELECT');temp=work/'runtime-export.glb'
bpy.ops.export_scene.gltf(filepath=str(temp),export_format='GLB',export_apply=False,export_materials='EXPORT',export_extras=True,export_yup=True,export_animations=True,export_nla_strips=True,export_anim_single_armature=True,export_cameras=False,export_lights=False)
payload=temp.read_bytes();dest=out/(a.id+'.glb');temp.replace(dest)
size=struct.unpack_from('<I',payload,12)[0];gltf=json.loads(payload[20:20+size]);sha=hashlib.sha256(payload).hexdigest()
provenance={'id':a.id,'creator':'Actual TRELLIS creature surface retained; Blender UV-preserving LOD, body-specific skin and the shared production clip set (IdleLoop/MoveLoop/Attack/Die)','input':str(src),'source_sha256':source_hash,'raw_triangles':raw_triangles,'game_triangles':sum(sum(len(f.vertices)-2 for f in o.data.polygons)for o in objects),'game_texture_max':spec['texture'],'height':H,'shape':shape,'rig':list(starts),'clips':[v['name']for v in gltf.get('animations',[])],'mesh_count':len(gltf.get('meshes',[])),'material_count':len(gltf.get('materials',[])),'embedded_images':len(gltf.get('images',[])),'high_source':str(work/'high.blend'),'game_source':str(work/'game.blend'),'glb_sha256':sha,'glb_bytes':len(payload),'motion':motion_meta,'quality_status':'candidate; actual multi-view/motion/Godot QA required','runtime_budget_basis':'41 monsters plus12 heroes. Device FPS unmeasured.'}
(out/'provenance.json').write_text(json.dumps(provenance,indent=2)+'\n')
path=ROOT/'art/models/native_monsters.json';lock=(ROOT/'build/character-3d/monster-manifest.lock').open('a');fcntl.flock(lock,fcntl.LOCK_EX)
manifest=json.loads(path.read_text());manifest['monsters'][a.id]={'path':f'res://art/models/monsters/{a.id}/{a.id}.glb','rig':len(starts),'height':H,'shape':shape,'metallic':spec.get('metallic',0.0),'clips':provenance['clips'],'glb_sha256':sha,'motion':monster_motion.runtime_motion(spec,motion_params),'ready':False}
if a.id in manifest['ready_ids']:manifest['ready_ids'].remove(a.id)
tmp=path.with_suffix('.tmp.'+str(os.getpid()));tmp.write_text(json.dumps(manifest,indent=2)+'\n');tmp.replace(path)
fcntl.flock(lock,fcntl.LOCK_UN);lock.close();print('NATIVE_MONSTER_CANDIDATE',a.id,sha,provenance['game_triangles'])
