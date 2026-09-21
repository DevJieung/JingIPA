#!/usr/bin/env python3
"""Artifact checks and visual contact sheets for the actual exported frames."""
import json
import zipfile
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw,ImageFont
from world_h3 import ROOT,OUT,savejson
from world_h3_post import checker
from world_fx import STYLES

def audit():
    chars=json.loads((ROOT/'art/concepts/last_refuge_v3/characters.json').read_text())
    rows=[]
    font=ImageFont.truetype(str(ROOT/'core/fonts/DinoKR.ttf'),14)
    for c in chars:
        p=OUT/c['id'];issues=[];meta=p/'animation.json';done=meta.exists()
        if not done:
            rows.append({'id':c['id'],'status':'pending'});continue
        m=json.loads(meta.read_text());arrays=[]
        for name,n,size in [('idle',8,256),('attack',12,256),('shot',8,128),('effect',12,128)]:
            if name in ('shot','effect') and not m.get(name):continue
            files=sorted((p/name).glob(f'{name}_*.png'))
            if len(files)!=n:issues.append(f'{name}: {len(files)} frames, expected {n}')
            for f in files:
                im=Image.open(f);a=np.asarray(im)
                if im.mode!='RGBA' or im.size!=(size,size):issues.append(f'{f.name}: wrong format')
                elif not set(np.unique(a[:,:,3])).issubset({0,255}):issues.append(f'{f.name}: soft alpha')
                if name in ('shot','effect') and any(np.any(v) for v in [a[0,:,3],a[-1,:,3],a[:,0,3],a[:,-1,3]]):issues.append(f'{f.name}: FX canvas clipping')
                if name in ('idle','attack'):arrays.append(a)
            with Image.open(p/f'{name}_sheet.png') as im:
                if im.size!=(n*size,size):issues.append(f'{name}: sheet dimensions')
            with Image.open(p/f'{name}.webp') as im:
                if not im.info.get('loop',1)==0:issues.append(f'{name}: not looping')
                if im.n_frames < 2:issues.append(f'{name}: no animated changes')
                for k in range(im.n_frames):im.seek(k);im.load()
        if arrays:
            box=m['qc'].get('foot_pin_box',[0,224,256,256]);x0,y0,x1,y1=box
            if not all(np.array_equal(a[y0:y1,x0:x1],arrays[0][y0:y1,x0:x1]) for a in arrays):issues.append('feet mismatch')
            if any(not np.any(a[:,:,3]==0) for a in arrays):issues.append('background not transparent')
            if any(np.any(a[0,:,3]) or np.any(a[:,0,3]) or np.any(a[:,-1,3]) for a in arrays):issues.append('canvas clipping')
        for f in ['source.mp4','sequence.mp4','generation.json','prompt.txt','workflow.json']:
            if not (p/f).exists():issues.append('missing '+f)
        rows.append({'id':c['id'],'status':'pass' if not issues else 'needs_fix','issues':issues,
            'visual_review':m['qc'].get('camera_and_direction_visual_review','pending')})
    for elem in ['water','fire','ice','elec','none']:
        selected=[c for c in chars if c['element']==elem]
        contact=Image.new('RGB',(1536,2560),'#151c28');draw=ImageDraw.Draw(contact)
        for row,c in enumerate(selected):
            p=OUT/c['id']
            names=['idle/idle_00.png','idle/idle_04.png','attack/attack_03.png','attack/attack_05.png','attack/attack_08.png','attack/attack_10.png']
            for col,name in enumerate(names):
                x=col*256;y=row*256
                if (p/name).exists():
                    im=Image.open(p/name);b=checker((256,256));b.paste(im,mask=im.getchannel('A'));contact.paste(b,(x,y))
                draw.text((x+5,y+3),c['id']+' '+name.split('/')[1][:-4]+'                  ',font=font,fill='white')
        contact.save(OUT/f'review_{elem}.png')
    peak=Image.new('RGB',(1280,2900),'#565963');draw=ImageDraw.Draw(peak)
    for c in chars:
        p=OUT/c['id'];files=[*p.glob('idle/*.png'),*p.glob('attack/*.png')]
        if not files:continue
        f=max(files,key=lambda f:np.count_nonzero(np.array(Image.open(f))[:,:,3]))
        im=Image.open(f);x=['water','fire','ice','elec','none'].index(c['element'])*256;y=(c['tier']-1)*290
        peak.paste(im,(x,y),im);draw.text((x+3,y+260),c['id']+' '+f.stem,font=font,fill='white')
    peak.save(OUT/'review_peak.png')
    result={'total':50,'exported':sum(r['status']!='pending' for r in rows),'artifact_pass':sum(r['status']=='pass' for r in rows),
       'visual_approved':sum(r.get('visual_review')=='approved' for r in rows),'characters':rows}
    savejson(OUT/'audit.json',result)
    print(json.dumps({k:v for k,v in result.items() if k!='characters'}))
    return result

if __name__=='__main__':audit()
