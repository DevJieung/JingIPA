#!/usr/bin/env python3
"""Prepare actual generated geometry for game skin/motion; no primitive body.

bl -b --factory-startup --python tools/3d/finish_native_character.py -- \
  --id echo --input build/character-3d/raw-v2/echo/model.glb

Raw and editable high sources are retained. Game UV-preserving LOD/texture
resizing is a candidate requiring actual visual QA before ready_ids publication.
"""
import argparse,hashlib,json,math,struct,sys,statistics,heapq
from pathlib import Path
import bpy,bmesh
from mathutils import Vector,Matrix,kdtree

ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--id',required=True);p.add_argument('--input',required=True)
p.add_argument('--triangles',type=int,default=55000);p.add_argument('--texture',type=int,default=1024)
p.add_argument('--front',choices=['+y','-y'],default='-y');p.add_argument('--publish',action='store_true')
a=p.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
if a.id=='limne':raise ValueError('Accepted Limne must remain unchanged')
specs=json.loads((ROOT/'tools/3d/native_visual_specs.json').read_text())['heroes']
spec=specs[a.id];height=float(spec.get('height',1.65));kind=spec['attack'];build=spec.get('build','normal')
a_pose=str(spec.get('bind_pose','')).startswith('a_pose')
src=Path(a.input).resolve();out=ROOT/'art/models'/a.id;work=ROOT/'build/character-3d/source'/a.id
out.mkdir(parents=True,exist_ok=True);work.mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(src))
objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
if not objects:raise ValueError('Input has no actual geometry')
raw_tris=sum(sum(len(f.vertices)-2 for f in o.data.polygons) for o in objects)
turn=Matrix.Rotation(math.pi if a.front=='-y' else 0,4,'Z')
for ob in objects:
    ob.data.transform(turn@ob.matrix_world);ob.matrix_world=Matrix.Identity(4);ob.parent=None
    bpy.context.view_layer.objects.active=ob
    if ob.data.has_custom_normals:bpy.ops.mesh.customdata_custom_splitnormals_clear()
    ob.data.use_auto_smooth=False
for ob in list(bpy.context.scene.objects):
    if ob not in objects:bpy.data.objects.remove(ob,do_unlink=True)
points=[v.co for ob in objects for v in ob.data.vertices]
lo=Vector([min(v[i] for v in points) for i in range(3)]);hi=Vector([max(v[i] for v in points) for i in range(3)])
raw_h=hi.z-lo.z
head=[v for v in points if v.z>lo.z+raw_h*.75]
cx=statistics.median(v.x for v in head)
trunk=[v for v in points if lo.z+raw_h*.42<v.z<lo.z+raw_h*.67 and abs(v.x-cx)<raw_h*.11]
cy=statistics.median(v.y for v in trunk) if trunk else (lo.y+hi.y)/2
center=Vector((cx,cy,lo.z));scale=height/raw_h
for ob in objects:
    for v in ob.data.vertices:v.co=(v.co-center)*scale
    bm=bmesh.new();bm.from_mesh(ob.data)
    # Weld exact coincident UV-chart geometry, keeping corner UVs and winding.
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=height*0.000001)
    bm.normal_update();bm.to_mesh(ob.data);bm.free()
    for f in ob.data.polygons:f.use_smooth=True
    ob.data.update()
def smooth(a,b,x):
    t=max(0,min(1,(x-a)/(b-a)));return t*t*(3-2*t)
# Correct the small reconstruction sole offset separately on each side.
for sign in [-1,1]:
    boot=[v for ob in objects for v in ob.data.vertices if v.co.z<height*.18 and v.co.x*sign>0]
    bottom=min((v.co.z for v in boot),default=0)
    if 0<bottom<height*.06:
        for ob in objects:
            for v in ob.data.vertices:
                if v.co.x*sign>0:v.co.z-=bottom*(1-smooth(height*.16,height*.32,v.co.z))
