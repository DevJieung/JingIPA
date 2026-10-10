#!/usr/bin/env python3
"""Restyle and rig the accepted Limne surface; no reconstruction or mesh cuts.

bl -b --factory-startup --python tools/3d/style_animate_limne.py
Source is the archived accepted .blend. Output retains its topology and UVs,
adds four independent elbow/hand skin bones and editable motion actions.
"""
import bpy
import math
import json
import hashlib
import struct
from pathlib import Path
from mathutils import Vector,Matrix,Euler

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'build/limne-game-motion'
OUT.mkdir(parents=True,exist_ok=True)
SOURCE=OUT/'before/limne_game.blend'
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
bpy.context.view_layer.objects.active=rig
bpy.ops.object.select_all(action='DESELECT');rig.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
for sign,side in [(-1,'L'),(1,'R')]:
    for part,start,end in [('Forearm',(sign*.34,.82,-.14),(sign*.347,.575,-.213)),
                            ('Hand',(sign*.347,.565,-.213),(sign*.347,.525,-.27))]:
        bone=rig.data.edit_bones.new('Skin'+part+side)
        bone.head=(start[0],-start[2],start[1]);bone.tail=(end[0],-end[2],end[1])
bpy.ops.object.mode_set(mode='OBJECT')
def smooth(a,b,x):
    t=max(0,min(1,(x-a)/(b-a)));return t*t*(3-2*t)
for ob in objects:
    for side in ['L','R']:
        arm=ob.vertex_groups.get('SkinArm'+side)
        if arm is None:continue
        fore=ob.vertex_groups.new(name='SkinForearm'+side)
        hand=ob.vertex_groups.new(name='SkinHand'+side)
        for v in ob.data.vertices:
            old=next((g.weight for g in v.groups if g.group==arm.index),0)
            if old<=0:continue
            if 'limne_hose_side' in ob:
                arm.remove([v.index]);hand.add([v.index],old,'REPLACE');continue
            is_hand=ob.name.startswith(('Closed_wrist','Curled_finger','Opposed_thumb'))
            # Manufactured nozzles follow the palm, while cloth/skin uses a
            # smooth elbow/wrist transition. The original source is retained.
            authored=ob.get('limne_control','')=='Arm'+side
            cuff=ob.name.startswith('Cuff_sewn')
            if authored and not is_hand and not cuff:
                arm.remove([v.index]);hand.add([v.index],old,'REPLACE');continue
            lower=1-smooth(.785,.865,v.co.z)
            palm=1-smooth(.595,.675,v.co.z)
            arm.add([v.index],old*(1-lower),'REPLACE')
            fore.add([v.index],old*lower*(1-palm),'REPLACE')
            hand.add([v.index],old*lower*palm,'REPLACE')

# Broad, painted game materials: cotton/rubber stay matte; brass remains
# readable but restrained. Original albedo/ORM images and UVs are unchanged.
for mat in bpy.data.materials:
    if not mat.use_nodes:continue
    p=mat.node_tree.nodes.get('Principled BSDF')
    if p is None:continue
    name=mat.name
    p.inputs['Specular IOR Level'].default_value=.16
    p.inputs['Coat Weight'].default_value=0
    if name=='Material_0' or any(n.type=='TEX_IMAGE' for n in mat.node_tree.nodes):
        # Retain the roughness texture, remove spurious AI-inferred metal from
        # workwear/boots. The atlas is still present for external editors.
        for link in list(p.inputs['Metallic'].links):mat.node_tree.links.remove(link)
        p.inputs['Metallic'].default_value=0
    if 'Hair' in name:
        p.inputs['Roughness'].default_value=.82
        p.inputs['Specular IOR Level'].default_value=.12
    elif 'Skin_' in name:
        p.inputs['Roughness'].default_value=.78
        p.inputs['Subsurface Weight'].default_value=.018
    elif any(tag in name for tag in ['Cobalt','Teal','NavyPants','Harness','rubber']):
        p.inputs['Roughness'].default_value=.86
    elif 'brass' in name or 'polished' in name:
        p.inputs['Metallic'].default_value=.48
        p.inputs['Roughness'].default_value=.54
    elif 'iris' in name:
        p.inputs['Roughness'].default_value=.35
        p.inputs['Coat Weight'].default_value=.12
    elif 'glass' in name:
        p.inputs['Roughness'].default_value=.30
    elif 'enamel' in name or 'water' in name:
        p.inputs['Roughness'].default_value=.57
for ob in objects:
    if not ob.data.color_attributes.get('SkinComplexion'):continue
    col=ob.data.color_attributes['SkinComplexion'].data
    for face in ob.data.polygons:
        if ob.data.materials[face.material_index].name!='Skin_soft_warm_volume':continue
        for i in face.loop_indices:col[i].color=(.67,.435,.325,1)

