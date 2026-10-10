#!/usr/bin/env python3
"""Read actual creature poses/loop seams; not an aesthetic or FPS test."""
import argparse,hashlib,json,sys
from pathlib import Path
import bpy

p=argparse.ArgumentParser();p.add_argument('--input',required=True);p.add_argument('--output',required=True)
a=p.parse_args(sys.argv[sys.argv.index('--')+1:]if'--'in sys.argv else[])
path=Path(a.input).resolve();bpy.ops.wm.open_mainfile(filepath=str(path))
rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
H=max(v.co.z for o in objects for v in o.data.vertices)-min(v.co.z for o in objects for v in o.data.vertices)
samples=[];seams={}
# Loop clips must close; Attack holds the same neutral pose at both ends; Die is one-shot.
for name in ['IdleLoop','MoveLoop','Attack','Die']:
    action=bpy.data.actions.get(name)
    if action is None:
        if name in ['IdleLoop','MoveLoop']:raise ValueError('Missing authored '+name)
        continue
    rig.animation_data.action=action;last=int(action.frame_range[1]);endpoints=[]
    for frame in sorted(set([0,last//4,last//2,last*3//4,last]+([int(last*.7)] if name=='Attack' else []))):
        bpy.context.scene.frame_set(frame);bpy.context.view_layer.update();count=0;ground=100.;greatest=0.
        if frame in [0,last]:endpoints.append([b.matrix.copy()for b in rig.pose.bones])
        for ob in objects:
            evaluated=ob.evaluated_get(bpy.context.evaluated_depsgraph_get());mesh=evaluated.to_mesh()
            for edge in ob.data.edges:
                i,j=edge.vertices;before=(ob.data.vertices[i].co-ob.data.vertices[j].co).length
                after=(mesh.vertices[i].co-mesh.vertices[j].co).length;greatest=max(greatest,after-before)
                if before<H*.025 and after>H*.12 and after>before*8:count+=1
            ground=min(ground,min(v.co.z for v in mesh.vertices));evaluated.to_mesh_clear()
        samples.append({'clip':name,'frame':frame,'short_edge_overstretch_count':count,'maximum_edge_extension_m':greatest,'minimum_ground_z_m':ground})
    if name!='Die':seams[name]=max(abs(start[i][j]-end[i][j])for start,end in zip(*endpoints)for i in range(4)for j in range(4))
rig.animation_data.action=None
result={'source':str(path),'source_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'purpose':'actual anatomy deformation and endpoint seam diagnostics; direct visual QA required','samples':samples,'loop_matrix_max_error':seams,'review_required':any(s['short_edge_overstretch_count']for s in samples)or max(seams.values())>1e-5}
out=Path(a.output);out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(result,indent=2)+'\n');print('CREATURE_POSE_DIAGNOSTIC',result['review_required'],out)