bpy.ops.wm.save_as_mainfile(filepath=str(work/'high.blend'))
# Moderate UV-preserving LOD. No atlas rebake or broad coordinate deletion.
ratio=min(1,a.triangles/max(raw_tris,1))
for ob in objects:
    if ratio<.999:
        bpy.context.view_layer.objects.active=ob
        mod=ob.modifiers.new('UV_preserving_game_LOD','DECIMATE');mod.ratio=ratio;mod.use_collapse_triangulate=True
        bpy.ops.object.modifier_apply(modifier=mod.name)
    for f in ob.data.polygons:f.use_smooth=True
    ob.data.update()
source_hash=hashlib.sha256(src.read_bytes()).hexdigest()
texture_folder=work/'textures';texture_folder.mkdir(exist_ok=True)
for texture_index,image in enumerate(list(bpy.data.images)):
    if image.type!='IMAGE' or image.size[0]<2:continue
    if max(image.size)>a.texture:image.scale(a.texture,a.texture)
    texture_name=a.id+'_Texture_'+source_hash[:8]+'_'+str(texture_index)
    # Persist pixels before renaming a packed glTF image; Blender's image
    # collection reorders on ID changes, so iterate a snapshot and pack PNGs.
    image.filepath_raw=str(texture_folder/(texture_name+'.png'));image.file_format='PNG';image.save()
    image.name=texture_name
    image.pack()
