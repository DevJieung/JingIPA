#!/usr/bin/env python3
"""Render the REAL Limne mesh/materials in a soft studio, not an AI raster.

Run in Blender: bl -b <actual-model.blend> --python tools/3d/render_limne_studio.py
Views are saved in ignored build/limne-pro/studio/. Does not restyle the source.
"""
import bpy
import math
import os
from pathlib import Path
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[2]
OUT=Path(os.environ.get('LIMNE_STUDIO_OUTPUT',str(ROOT/'build/limne-pro/studio')))
OUT.mkdir(parents=True,exist_ok=True)
s=bpy.context.scene
s.render.engine='BLENDER_EEVEE'
s.render.resolution_x=1440;s.render.resolution_y=1800;s.render.resolution_percentage=100
s.render.image_settings.file_format='PNG'
s.render.film_transparent=False
s.eevee.taa_render_samples=128
if os.environ.get('LIMNE_STUDIO_QUICK')=='1':
    s.render.resolution_percentage=50
    s.eevee.taa_render_samples=32
s.eevee.use_gtao=True;s.eevee.gtao_distance=.075;s.eevee.gtao_factor=.85
s.eevee.use_soft_shadows=True
s.eevee.use_ssr=True;s.eevee.use_ssr_refraction=True
s.view_settings.view_transform='AgX'
s.view_settings.exposure=0;s.view_settings.gamma=1
s.world.use_nodes=True
s.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.055,.069,.085,1)
s.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.40

# A quiet studio cyclorama/ground provides contact and material judgement.
mesh=bpy.data.meshes.new('StudioFloor')
mesh.from_pydata([(-200,-200,-.003),(200,-200,-.003),(200,200,-.003),(-200,200,-.003)],[],[(0,1,2,3)])
floor=bpy.data.objects.new('StudioFloor',mesh);s.collection.objects.link(floor)
mat=bpy.data.materials.new('StudioNeutral');mat.use_nodes=True
node=mat.node_tree.nodes.get('Principled BSDF')
node.inputs['Base Color'].default_value=(.065,.080,.098,1)
node.inputs['Roughness'].default_value=.84
mesh.materials.append(mat)
for name,pos,power,color,size in [
    ('BroadKey',(-2.2,3.4,3.8),240,(1,.89,.78),3.0),
    ('SoftFill',(2.9,2.0,2.6),95,(.75,.86,1),3.0),
    ('Rim',(1.6,-2.5,3.2),210,(.82,.91,1),2.4),
    ('TopSoft',(-.3,-.1,4.2),90,(1,.95,.86),2.0)]:
    d=bpy.data.lights.new(name,'AREA');d.energy=power;d.size=size;d.color=color
    o=bpy.data.objects.new(name,d);s.collection.objects.link(o);o.location=pos
    o.rotation_euler=(Vector((0,0,.94))-o.location).to_track_quat('-Z','Y').to_euler()
camera_data=bpy.data.cameras.new('StudioCamera')
camera=bpy.data.objects.new('StudioCamera',camera_data);s.collection.objects.link(camera)
s.camera=camera;camera_data.type='ORTHO';camera_data.ortho_scale=2.05
for label,pos in [('three_quarter',(2.25,4.5,1.8)),('front',(0,4.5,1.13)),
                  ('side',(4.5,0,1.13)),('back',(0,-4.5,1.13))]:
    camera.location=pos
    camera.rotation_euler=(Vector((0,0,.86))-camera.location).to_track_quat('-Z','Y').to_euler()
    s.render.filepath=str(OUT/(label+'.png'));bpy.ops.render.render(write_still=True)
# Face/material close-up uses the actual same mesh and textures.
camera_data.ortho_scale=.76
camera.location=(.75,3.8,1.47)
camera.rotation_euler=(Vector((0,0,1.32))-camera.location).to_track_quat('-Z','Y').to_euler()
s.render.filepath=str(OUT/'face_closeup.png');bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'studio_scene.blend'))
print('LIMNE_PRO_REAL_STUDIO_RENDER',OUT)
