#!/usr/bin/env python3
"""Render actual native character geometry from GLB or editable .blend."""
import argparse,math,sys,json
from pathlib import Path
import bpy
from mathutils import Vector,Matrix

p=argparse.ArgumentParser();p.add_argument('--input',required=True);p.add_argument('--out',required=True)
p.add_argument('--quick',action='store_true');p.add_argument('--raw',action='store_true')
p.add_argument('--height',type=float,default=1.68);p.add_argument('--front',choices=['+y','-y'],default='-y')
p.add_argument('--clip');p.add_argument('--frame',type=int,default=30)
a=p.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
src=Path(a.input).resolve();out=Path(a.out).resolve();out.mkdir(parents=True,exist_ok=True)
if src.suffix=='.blend':bpy.ops.wm.open_mainfile(filepath=str(src))
else:
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(src))
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
    if a.raw:
        turn=Matrix.Rotation(math.pi if a.front=='-y' else 0,4,'Z')
        for o in meshes:o.data.transform(turn@o.matrix_world);o.matrix_world=Matrix.Identity(4);o.parent=None
        points=[v.co for o in meshes for v in o.data.vertices]
        lo=Vector([min(v[i] for v in points) for i in range(3)]);hi=Vector([max(v[i] for v in points) for i in range(3)])
        scale=a.height/(hi.z-lo.z);center=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
        for o in meshes:
            for v in o.data.vertices:v.co=(v.co-center)*scale
            for f in o.data.polygons:f.use_smooth=True
            o.data.update()
for o in list(bpy.context.scene.objects):
    if o.type in ['LIGHT','CAMERA']:bpy.data.objects.remove(o,do_unlink=True)
s=bpy.context.scene;s.frame_set(0)
for o in s.objects:
    if o.type=='ARMATURE':
        if o.animation_data:o.animation_data.action=bpy.data.actions.get(a.clip) if a.clip else None
        if not a.clip:
            for bone in o.pose.bones:bone.matrix_basis=Matrix.Identity(4)
if a.clip:s.frame_set(a.frame)
bpy.context.view_layer.update()
model_points=[]
for ob in s.objects:
    if ob.type!='MESH':continue
    evaluated=ob.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh=evaluated.to_mesh()
    model_points.extend(evaluated.matrix_world@v.co for v in mesh.vertices)
    evaluated.to_mesh_clear()
s.render.engine='BLENDER_EEVEE';s.render.resolution_x=1000;s.render.resolution_y=1250
s.render.resolution_percentage=55 if a.quick else 100;s.eevee.taa_render_samples=24 if a.quick else 96
s.eevee.use_gtao=True;s.eevee.gtao_distance=.075;s.eevee.gtao_factor=.8;s.eevee.use_soft_shadows=True
s.render.image_settings.file_format='PNG';s.view_settings.view_transform='AgX';s.view_settings.exposure=0
s.world.use_nodes=True;s.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.035,.05,.075,1)
s.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.45
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.003));floor=bpy.context.object
mat=bpy.data.materials.new('ReviewGround');mat.use_nodes=True
mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.06,.08,.10,1)
mat.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.9;floor.data.materials.append(mat)
for name,pos,power,color,size in [('Key',(-2.5,3.5,4),240,(1,.9,.8),3),('Fill',(3,2,2.5),110,(.75,.86,1),3),('Rim',(1,-3,3),200,(.84,.91,1),2.4)]:
    d=bpy.data.lights.new(name,'AREA');d.energy=power;d.color=color;d.size=size
    o=bpy.data.objects.new(name,d);s.collection.objects.link(o);o.location=pos
    o.rotation_euler=(Vector((0,0,.92))-o.location).to_track_quat('-Z','Y').to_euler()
d=bpy.data.cameras.new('NativeReviewCamera');camera=bpy.data.objects.new('NativeReviewCamera',d)
s.collection.objects.link(camera);s.camera=camera;d.type='ORTHO';d.ortho_scale=a.height*1.55
view_metadata={}
for label,pos in [('three_quarter',(2.4,4.5,1.85)),('front',(0,4.5,1.05)),('back',(0,-4.5,1.05)),('side',(4.5,0,1.05))]:
    camera.location=pos;camera.rotation_euler=(Vector((0,0,a.height*.51))-camera.location).to_track_quat('-Z','Y').to_euler()
    # Pose bounds include a raised blade/bow, not only the resting body.
    bpy.context.view_layer.update()
    projected=[camera.matrix_world.inverted()@point for point in model_points]
    d.ortho_scale=max(a.height*1.55,2*max(abs(v.y)for v in projected)/.86,
                      2*max(abs(v.x)for v in projected)/(.86*.8))
    view_metadata[label]={'width':int(s.render.resolution_x*s.render.resolution_percentage/100),
        'height':int(s.render.resolution_y*s.render.resolution_percentage/100),'ortho_scale':d.ortho_scale,
        'camera_matrix':list(map(list,camera.matrix_world)),'native_height':a.height,
        'clip':a.clip,'frame':a.frame}
    s.render.filepath=str(out/(label+'.png'));bpy.ops.render.render(write_still=True)
d.ortho_scale=a.height*.42;camera.location=(.7,4.5,a.height*.86)
camera.rotation_euler=(Vector((0,0,a.height*.80))-camera.location).to_track_quat('-Z','Y').to_euler()
s.render.filepath=str(out/'face.png');bpy.ops.render.render(write_still=True)
(out/'camera.json').write_text(json.dumps(view_metadata,indent=2)+'\n')
print('ACTUAL_NATIVE_STUDIO',src,out)