# Editable native actions mirror game/3d/limne_model.gd (idle, distance-driven
# walk cycle, stateless water-cannon attack). Bones are roots, so the five
# pre-existing direct controls keep their absolute contract. The runtime never
# plays these clips; they exist so the motion can be inspected and edited.
C=Matrix.Rotation(math.pi/2,4,'X')
HIP=.45;HEIGHT=1.63
def about(point,basis):
    return Matrix.Translation(Vector(point))@basis@Matrix.Translation(-Vector(point))
def converted(m):return C@m@C.inverted()
def godot_euler(x,y,z):
    # Godot Basis.from_euler default (YXZ: Z first, then X, then Y) == mathutils 'ZXY'.
    return Euler((x,y,z),'ZXY').to_matrix().to_4x4()
def smoothstep(a,b,x):return smooth(a,b,x)
def pose(time,age=9,wind=.6,phi=0.0,weight=0.0):
    wind=max(wind,.04)
    active=0<=age<wind+.22
    aim=smoothstep(0,.72,age/wind) if active and age<wind else 1-smoothstep(0,1,(age-wind)/.22) if active else 0
    release=max(0,age-wind)
    settle=1-smoothstep(0,1,release/.22)
    kick=math.exp(-release*18)*math.sin(release*math.tau*3.2)*settle if active and age>=wind else 0
    charge=max(0,min(1,(age/wind-.6)/.4)) if active and age<wind else 0
    tremble=math.sin(age*math.tau*12)*.0025*charge
    breath=math.sin(time*math.tau/3)*.008
    sway=math.sin(time*math.tau/6)
    look=.06*math.sin(max(0,min(1,(time-2.4)/2.2))*math.pi)**2
    theta_l=.6*math.cos(math.tau*phi)*weight
    bounce=-.8*HIP*(1-math.cos(theta_l))
    lean=.10*weight
    walk_yaw=.08*math.cos(math.tau*phi)*weight
    walk_roll=.03*math.cos(math.tau*(phi-.1))*weight
    walk_x=-.012*HEIGHT*math.cos(math.tau*(phi-.1))*weight
    idle_w=1-weight
    body_offset=Vector((sway*.006*idle_w+walk_x,breath*idle_w+bounce-aim*.012+tremble,aim*.01-kick*.02))
    body_basis=godot_euler(-aim*.05+kick*.07+lean+.006*math.sin(time*math.tau/3+.6)*idle_w,
        walk_yaw+(.02*math.sin(time*math.tau/6+1)+look)*idle_w,
        sway*.012*idle_w*(1-aim)+walk_roll)
    hip=Vector((0,HIP,0))
    body=Matrix.Translation(body_offset+hip-body_basis.to_3x3()@hip)@body_basis
    rig.pose.bones['SkinBody'].matrix=converted(body)@rig.data.bones['SkinBody'].matrix_local
    for n,(sign,side) in enumerate([(-1,'L'),(1,'R')]):
        shoulder=body@Vector((sign*.32,1.035,0))
        arm_swing=-.45*math.cos(math.tau*phi)*(1 if side=='L' else -1)*weight*(1-aim)
        idle_swing=math.sin(time*math.tau/3+sign*.3)*.015*idle_w*(1-aim)
        raise_=aim*.06+kick*(-.10)
        arm_basis=body_basis@godot_euler(arm_swing+raise_,0,idle_swing-sign*aim*.06)
        arm=Matrix.Translation(shoulder+Vector((0,aim*.012,0)))@arm_basis
        upper=arm@Matrix.Translation(Vector((sign*.32,1.035,0))).inverted()
        bend=.86*aim+(.85+.25*max(0,math.cos(math.tau*phi)*(1 if side=='R' else -1)))*weight*(1-aim)
        theta=bend+.05*math.sin(time*math.tau/3+n)*idle_w*(1-aim)+kick*.12
        elbow=about((sign*.34,.82,-.14),Matrix.Rotation(theta,4,'X'))
        fore=upper@elbow
        wrist=(sign*.347,.565,-.213)
        counter=about(wrist,fore.to_3x3().inverted().to_4x4())
        for name,delta in [('Arm'+side,upper),('Forearm'+side,fore),('Hand'+side,fore@counter)]:
            rig.pose.bones['Skin'+name].matrix=converted(delta)@rig.data.bones['Skin'+name].matrix_local
        leg_delta=Matrix.Identity(4)
        if weight>0:
            theta_leg=theta_l if side=='L' else -theta_l
            local=((phi-.5) if side=='L' else phi)%1.0
            lift=.032*HEIGHT*math.sin(math.pi*max(0,min(1,local/.5)))**2 if local<.5 else 0
            leg_delta=Matrix.Translation((0,lift*weight,0))@about((sign*.15,.45,0),Matrix.Rotation(theta_leg,4,'X'))
        rig.pose.bones['SkinLeg'+side].matrix=converted(leg_delta)@rig.data.bones['SkinLeg'+side].matrix_local
    bpy.context.view_layer.update()
