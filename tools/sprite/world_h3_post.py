#!/usr/bin/env python3
"""Extract, stabilize, review and package V3 H3 takes without changing game assets."""
from __future__ import annotations
import argparse
import html
import json
import math
import subprocess
import time
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw,ImageFont
from scipy import ndimage as ndi
from world_h3 import ROOT,OUT,savejson
import world_fx as fx

PIX=256
GROUND=224

def cutout(im):
    """Key the connected background despite H3's magenta->red hue drift.

    The outline is a connectivity barrier, so similarly colored costume pixels
    are preserved. Border colors are measured afresh for each source frame.
    """
    im=im.convert('RGB').resize((PIX,PIX),Image.Resampling.NEAREST)
    a=np.array(im); f=a.astype('float32')
    # Hue wrapping handles both magenta and its red/orange generated variants.
    corner=np.median(np.concatenate([f[:6,:6].reshape(-1,3),f[:6,-6:].reshape(-1,3),f[-6:,:6].reshape(-1,3),f[-6:,-6:].reshape(-1,3)]),axis=0)
    import colorsys
    hue0=colorsys.rgb_to_hsv(*(corner/255))[0]
    hi=f.max(axis=2);lo=f.min(axis=2);delta=np.maximum(hi-lo,1)
    hue=np.where(hi==f[:,:,0],((f[:,:,1]-f[:,:,2])/delta)%6,
         np.where(hi==f[:,:,1],(f[:,:,2]-f[:,:,0])/delta+2,(f[:,:,0]-f[:,:,1])/delta+4))/6
    hd=np.abs(hue-hue0);hd=np.minimum(hd,1-hd)
    candidate=(hd<.115)&((hi-lo)/np.maximum(hi,1)>.25)
    labs,n=ndi.label(candidate)
    edges=np.unique(np.r_[labs[0],labs[-1],labs[:,0],labs[:,-1]])
    bg=np.isin(labs,edges[edges>0])
    # Fit the smooth backdrop color field, then identify enclosed openings by
    # their agreement with that field (not merely red/magenta costume hue).
    yy,xx=np.indices(bg.shape);xx=(xx-128)/128;yy=(yy-128)/128
    basis=np.stack([np.ones_like(xx),xx,yy,xx*xx,xx*yy,yy*yy],axis=-1)
    sample=bg.copy();sample[1::2]=False
    coef=np.linalg.lstsq(basis[sample],f[sample],rcond=None)[0]
    expected=basis@coef
    residual=np.max(abs(f-expected),axis=2)
    sizes=np.bincount(labs.ravel())
    for j in range(1,n+1):
        if sizes[j]>3 and np.median(residual[labs==j])<28:
            bg[labs==j]=True
    fg=~bg
    labs,n=ndi.label(fg);sizes=np.bincount(labs.ravel());sizes[0]=0
    # Detached muzzle flashes, arrows and particles belong in the separate FX
    # assets. Keep the connected actor/equipment silhouette only.
    fg=labs==int(np.argmax(sizes))
    # One-pixel dark outline remains; suppress saturated spill only at boundary.
    edge=fg & ~ndi.binary_erosion(fg)
    spill=edge&candidate
    a[spill]=np.array([31,26,43],dtype='uint8')
    a=np.dstack([a,np.where(fg,255,0).astype('uint8')]);a[~fg,:3]=0
    return Image.fromarray(a)

def anchor(im,center_hint=None):
    a=np.array(im.getchannel('A'))>0
    offset=0
    if center_hint is not None:
        offset=max(0,round(center_hint)-12);a=a[:,offset:min(PIX,round(center_hint)+13)]
    ys,xs=np.where(a)
    if len(xs)<50:raise ValueError('Foreground missing')
    bottom=int(ys.max()); mask=a[max(0,bottom-7):bottom+1]
    xx=np.where(mask)[1]
    return offset+round((int(xx.min())+int(xx.max()))/2),bottom