for mat in bpy.data.materials:
    if not mat.use_nodes:continue
    principled=next((n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
    if principled is None:continue
    for name,value in [('Metallic',.12 if build in ['heavy','automaton'] else 0),('Roughness',.84),('Specular IOR Level',.16),('Coat Weight',0)]:
        socket=principled.inputs.get(name)
        if socket is None:continue
        for link in list(socket.links):mat.node_tree.links.remove(link)
        socket.default_value=value

# A reconstructed transparent reactor may be an empty opening. Author only
# the machine lens inside its retained rim, preserving the native body/armor.
for lens in spec.get('reactor_lenses',[]):
    center=Vector(lens['center'])*height;radius=float(lens['radius'])*height
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=12,radius=radius,location=center)
    ob=bpy.context.object;ob.name='NativeReactorLens'
    ob.scale=(1,float(lens.get('depth',.3)),1)
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    for f in ob.data.polygons:f.use_smooth=True
    mat=bpy.data.materials.new('NativeReactorAmber');mat.use_nodes=True
    shader=mat.node_tree.nodes['Principled BSDF'];shader.inputs['Base Color'].default_value=(1,.30,.012,1)
    shader.inputs['Roughness'].default_value=.54;shader.inputs['Metallic'].default_value=.08
    shader.inputs['Emission Color'].default_value=(1,.16,.003,1);shader.inputs['Emission Strength'].default_value=.18
    ob.data.materials.append(mat);objects.append(ob)

# Character-scaled roots retain the game's five direct control pivots.
width=1.20 if build=='heavy' else .88 if build=='slim' else 1.0
arm_x=height*.205*width;shoulder=height*.64;elbow=height*.50;wrist=height*.395
starts={'Body':(0,0,0),'ArmL':(-arm_x,shoulder,0),'ArmR':(arm_x,shoulder,0),
        'LegL':(-height*.09*width,height*.29,0),'LegR':(height*.09*width,height*.29,0),
        'ForearmL':(-arm_x,elbow,-height*.06),'ForearmR':(arm_x,elbow,-height*.06),
        'HandL':(-arm_x,wrist,-height*.09),'HandR':(arm_x,wrist,-height*.09)}
if a_pose:
    for sign,side in [(-1,'L'),(1,'R')]:
        starts['Arm'+side]=(sign*height*.16*width,height*.635,0)
        starts['Forearm'+side]=(sign*height*.27*width,height*.515,0)
        starts['Hand'+side]=(sign*height*.36*width,height*.400,0)
for name,point in spec.get('pivots',{}).items():starts[name]=tuple(v*height for v in point)
for region in spec.get('rigid_regions',[]):
    if region['bone'].startswith('Weapon'):
        side=region['bone'][-1];starts[region['bone']]=starts['Hand'+side]
for name,mount in spec.get('mounted_weapons',{}).items():
    starts[name]=tuple(v*height for v in mount['point'])
def xyz(point):return Vector((point[0],-point[2],point[1]))
data=bpy.data.armatures.new(a.id+'_NativeSkin');rig=bpy.data.objects.new('NativeSkin',data)
bpy.context.collection.objects.link(rig);bpy.context.view_layer.objects.active=rig;rig.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
for name,start in starts.items():
    bone=data.edit_bones.new('Skin'+name);bone.head=xyz(start)
    bone.tail=bone.head+Vector((0,0,height*(.22 if name=='Body' else -.10)))
bpy.ops.object.mode_set(mode='OBJECT')
def surface_distances(mesh,points,radius=None):
    """Shortest surface paths separate a glove from adjacent thigh/pouches.

    The generated surface is retained intact. Disconnected islands fall back to
    the spatial envelope; this is skin selection, never geometry deletion.
    """
    kd=kdtree.KDTree(len(mesh.vertices))
    for v in mesh.vertices:kd.insert(v.co,v.index)
    kd.balance();graph=[[] for v in mesh.vertices]
    for edge in mesh.edges:
        i,j=edge.vertices;d=(mesh.vertices[i].co-mesh.vertices[j].co).length
        graph[i].append((j,d));graph[j].append((i,d))
    distances=[math.inf]*len(mesh.vertices);queue=[]
    for point in points:
        neighbours=kd.find_range(Vector(point),height*.060 if radius is None else radius)
        if not neighbours:neighbours=[kd.find(Vector(point))]
        for _,i,d in neighbours:
            distances[i]=0;heapq.heappush(queue,(0,i))
    while queue:
        d,i=heapq.heappop(queue)
        if d>distances[i]:continue
        for j,length in graph[i]:
            new=d+length
            if new<distances[j]:distances[j]=new;heapq.heappush(queue,(new,j))
    return distances
for ob in objects:
    groups={name:ob.vertex_groups.new(name='Skin'+name) for name in starts}
    assigned=[]
    semantic={}
    if spec.get('skin_regions') or spec.get('preserve_dark_regions') or spec.get('bind_color_regions'):
        # Corner UV sampling follows Blender's bottom-left image coordinates.
        # Semantic selection is restricted to authored ID-specific regions.
        colors=[[0.,0.,0.,0] for v in ob.data.vertices]
        caches={}
        for polygon in ob.data.polygons:
            mat=ob.data.materials[polygon.material_index]
            shader=next((n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None) if mat and mat.use_nodes else None
            link=shader.inputs['Base Color'].links[0] if shader and shader.inputs['Base Color'].links else None
            image=getattr(link.from_node,'image',None) if link else None
            if not image or not ob.data.uv_layers.active:continue
            if image.name not in caches:caches[image.name]=(list(image.pixels),image.size[0],image.size[1])
            pixels,iw,ih=caches[image.name]
            for loop_index in polygon.loop_indices:
                uv=ob.data.uv_layers.active.data[loop_index].uv
                px=max(0,min(iw-1,int(uv.x*iw)));py=max(0,min(ih-1,int(uv.y*ih)))
                vid=ob.data.loops[loop_index].vertex_index;target=colors[vid]
                for channel in range(3):target[channel]+=pixels[(py*iw+px)*4+channel]
                target[3]+=1
        for vertex in ob.data.vertices:
            color=colors[vertex.index]
            if not color[3]:continue
            r,g,b=[v/color[3] for v in color[:3]]
            for region in spec.get('preserve_dark_regions',[]):
                saturation=(max(r,g,b)-min(r,g,b))/max(max(r,g,b),.001)
                if all(region['min'][n]*height<=vertex.co[n]<=region['max'][n]*height for n in range(3)) and max(r,g,b)<region.get('maximum',.20) and saturation<region.get('saturation_maximum',.35):semantic[vertex.index]='Body'
            for region in spec.get('skin_regions',[]):
                if all(region['min'][n]*height<=vertex.co[n]<=region['max'][n]*height for n in range(3)) and r>1.18*g and g>1.18*b and r>.12:semantic[vertex.index]=region['bone']
            for region in spec.get('bind_color_regions',[]):
                if not all(region['min'][n]*height<=vertex.co[n]<=region['max'][n]*height for n in range(3)):continue
                if region['color']=='purple' and r>g*1.15 and b>g*1.25 and b>.07:
                    semantic[vertex.index]=region['bone']
    surface={}
    equipment={name:surface_distances(ob.data,[Vector(p)*height for p in points],height*.035)
        for name,points in spec.get('rigid_seed_points',{}).items()}
    if build!='automaton':
        body_seeds=[(x*height,y*height,z*height) for x in [-.07,0,.07] for y in [-.04,.13] for z in [.37,.48,.57,.63,.80]]
        body_seeds += [(s*.12*height,.055*height,z*height) for s in [-1,1] for z in [.15,.27,.36]]
        surface['Body']=surface_distances(ob.data,body_seeds)
        for side in ['L','R']:
            seeds=[xyz(starts[n+side]) for n in ['Forearm','Hand']]
            shoulder_seed=xyz(starts['Arm'+side])+Vector(((-1 if side=='L' else 1)*height*.025,0,-height*.035))
            finger_seed=xyz(starts['Hand'+side])+Vector(((-1 if side=='L' else 1)*height*.015,height*.02,-height*.055))
            seeds.extend([shoulder_seed,finger_seed])
            surface[side]=surface_distances(ob.data,seeds)
    for v in ob.data.vertices:
        x,y,z=v.co;weights={'Body':1.0}
        if z<height*.35:
            leg=1-smooth(height*.27,height*.35,z)
            weights={'Body':1-leg,'LegR' if x>=0 else 'LegL':leg}
        min_arm=float(spec.get('arm_min',.305))
        if height*min_arm<z<height*.74:
            upper=smooth(height*.49,height*.64,z)
            inner=height*width*(.085+upper*.065)
            outer=height*width*(.145+upper*.075)
            arm=smooth(inner,outer,abs(x))
            arm*=1-smooth(height*.65,height*.74,z)
            if spec.get('arm_back_gate',True):arm*=smooth(-height*.14,-height*.035,y)
            arm*=smooth(height*min_arm,height*(min_arm+.025),z)
            if a_pose and z<height*.41:
                # The A-pose palms are outside the hips. A low generic arm
                # envelope otherwise assigns trouser fronts to a wrist.
                arm*=smooth(height*.225,height*.275,abs(x))
            side='R' if x>=0 else 'L'
            if surface and math.isfinite(surface[side][v.index]) and math.isfinite(surface['Body'][v.index]):
                arm*=smooth(-height*.02,height*.045,surface['Body'][v.index]-surface[side][v.index])
            if 'rigid_arm_outer' in spec and z<height*.58 and abs(x)>height*float(spec['rigid_arm_outer']):
                arm=1.0
            for region in spec.get('arm_force_regions',[]):
                if all(region['min'][n]*height<=v.co[n]<=region['max'][n]*height for n in range(3)):
                    arm=1.0;side=region['side']
            if arm>.0001:
                ez=starts['Forearm'+side][1];wz=starts['Hand'+side][1]
                lower=1-smooth(ez-height*.055,ez+height*.055,z)
                palm=1-smooth(wz-height*.025,wz+height*.045,z)
                weights={n:w*(1-arm) for n,w in weights.items()}
                weights['Arm'+side]=arm*(1-lower)
                weights['Forearm'+side]=arm*lower*(1-palm)
                weights['Hand'+side]=arm*lower*palm
        # Central garment and neck cannot be assigned to either arm simply
        # because the reconstructed surface has shortcuts through a strap.
        if abs(x)<height*.145 and height*.38<z:weights={'Body':1.0}
        if z>height*float(spec.get('head_start',.675)):weights={'Body':1.0}
        # The visible boot soles stay on the world plane. This anatomical
        # region is declared per character and excludes outer handheld gear.
        if z<height*float(spec.get('foot_fixed_height',.12)) and abs(x)<height*.23:
            weights={'LegR' if x>=0 else 'LegL':1.0}
        for region in spec.get('retain_body_regions',[]):
            if all(region['min'][n]*height<=v.co[n]<=region['max'][n]*height for n in range(3)):
                weights={'Body':1.0}
        # Authored ID-specific rigid equipment binding, without deleting any
        # retained body geometry. Coordinates are normalized by this height.
        for region in spec.get('rigid_regions',[]):
            low=region['min'];high=region['max']
            if all(low[n]*height<=v.co[n]<=high[n]*height for n in range(3)):
                weights={region['bone']:1.0}
        for name,distances in equipment.items():
            d=distances[v.index]
            others=[values[v.index] for values in surface.values()]
            if d<height*.27 and (not others or d<min(others)-height*.008):weights={name:1.0}
        if v.index in semantic:weights={semantic[v.index]:1.0}
        for name,weight in weights.items():
            if weight>.0001:groups[name].add([v.index],weight,'REPLACE')
        assigned.append(weights)
    # Blend pose influence over adjacent retained surface vertices so sleeves
    # and gauntlet boundaries do not become hard one-triangle hinges.
    adjacency=[[] for v in ob.data.vertices]
    for edge in ob.data.edges:
        i,j=edge.vertices;adjacency[i].append(j);adjacency[j].append(i)
    anatomical_weights=[dict(weights) for weights in assigned]
    for iteration in range(int(spec.get('seam_blend_iterations',5))):
        updated=[]
        for i,weights in enumerate(assigned):
            if (any(name.startswith('Weapon')for name in weights) and not spec.get('blend_rigid_seams')) or not adjacency[i]:updated.append(weights);continue
            neighbours=[assigned[j]for j in adjacency[i]if spec.get('blend_rigid_seams') or not any(n.startswith('Weapon')for n in assigned[j])]
            if not neighbours:updated.append(weights);continue
            blended={name:value*.65 for name,value in weights.items()}
            for near in neighbours:
                for name,value in near.items():blended[name]=blended.get(name,0)+value*.35/len(neighbours)
            updated.append(blended)
        assigned=updated
    for i,vertex in enumerate(ob.data.vertices):
        original=anatomical_weights[i]
        if i in semantic:
            assigned[i]=original
            continue
        if not set(original).issubset({'Body','LegL','LegR'}):continue
        if vertex.co.z<height*.12 and abs(vertex.co.x)<height*.23:
            assigned[i]=original
        elif a_pose and vertex.co.z<height*.40 and abs(vertex.co.x)<height*.215 and abs(vertex.co.y)<height*.14:
            assigned[i]=original
    for group in groups.values():group.remove(list(range(len(ob.data.vertices))))
    for i,weights in enumerate(assigned):
        for name,weight in weights.items():
            if weight>.0001:groups[name].add([i],weight,'REPLACE')
    mod=ob.modifiers.new('Native_clothing_skin','ARMATURE');mod.object=rig
    ob.parent=rig;ob.name=a.id+'_Retained_3D_Surface'
for name in ['Body','ArmL','ArmR','LegL','LegR']:
    control=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(control);control.location=xyz(starts[name])

# Root bones use absolute model-space deltas. Native authoring clips remain
# editable and are sampled by the read-only runtime visual event state.
C=Matrix.Rotation(math.pi/2,4,'X')
def around(point,rotation):
    p=Vector(point);m=rotation.to_4x4();m.translation=p-rotation@p;return m
def pose(bone,delta):
    rig.pose.bones[bone].matrix=C@delta@C.inverted()@rig.data.bones[bone].matrix_local
def authored_pose(time,amount):
    breath=math.sin(time*math.tau/3)*height*.005
    body=Matrix.Translation((math.sin(time*math.tau/6)*height*.0025,breath,0))
    body=body@around((0,height*.4,0),Matrix.Rotation(-amount*.03,3,'X'))
    pose('SkinBody',body)
    for sign,side in [(-1,'L'),(1,'R')]:
        lead=spec.get('lead_side','R')
        shoulder_angle=amount*((.98 if side==lead else .72) if kind=='bow' else .42 if kind=='rifle' else .36 if kind=='cast' else .56)
        if kind=='artillery':shoulder_angle=amount*.13
        if kind=='sword':shoulder_angle=amount*(.90 if side==lead else .18)
        arm_rotation=Matrix.Rotation(shoulder_angle,3,'X')
        if kind=='bow' and side!=lead:arm_rotation=Matrix.Rotation(amount*(.72 if side=='R' else -.72),3,'Y')@arm_rotation
        relax=float(spec.get('idle_inward_angle',0))*(1-amount*.7)*(-sign)
        arm_rotation=arm_rotation@Matrix.Rotation(relax,3,'Z')
        arm=Matrix.Translation((0,breath,0))@around(starts['Arm'+side],arm_rotation)
        bend=amount*((.20 if side==lead else .70) if kind=='bow' else .48 if kind=='rifle' else .32)
        if kind=='artillery':bend=amount*.18
        rotation=Matrix.Rotation(bend,3,'X')
        if kind=='bow' and side!=lead:rotation=Matrix.Rotation(amount*(.72 if side=='R' else -.72),3,'Y')@rotation
        fore=arm@around(starts['Forearm'+side],rotation)
        hand=fore
        side_gun=kind=='rifle' and (side==lead or side in spec.get('muzzle_axes_xyz',{}))
        if (kind=='bow' and side==lead) or side_gun:
            hand=fore@around(starts['Hand'+side],fore.to_3x3().inverted())
            if kind=='rifle':
                axis_data=spec.get('muzzle_axes_xyz',{}).get(side,spec.get('muzzle_axis_xyz'))
                if axis_data:
                    axis=Vector(axis_data).normalized()
                    target=axis.rotation_difference(Vector((0,0,-1)))
                    rotation=target.__class__().slerp(target,amount).to_matrix()
                else:rotation=Matrix.Rotation(amount*float(spec.get('weapon_aim_x',0)),3,'X')
                hand=hand@around(starts['Hand'+side],rotation)
        pose('SkinArm'+side,arm);pose('SkinForearm'+side,fore);pose('SkinHand'+side,hand)
        if 'Weapon'+side in starts:
            weapon=hand if kind in ['sword','tool','rifle'] or spec.get('weapon_follow_hand') else hand@around(starts['Hand'+side],hand.to_3x3().inverted())
            pose('SkinWeapon'+side,weapon)
        pose('SkinLeg'+side,Matrix.Identity(4))
    for name,mount in spec.get('mounted_weapons',{}).items():
        target=Vector(mount['axis_xyz']).normalized().rotation_difference(Vector((0,0,-1)))
        rotation=target.__class__().slerp(target,amount).to_matrix()
        pose('Skin'+name,body@around(starts[name],rotation))
rig.animation_data_create();scene=bpy.context.scene;scene.render.fps=30
for name,last in [('IdleLoop',180),('Attack',39)]:
    action=bpy.data.actions.new(name);rig.animation_data.action=action
    for frame in range(last+1):
        t=frame/30
        if name=='IdleLoop':amount=0
        elif t<=1:amount=smooth(.0,.78,t)
        else:amount=1-smooth(1,1.3,t)
        authored_pose(t,amount)
        for bone in rig.pose.bones:
            bone.rotation_mode='QUATERNION'
            for prop in ['location','rotation_quaternion','scale']:bone.keyframe_insert(data_path=prop,frame=frame,group=bone.name)
    for curve in action.fcurves:
        for key in curve.keyframe_points:key.interpolation='LINEAR'
    track=rig.animation_data.nla_tracks.new();track.name=name
    track.strips.new(name,0,action);track.mute=True
rig.animation_data.action=None
for bone in rig.pose.bones:bone.matrix_basis=Matrix.Identity(4)
scene.frame_set(0)
bpy.ops.wm.save_as_mainfile(filepath=str(work/'game.blend'))
bpy.ops.object.select_all(action='SELECT')
dest=out/(a.id+'.glb')
export_temp=work/'runtime-export.glb'
bpy.ops.export_scene.gltf(filepath=str(export_temp),export_format='GLB',export_apply=False,
    export_materials='EXPORT',export_extras=True,export_yup=True,export_animations=True,
    export_nla_strips=True,export_anim_single_armature=True,export_cameras=False,export_lights=False)
payload=export_temp.read_bytes();export_temp.replace(dest)
length=struct.unpack_from('<I',payload,12)[0];gltf=json.loads(payload[20:20+length])
triangles=sum(sum(len(f.vertices)-2 for f in ob.data.polygons) for ob in objects)
provenance={'id':a.id,'creator':'actual TRELLIS native surface retained; Blender UV-preserving LOD, game materials, continuous skin and authored clips',
    'input':str(src),'source_sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'raw_triangles':raw_tris,
    'game_triangles':triangles,'game_texture_max':a.texture,'mesh_count':len(gltf.get('meshes',[])),
    'material_count':len(gltf.get('materials',[])),'embedded_images':len(gltf.get('images',[])),
    'rig':list(starts),'clips':[v['name'] for v in gltf.get('animations',[])],
    'high_source':str(work/'high.blend'),'game_source':str(work/'game.blend'),'height':height,
    'glb_bytes':len(payload),'glb_sha256':hashlib.sha256(payload).hexdigest(),'quality_status':'candidate; actual visual QA required',
    'surface_strategy':'retained original UV/albedo; moderate collapse LOD and texture resize; no atlas rebake or broad source geometry cuts'}
(out/'provenance.json').write_text(json.dumps(provenance,indent=2)+'\n')
manifest_path=ROOT/'art/models/native_heroes.json'
import fcntl,os
manifest_lock=(ROOT/'build/character-3d/native-manifest.lock').open('a')
fcntl.flock(manifest_lock,fcntl.LOCK_EX)
manifest=json.loads(manifest_path.read_text())
effect={'bow':'#f2d99a','sword':'#bfd9ef','tool':'#ffe1a0','cast':'#ffbc58','rifle':'#9edfff'}.get(kind,'#bfeaff')
lead=spec.get('lead_side','R');lead_point=starts['Hand'+lead]
socket_bone='SkinWeapon'+lead if 'Weapon'+lead in starts else 'SkinHand'+lead
row={'path':f'res://art/models/{a.id}/{a.id}.glb','rig':len(starts),'attack':kind,'height':height,
    'aim_alignment':kind not in ['sword','tool'],
    'metallic':.12 if build in ['heavy','automaton'] else 0,'effect_color':effect,
    'sockets':[{'bone':socket_bone,'point':[lead_point[0],lead_point[1],lead_point[2]-height*.09]}],
    'glb_sha256':provenance['glb_sha256'],'ready':bool(a.publish)}
if spec.get('sockets'):
    row['sockets']=[dict(socket,point=[v*height for v in socket['point']]) for socket in spec['sockets']]
if kind=='artillery':
    # Back-mounted mortars keep their measured native axis; they do not
    # pretend to be a handheld horizontal rifle. This is a visual port only.
    for socket in row['sockets']:
        axis=Vector(socket['physical_axis']).normalized()
        socket['physical_axis']=list(axis)
        if 'rotation_xyz' not in socket:
            socket['rotation_xyz']=list(Vector((0,0,-1)).rotation_difference(axis).to_euler('XYZ'))
if kind=='rifle' and (spec.get('muzzle_axis_xyz') or spec.get('muzzle_axes_xyz') or spec.get('mounted_weapons')):
    for socket in row['sockets']:
        bone=socket['bone'].removeprefix('Skin')
        axis=spec.get('mounted_weapons',{}).get(bone,{}).get('axis_xyz')
        if axis is None:axis=spec.get('muzzle_axes_xyz',{}).get(bone[-1],spec.get('muzzle_axis_xyz'))
        if axis is not None and 'rotation_xyz' not in socket:
            aim=Vector(axis).normalized().rotation_difference(Vector((0,0,-1)))
            socket['rotation_xyz']=list(aim.inverted().to_euler())
elif kind=='rifle' and spec.get('weapon_aim_x'):
    if 'rotation_xyz' not in row['sockets'][0]:row['sockets'][0]['rotation_xyz']=[-float(spec['weapon_aim_x']),0,0]
manifest['heroes'][a.id]=row
if a.id in manifest['ready_ids']:manifest['ready_ids'].remove(a.id)
if a.publish:manifest['ready_ids'].append(a.id)
manifest_temp=manifest_path.with_suffix('.tmp.'+str(os.getpid()))
manifest_temp.write_text(json.dumps(manifest,indent=2)+'\n');manifest_temp.replace(manifest_path)
fcntl.flock(manifest_lock,fcntl.LOCK_UN);manifest_lock.close()
print('NATIVE_CANDIDATE',a.id,triangles,len(payload),provenance['glb_sha256'])
