#!/usr/bin/env python3
"""Inspect actual posed native surfaces; statistics do not certify aesthetics.

bl -b --factory-startup --python tools/3d/check_native_deformation.py -- \
  --input build/character-3d/source/echo/game.blend --output build/character-3d/review/echo/deformation.json
"""
import argparse,hashlib,json,sys
from pathlib import Path
import bpy
from mathutils import Matrix

p=argparse.ArgumentParser();p.add_argument('--input',required=True);p.add_argument('--output',required=True)
a=p.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
source=Path(a.input).resolve();bpy.ops.wm.open_mainfile(filepath=str(source))
rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
height=max(v.co.z for o in meshes for v in o.data.vertices)-min(v.co.z for o in meshes for v in o.data.vertices)
rest={o.name:[v.co.copy() for v in o.data.vertices] for o in meshes};samples=[]
for clip,frames in [('IdleLoop',[0,45,90,135,180]),('Attack',[0,12,24,30,34,39])]:
    action=bpy.data.actions.get(clip)
    if action is None:raise ValueError('Missing actual native clip: '+clip)
    rig.animation_data.action=action
    for frame in frames:
        bpy.context.scene.frame_set(frame);bpy.context.view_layer.update()
        critical=[];maximum=0.;foot=0.
        for ob in meshes:
            evaluated=ob.evaluated_get(bpy.context.evaluated_depsgraph_get());mesh=evaluated.to_mesh()
            vertices=rest[ob.name]
            for edge in ob.data.edges:
                i,j=edge.vertices;before=(vertices[i]-vertices[j]).length
                after=(mesh.vertices[i].co-mesh.vertices[j].co).length
                maximum=max(maximum,after-before)
                if before<height*.035 and after>height*.13 and after>before*8:
                    critical.append({'mesh':ob.name,'vertices':[i,j],'rest_m':before,'posed_m':after,
                        'xyz':[list(vertices[i]),list(vertices[j])],
                        'bones':[{ob.vertex_groups[g.group].name:g.weight for g in ob.data.vertices[k].groups}for k in [i,j]]})
            for i,v in enumerate(vertices):
                if v.z<height*.045 and abs(v.x)<height*.23:
                    foot=max(foot,(mesh.vertices[i].co-v).length)
            evaluated.to_mesh_clear()
        critical.sort(key=lambda row:row['posed_m'],reverse=True)
        samples.append({'clip':clip,'frame':frame,'short_edge_overstretch_count':len(critical),
            'maximum_edge_extension_m':maximum,'sole_movement_m':foot,'largest_examples':critical[:8]})
result={'source':str(source),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
    'purpose':'Detect tears and body/equipment misbinding in actual posed geometry; direct multiview/motion QA remains required',
    'review_required':any(s['short_edge_overstretch_count']for s in samples),'samples':samples}
out=Path(a.output);out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(result,indent=2)+'\n')
print('ACTUAL_DEFORMATION',out,'review_required',result['review_required'])