rig.animation_data_create()
for name,length,step in [('IdleLoop',180,1),('WalkLoop',30,1),('WaterSprayAttack',30,1)]:
    action=bpy.data.actions.new(name);rig.animation_data.action=action
    for frame in range(0,length+1,step):
        bpy.context.scene.frame_set(frame)
        if name=='IdleLoop':pose(frame/30)
        elif name=='WalkLoop':pose(0.0,phi=(frame%30)/30,weight=1.0)
        else:pose(frame/30,age=frame/30,wind=.6)
        for bone in rig.pose.bones:
            bone.rotation_mode='QUATERNION'
            bone.keyframe_insert('location',frame=frame,group=bone.name)
            bone.keyframe_insert('rotation_quaternion',frame=frame,group=bone.name)
            bone.keyframe_insert('scale',frame=frame,group=bone.name)
    track=rig.animation_data.nla_tracks.new();track.name=name
    track.strips.new(name,0,action);track.mute=True
rig.animation_data.action=None
for bone in rig.pose.bones:bone.matrix_basis=Matrix.Identity(4)
bpy.context.scene.frame_set(0);bpy.context.scene.render.fps=30
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'limne_game.blend'))
bpy.ops.object.select_all(action='SELECT')
glb=ROOT/'art/models/limne/limne.glb'
fresh_path=OUT/'runtime-export.glb'
bpy.ops.export_scene.gltf(filepath=str(fresh_path),export_format='GLB',export_materials='EXPORT',
    export_extras=True,export_animations=True,export_nla_strips=True,
    export_yup=True,export_cameras=False,export_lights=False,
    export_draco_mesh_compression_enable=False)
# The approved runtime GLB keeps every geometry/material/texture byte; only the
# editable clips are replaced (tools/3d/glb_animation_merge.py).
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
from glb_animation_merge import merge_animations
base_dir=OUT/'before-motion2';base_dir.mkdir(exist_ok=True)
base_copy=base_dir/'limne.glb'
if not base_copy.exists():base_copy.write_bytes(glb.read_bytes())
merged=merge_animations(base_copy.read_bytes(),fresh_path.read_bytes())
fresh_path.unlink()
glb.write_bytes(merged)
record=json.loads((OUT/'before/provenance.json').read_text())
payload=glb.read_bytes();glb_json=json.loads(payload[20:20+struct.unpack_from('<I',payload,12)[0]])
record.update(style='Accepted Limne shape; moderate stylized game materials and articulated aiming',
    accepted_source='build/limne-game-motion/before/limne_game.blend',
    accepted_glb_sha256=hashlib.sha256((OUT/'before/limne.glb').read_bytes()).hexdigest(),
    game_source='build/limne-game-motion/limne_game.blend',
    motion_bones=['SkinForearmL','SkinForearmR','SkinHandL','SkinHandR'],
    animation_clips=['IdleLoop','WalkLoop','WaterSprayAttack'],
    motion={'version':2,'tool':'tools/3d/style_animate_limne.py','runtime':'game/3d/limne_model.gd (procedural; clips mirror it)',
            'geometry_base':'build/limne-game-motion/before-motion2/limne.glb','geometry_bytes_preserved':True,
            'clips':{'IdleLoop':6.0,'WalkLoop':1.0,'WaterSprayAttack':1.0,'wind_in_clip':0.6}},
    rig='nine continuous skin bones; original five controls plus elbow/palm articulation',
    game_triangles_before_gltf=sum(sum(len(f.vertices)-2 for f in o.data.polygons) for o in objects),
    glb_sha256=hashlib.sha256(glb.read_bytes()).hexdigest(),
    glb_bytes=len(payload),glb_meshes=len(glb_json['meshes']),glb_materials=len(glb_json['materials']),embedded_images=len(glb_json['images']),
    quality_status='Accepted shape; game style retained; motion 2 (walk cycle, turn, aim twist, recoil) mirrored in editable clips')
(ROOT/'art/models/limne/provenance.json').write_text(json.dumps(record,indent=2)+'\n')
print('LIMNE_GAME_STYLE_MOTION',json.dumps(record))