def align(im,center_hint=None):
    x,y=anchor(im,center_hint);dst=Image.new('RGBA',(PIX,PIX))
    dst.paste(im,(128-x,GROUND-y))
    return dst,(128-x,GROUND-y)

def arc_indices(frames,start,end,n):
    arrays=[np.asarray(f.resize((64,64))).astype('float32') for f in frames[start:end+1]]
    dif=[0]+[float(np.abs(b-a).mean()) for a,b in zip(arrays,arrays[1:])]
    cumulative=np.cumsum(dif)
    if cumulative[-1]<.01:return np.linspace(start,end,n).round().astype(int).tolist()
    out=np.searchsorted(cumulative,np.linspace(0,cumulative[-1],n))+start
    return out.tolist()

def checker(size):
    a=Image.new('RGB',size,'#252b38');d=ImageDraw.Draw(a)
    for y in range(0,size[1],16):
        for x in range(0,size[0],16):
            if (x//16+y//16)%2:d.rectangle((x,y,x+15,y+15),fill='#303847')
    return a

def post(c,force=False):
    dst=OUT/c['id'];files=sorted((dst/'raw').glob('f_*.png'))
    if not (dst/'generation.json').exists():return False
    if (dst/'animation.json').exists() and not force:return True
    print('POST',c['id'],flush=True)
    # Always use semantic masks for the final deliverable. A changing red
    # backdrop can share skin/outline hues, so key-only masks are insufficient.
    keyed=[Image.new('RGBA',(PIX,PIX)) for f in files]
    config=dst/'selection.json'
    sel=json.loads(config.read_text()) if config.exists() else {'idle_start':36,'idle_end':60,'attack_start':61,'attack_end':121,'reference':48}
    fallback=True
    preliminary=list(range(sel['idle_start'],sel['attack_end']+1))
    if 'attack_indices' in sel:
        preliminary=list(range(sel['idle_start'],sel['idle_end']+1))+sel['attack_indices']
    for i in preliminary:
        aa=np.array(keyed[i].getchannel('A'))
        if (aa>0).mean()>.38 or (aa>0).mean()<.005 or np.any(aa[0]) or np.any(aa[:,0]) or np.any(aa[:,-1]):fallback=True
    forced_idle=np.linspace(sel['idle_start'],sel['idle_end'],5).round().astype(int).tolist()
    forced_attack=np.linspace(sel['attack_start'],sel['attack_end'],11).round().astype(int).tolist()
    if fallback:
        indices=sorted(set(forced_idle+forced_attack+sel.get('attack_indices',[])+[sel['reference']]))
        pairs=[]
        for i in indices:
            target=dst/'matte'/f'f_{i:04}.png'
            if target.exists():
                try:
                    with Image.open(target) as cached:cached.verify()
                except Exception:target.unlink()
            if not target.exists():pairs += [str(files[i]),str(target)]
        if pairs:
            subprocess.run(['/home/dgxmaruta/pjt/pixelforge/.venv/bin/python',str(ROOT/'tools/sprite/world_matte.py')]+pairs,check=True)
        for i in indices:
            z=Image.open(dst/'matte'/f'f_{i:04}.png').convert('RGBA')
            a=np.array(z)
            for rule in sel.get('cleanup_colors',[]):
                match=(np.max(abs(a[:,:,:3].astype('int16')-np.array(rule['rgb'])),axis=2)<=rule['tolerance'])&(a[:,:,3]>0)
                labs,n=ndi.label(match);sizes=np.bincount(labs.ravel());sizes[0]=0
                a[np.isin(labs,np.flatnonzero(sizes>=rule['min_area']))]=0
            if c['element']=='none':
                # Neutral concepts have grey outlines. Despill only their thin
                # boundary, retaining the alpha and any interior status lights.
                edge=(a[:,:,3]>0)&~ndi.binary_erosion(a[:,:,3]>0,iterations=3)
                rb=np.maximum(a[:,:,0],a[:,:,2]).astype('int16')
                spill=edge&(a[:,:,1].astype('int16')>rb+18)
                neutral=((a[:,:,0].astype('int16')+a[:,:,2])/2).astype('uint8')
                a[spill,:3]=np.repeat(neutral[spill,None],3,axis=1)
            z=Image.fromarray(a).resize((PIX,PIX),Image.Resampling.NEAREST)
            a=np.array(z);labs,n=ndi.label(a[:,:,3]>0);cnt=np.bincount(labs.ravel());cnt[0]=0
            a[labs!=int(np.argmax(cnt))]=0;keyed[i]=Image.fromarray(a)
    input_small=Image.open(dst/'input_transparent.png').convert('RGBA').resize((PIX,PIX),Image.Resampling.NEAREST)
    foot_hint=sel.get('foot_x',anchor(input_small)[0])
    forward=forced_idle
    idle_idx=forward+forward[-2:0:-1]
    attack_idx=sel.get('attack_indices',[sel['reference']]+forced_attack)
    required=sorted(set(idle_idx+attack_idx+[sel['reference']]))
    anchors={i:anchor(keyed[i],foot_hint) for i in required}
    extents=[]
    for i in required:
        b=keyed[i].getbbox();x,y=anchors[i]
        extents.append((b[0]-x,b[1]-y,b[2]-x,b[3]-y))
    left=min(b[0] for b in extents);top=min(b[1] for b in extents)
    right=max(b[2] for b in extents);bottom=max(b[3] for b in extents)
    ref_source=keyed[sel['reference']]
    ref_height=anchors[sel['reference']][1]-ref_source.getbbox()[1]
    # Compute the common transform BEFORE placing frames on the final canvas.
    # Centering first would silently crop an extended bow/sword at the edge.
    scale=min(192/max(1,ref_height),(GROUND-8)/max(1,-top),
              120/max(1,-left),120/max(1,right),(PIX-GROUND-5)/max(1,bottom))
    n=max(1,round(PIX*scale));scale=n/PIX
    palette=ref_source.convert('RGB').quantize(colors=64,method=Image.Quantize.MEDIANCUT)
    shifts=[]
    def render(i):
        f=keyed[i];x,y=anchors[i]
        z=f.convert('RGB').quantize(palette=palette,dither=Image.Dither.NONE).convert('RGBA')
        z.putalpha(f.getchannel('A'));z=z.resize((n,n),Image.Resampling.NEAREST)
        dst_im=Image.new('RGBA',(PIX,PIX));xy=(128-round(x*scale),GROUND-round(y*scale))
        dst_im.paste(z,xy)
        shifts.append(list(xy))
        return dst_im
    rendered={i:render(i) for i in required}
    ref=rendered[sel['reference']]
    # Pin the sole/ankle region only. A low-sweeping chain outside the feet must
    # remain visible instead of being erased by a full-width horizontal patch.
    pin_y=GROUND-14
    pin_box=tuple(sel.get('foot_pin_box',(80,pin_y,176,GROUND+4)))
    sole=rendered[sel.get('foot_pin_reference',sel['reference'])].crop(pin_box)
    ref.paste(sole,pin_box[:2])
    def finish(i):
        z=rendered[i].copy();z.paste(sole,pin_box[:2]);return z
    idle=[finish(i) for i in idle_idx];attack=[finish(i) for i in attack_idx]
    attack[-1]=ref.copy()
    fx.export_sequence(idle,dst/'idle','idle')
    fx.export_sequence(attack,dst/'attack','attack')
    ref.save(dst/'ready.png')
    fxmeta=fx.build(c,dst)
    # Review video contains the exact exported poses in order, not a second AI
    # generation. It therefore matches the sheets and is rigidly foot-locked.
    sequence=idle+attack+idle[:1]
    seqdir=dst/'sequence';seqdir.mkdir(exist_ok=True)
    for i,f in enumerate(sequence):
        b=checker((PIX,PIX));b.paste(f,mask=f.getchannel('A'))
        b.resize((768,768),Image.Resampling.NEAREST).save(seqdir/f'f_{i:03}.png')
    subprocess.run(['ffmpeg','-v','error','-y','-framerate','12','-i',str(seqdir/'f_%03d.png'),'-c:v','libx264','-crf','16','-pix_fmt','yuv420p',str(dst/'sequence.mp4')],check=True)
    for f in seqdir.glob('*.png'):f.unlink()
    seqdir.rmdir()
    sequence[0].save(dst/'sequence.webp',save_all=True,append_images=sequence[1:],duration=83,loop=0,lossless=True,exact=True)
    used=idle+attack
    aa=[np.asarray(f) for f in used]
    pin_equal=all(np.array_equal(a[pin_box[1]:pin_box[3],pin_box[0]:pin_box[2]],aa[0][pin_box[1]:pin_box[3],pin_box[0]:pin_box[2]]) for a in aa)
    clipped=any(np.any(a[:,0,3]) or np.any(a[:,-1,3]) or np.any(a[0,:,3]) for a in aa)
    qc={'alpha_values':sorted(set(np.concatenate([np.unique(a[:,:,3]) for a in aa]).tolist())),
        'feet_pixels_identical':pin_equal,'ground_y':GROUND,'foot_pin_rows':[pin_box[1],pin_box[3]-1],'foot_pin_box':list(pin_box),'source_foot_x_hint':foot_hint,
        'canvas_clipping':bool(clipped),'source_canvas_clipping':any(np.any(np.array(keyed[i])[0,:,3]) or np.any(np.array(keyed[i])[:,0,3]) or np.any(np.array(keyed[i])[:,-1,3]) for i in required),'max_registration_shift_px':np.max(np.abs(shifts),axis=0).tolist(),
        'camera_and_direction_visual_review':'pending','source_take_has_unconstrained_initial_turn':True,
        'matting':'BiRefNet CPU + connected component cleanup'}
    savejson(dst/'animation.json',{'id':c['id'],'name':c['name'],'element':c['element'],'tier':c['tier'],
      'attack_design':c['attack'],'hit_frame':int(sel.get('hit_frame',6)),'frame_size':PIX,'fps':12,'palette_colors':64,'constant_character_scale':scale,'origin':[128,GROUND],
      'idle_frames':8,'attack_frames':12,'idle_source_indices':idle_idx,'attack_source_indices':attack_idx,
      'attack_last_frame_replaced_with_ready':True,'selection':sel,'qc':qc,**fxmeta})
    return True

def gallery(chars):
    OUT.mkdir(parents=True,exist_ok=True)
    complete=[c for c in chars if (OUT/c['id']/'animation.json').exists()]
    cards=[]
    for c in sorted(chars,key=lambda x:(x['tier'],['water','fire','ice','elec','none'].index(x['element']))):
        i=c['id'];done=c in complete;shot,area=fx.STYLES[i]
        tags=('Shot' if shot else '')+(' + ' if shot and area else '')+('Area FX' if area else '')
        visual=f'<img class="anim" src="{i}/sequence.webp"><img class="fx" src="{i}/{"shot" if shot else "effect"}.webp">' if done else f'<img class="pending" src="../../concepts/last_refuge_v3_pixel/{i}.png">'
        links=(f'<a href="{i}/source.mp4">H3 원본</a> <a href="{i}/sequence.mp4">고정 영상</a> <a href="{i}/idle_sheet.png">Idle 시트</a> <a href="{i}/attack_sheet.png">Attack 시트</a>'
         +(f' <a href="{i}/shot_sheet.png">Shot 시트</a>' if shot else '')+(f' <a href="{i}/effect_sheet.png">FX 시트</a>' if area else '')+f' <a href="{i}/animation.json">메타데이터</a>') if done else 'H3 생성·추출 대기'
        cards.append(f'<article data-id="{i}" data-elem="{c["element"]}" data-done="{str(done).lower()}"><h2>T{c["tier"]} · {html.escape(c["name"])} <small>{i}</small></h2><div class="stage">{visual}<span class="ground"></span></div><b>{tags}</b><p>{html.escape(c["attack"])}</p><div class="links">{links}</div></article>')
    page='''<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Last Refuge · H3 Pixel Motion Review</title>
<style>*{box-sizing:border-box}body{margin:0;background:#111622;color:#e4e9f4;font:14px system-ui}header{padding:26px 30px;position:sticky;top:0;background:#111622f5;z-index:2;border-bottom:1px solid #39435a}h1{font-size:24px;margin:0 0 10px}button,select{background:#28364c;color:white;border:1px solid #607492;border-radius:6px;padding:8px;margin:3px}main{display:grid;grid-template-columns:repeat(5,minmax(220px,1fr));gap:14px;padding:20px}article{background:#1b2434;border:1px solid #39435a;border-radius:10px;overflow:hidden}h2{font-size:15px;margin:12px}small{font-size:11px;color:#91a5bf}p{font-size:12px;line-height:1.6;padding:0 12px;min-height:60px}.stage{position:relative;aspect-ratio:1;background:repeating-conic-gradient(#303847 0% 25%,#252b38 0% 50%) 0/24px 24px}.stage img{position:absolute;width:100%;height:100%;object-fit:contain;image-rendering:pixelated}.stage .fx{width:40%;height:40%;right:0;top:24%;pointer-events:none}.stage .pending{opacity:.4}.ground{position:absolute;top:87.5%;left:0;width:100%;border-top:1px dashed #68f1b790;pointer-events:none}.links{padding:12px;font-size:12px;line-height:2}a{color:#8cd7ff;margin-right:7px}b{display:block;margin:9px 12px;font-size:11px;color:#8ed5cb}.light .stage{background:repeating-conic-gradient(#dedede 0% 25%,#f5f5f5 0% 50%) 0/24px 24px}.plain .stage{background:#34473e}@media(max-width:1100px){main{grid-template-columns:repeat(3,1fr)}}@media(max-width:700px){main{grid-template-columns:repeat(2,1fr)}}</style>
<header><h1>LAST REFUGE · 50 PIXEL MOTIONS</h1><div>COUNT / 50 추출 완료 · 오른쪽 보기 → Idle → Attack · 투명 PNG/WebP · 발 기준선 고정</div><nav><button data-mode="sequence">연속 동작</button><button data-mode="idle">Idle</button><button data-mode="attack">Attack</button><button data-mode="shot">Shot</button><button data-mode="effect">범위 FX</button><button id="bg">배경 전환</button><select id="elem"><option value="all">모든 속성</option><option>water</option><option>fire</option><option>ice</option><option>elec</option><option>none</option></select></nav><small>H3 원본은 비교용입니다. 고정 영상과 추출 애니메이션은 배경 제거·발 보정을 거쳤습니다. 원본 회전 구간 제외. 발·발목 영역 픽셀 고정.</small></header><main>CARDS</main>
<script>const styles=STYLES;document.querySelectorAll('[data-mode]').forEach(b=>b.onclick=()=>{let mode=b.dataset.mode;document.querySelectorAll('article[data-done="true"]').forEach(a=>{let id=a.dataset.id,has=mode==='shot'?styles[id][0]:mode==='effect'?styles[id][1]:true;let im=a.querySelector('.anim');im.src=id+'/'+(has?mode:'ready')+(has?'.webp':'.png');a.querySelector('.fx').style.display=mode==='sequence'?'':'none';})});let bg=0;document.querySelector('#bg').onclick=()=>{bg=(bg+1)%3;document.body.className=['','light','plain'][bg]};document.querySelector('#elem').onchange=e=>document.querySelectorAll('article').forEach(a=>a.style.display=e.target.value==='all'||a.dataset.elem===e.target.value?'':'none');</script></html>'''
    page=page.replace('COUNT',str(len(complete))).replace('CARDS',''.join(cards)).replace('STYLES',json.dumps(fx.STYLES))
    page=page.replace('<nav>','<nav><a href="effects.html">50명 Shot / FX 전체 보기</a> ')
    (OUT/'index.html').write_text(page)
    fx_cards=[]
    fx_overview=Image.new('RGB',(1280,1800),'#111622');fd=ImageDraw.Draw(fx_overview)
    font=ImageFont.truetype(str(ROOT/'core/fonts/DinoKR.ttf'),14)
    for c in chars:
        i=c['id'];shot,area=fx.STYLES[i];images=[];links=[]
        for name,style in [('shot',shot),('effect',area)]:
            if style:
                images.append(f'<div><img width="160" height="160" src="{i}/{name}.webp"><small>{name}: {style}</small></div>')
                links.append(f'<a href="{i}/{name}_sheet.png">{name} PNG sheet</a>')
        fx_cards.append(f'<article><h2>T{c["tier"]} {html.escape(c["name"])} · {i}</h2><div class="fxstage">'+''.join(images)+'</div><p>'+html.escape(c['attack'])+'</p><p>'+' '.join(links)+'</p></article>')
        col=['water','fire','ice','elec','none'].index(c['element']);x=col*256;y=(c['tier']-1)*180
        names=[n for n,s in [('shot',shot),('effect',area)] if s]
        for k,name in enumerate(names):
            fp=OUT/i/name/f'{name}_05.png'
            if fp.exists():
                im=Image.open(fp);ox=x+(k*128 if len(names)==2 else 64);fx_overview.paste(im,(ox,y),im)
        fd.text((x+7,y+135),f'T{c["tier"]} {c["name"]} {i}                   ',font=font,fill='#d6e8ff')
    fx_overview.save(OUT/'effects_overview.png')
    css=page[page.index('<style>'):page.index('</style>')+8]
    fxpage='<!doctype html><html lang="ko"><meta charset="utf-8"><title>50 Shot / Area FX</title>'+css+'<style>.fxstage{display:flex;justify-content:center;background:#303847}.fxstage img{image-rendering:pixelated;display:block;width:128px;height:128px}.fxstage small{display:block;text-align:center;font-size:10px}</style><header><h1>50명 · SHOT / AREA FX</h1><a href="index.html">캐릭터 모션 검토</a><a href="effects_overview.png">이펙트 overview PNG</a><p>투명 배경 · 128 × 128px · 12 fps · Shot 8프레임 / Area 12프레임</p></header><main>'+''.join(fx_cards)+'</main></html>'
    (OUT/'effects.html').write_text(fxpage)
    savejson(OUT/'progress.json',{'complete':len(complete),'total':50,'ids':[c['id'] for c in complete]})
    # Compact static overview, one representative right-facing ready stance.
    tilew,tileh=256,295
    overview=Image.new('RGB',(tilew*5,tileh*10),'#111622');d=ImageDraw.Draw(overview)
    font=ImageFont.truetype(str(ROOT/'core/fonts/DinoKR.ttf'),14)
    for c in chars:
        col=['water','fire','ice','elec','none'].index(c['element']);x=col*tilew;y=(c['tier']-1)*tileh
        if c in complete:
            f=Image.open(OUT/c['id']/'ready.png');b=checker((256,256));b.paste(f,mask=f.getchannel('A'));overview.paste(b,(x,y))
        d.text((x+9,y+261),f'T{c["tier"]} {c["name"]}  {c["id"]}                       ',font=font,fill='#e4e9f4')
    overview.save(OUT/'overview.png')

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--watch',action='store_true');ap.add_argument('--force',action='store_true');ap.add_argument('--only',default='');a=ap.parse_args()
    chars=json.loads((ROOT/'art/concepts/last_refuge_v3/characters.json').read_text())
    targets=[c for c in chars if not a.only or c['id'] in a.only.split(',')]
    while True:
        for c in targets:
            error=OUT/c['id']/'post_error.json'
            if error.exists() and not a.force:continue
            try:post(c,a.force)
            except Exception as exc:
                savejson(error,{'error':str(exc),'time':time.time()});print('POST ERROR',c['id'],str(exc),flush=True)
        gallery(chars)
        if not a.watch or all((OUT/c['id']/'animation.json').exists() for c in targets):break
        time.sleep(25)
    print('POST DONE',flush=True)

if __name__=='__main__':main()
