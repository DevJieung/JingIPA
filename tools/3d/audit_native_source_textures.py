#!/usr/bin/env python3
"""Read editable .blend image payloads without saving or changing sources."""
import argparse, hashlib, json, sys
from pathlib import Path
import bpy

ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser()
p.add_argument('--ids',required=True)
p.add_argument('--monsters',action='store_true')
p.add_argument('--output',required=True)
a=p.parse_args(sys.argv[sys.argv.index('--')+1:])
result={'source_unchanged':True,'issues':[],'sources':[]}
for cid in a.ids.split(','):
    for label in ['high','game']:
        path=ROOT/'build/character-3d'/('monster-source'if a.monsters else'source')/cid/(label+'.blend')
        before=hashlib.sha256(path.read_bytes()).hexdigest()
        bpy.ops.wm.open_mainfile(filepath=str(path))
        row={'id':cid,'source':str(path.relative_to(ROOT)),'sha256':before,'images':[]}
        for im in bpy.data.images:
            if im.type!='IMAGE' or im.size[0]<2:continue
            packed=bool(im.packed_file or len(im.packed_files))
            external=Path(bpy.path.abspath(im.filepath)).is_file()if im.filepath else False
            sampled=[float(im.pixels[n])for n in range(min(16,len(im.pixels)))]
            valid=(packed or external)and bool(sampled)
            row['images'].append({'name':im.name,'size':list(im.size),'packed':packed,'external_exists':external,'filepath':im.filepath,'pixels_readable':bool(sampled)})
            if not valid:result['issues'].append(cid+'/'+label+'/'+im.name)
        if not row['images']:result['issues'].append(cid+'/'+label+': no editable textures')
        if hashlib.sha256(path.read_bytes()).hexdigest()!=before:raise ValueError('Source changed')
        result['sources'].append(row)
out=Path(a.output);out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(result,indent=2)+'\n')
print('Editable texture audit',len(result['sources']),'issues',len(result['issues']))
if result['issues']:raise RuntimeError(str(result['issues']))
