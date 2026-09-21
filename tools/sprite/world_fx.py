"""Deterministic transparent pixel effects matching the V3 attack mechanisms."""
from PIL import Image, ImageDraw
import math

# Each tuple is a travelling shot and/or a separate area impact.
STYLES = {
 'limne':('', 'pool'), 'phorkys':('pressure',''), 'protea':('triple_arrow',''),
 'marea':('','wave'), 'glaukos':('','geyser'), 'thalassa':('','rain'),
 'triton':('pressure_ring',''), 'keto':('harpoon','water_split'), 'galene':('','water_fan'), 'nerea':('','water_wall'),
 'chispa':('ember',''), 'solana':('arrow','fire_burst'), 'ceniza':('','embers'), 'igni':('','fire_slash'),
 'volcan':('','fissure'), 'carmen':('hot_round',''), 'saeta':('heavy_arrow','fire_pool'), 'candela':('','fire_ring'),
 'estoque':('heat_lance',''), 'brasa':('','inferno'), 'lind':('ice_chain',''), 'jokull':('','ice_slash'),
 'vidarr':('','freeze_fan'), 'kari':('','ice_cone'), 'eira':('arrow','blizzard_small'), 'snorri':('anchor','frost_wave'),
 'helga':('','ice_cross'), 'sigrid':('','blizzard'), 'frosti':('frost_round',''), 'isa':('icicle','ice_pillars'),
 'brigid':('arrow','chain_lightning'), 'rhiannon':('','linked_arc'), 'finn':('double_streak',''),
 'donn':('','lightning'), 'conor':('charged_round','electric_burst'), 'niamh':('triple_arrow','chain_lightning'),
 'morrigan':('','electric_ring'), 'caden':('','triple_slash'), 'lugh':('','lightning_field'), 'brian':('rail',''),
 'pip':('slash',''), 'mimic':('','shock'), 'dummy':('round',''), 'echo':('echo_arrow',''),
 'shift':('','blade_fan'), 'phantom':('','double_slash'), 'blank':('','shock_field'), 'grey':('heavy_round',''),
 'null':('needle',''), 'zero':('','chain_wave')}

COLORS={
 'water': ['#092c52','#176791','#21aab9','#6ddcde','#d6ffff'],
 'fire': ['#591a31','#b93828','#f37925','#ffd55b','#fff5bd'],
 'ice': ['#213c73','#477abc','#71bfeb','#b5edff','#f1ffff'],
 'elec': ['#30234f','#6750b3','#b189ee','#e1db73','#ffffcf'],
 'none': ['#302e3c','#656275','#a8a6b2','#dad6e1','#fff5df']}

def sprite_shot(style,elem,t):
    im=Image.new('RGBA',(128,128));d=ImageDraw.Draw(im); c=COLORS[elem]
    pulse=math.sin(t*2*math.pi); y=64
    # Tail motion stays local: engine translation remains independent of sheet.
    if 'arrow' in style or style in ('harpoon','needle','icicle'):
        offsets=[-12,0,12] if style=='triple_arrow' else ([0,10] if style=='echo_arrow' else [0])
        for off in offsets:
            yy=y+off; length=66 if style not in ('heavy_arrow','icicle') else 80
            x=28 if style!='echo_arrow' or off==0 else 13
            d.line([(x,yy),(x+length,yy)], fill=c[0],width=5)
            d.line([(x,yy-1),(x+length,yy-1)],fill=c[3],width=2)
            d.polygon([(x+length+8,yy),(x+length-7,yy-7),(x+length-3,yy),(x+length-7,yy+7)],fill=c[1],outline=c[0])
            d.polygon([(x+length+6,yy),(x+length-5,yy-4),(x+length-1,yy)],fill=c[4])
            if style!='needle':
                d.polygon([(x+12,yy),(x+2,yy-8),(x-4,yy-8),(x+3,yy)],fill=c[2],outline=c[0])
                d.polygon([(x+12,yy),(x+2,yy+8),(x-4,yy+8),(x+3,yy)],fill=c[2],outline=c[0])
    elif style in ('ice_chain','anchor'):
        for k in range(6):
            x=24+k*11;yy=64+round(3*math.sin(t*math.tau+k*.6))
            d.ellipse((x-7,yy-4,x+7,yy+4),outline=c[0],width=3);d.line((x-5,yy-2,x+5,yy-2),fill=c[3],width=2)
        d.polygon([(104,64),(92,48),(87,51),(92,64),(87,77),(92,80)],fill=c[2],outline=c[0])
    elif style in ('slash','double_streak','heat_lance','rail'):
        for off in ([-8,8] if style=='double_streak' else [0]):
            d.polygon([(13,y+off+5),(104,y+off-4),(116,y+off),(39,y+off+10)],fill=c[0])
            d.polygon([(21,y+off+4),(104,y+off-2),(112,y+off),(39,y+off+7)],fill=c[2])
            d.line((48,y+off+3,107,y+off),fill=c[4],width=2)
    else:
        r=10 if style not in ('heavy_round','pressure','pressure_ring') else 14
        for k in range(3):
            yy=y+(k-1)*9; x=18+round((t*24+k*11)%22)
            d.line((x,yy,76,yy),fill=c[k],width=3 if k==1 else 2)
        d.polygon([(102,y),(89,y-r),(73,y-r+3),(61,y),(73,y+r-3),(89,y+r)],fill=c[0])
        d.polygon([(99,y),(86,y-r+3),(72,y-r+6),(67,y),(77,y+r-4),(88,y+r-3)],fill=c[2])
        d.polygon([(98,y),(85,y-4),(75,y-3),(81,y+2)],fill=c[4])
        if style=='pressure_ring': d.ellipse((72,43,87,85),outline=c[3],width=3)
    if elem!='none':
        for k in range(5):
            x=20+((k*17-round(t*22))%68); yy=64+(-1 if k%2 else 1)*(12+k%3*4)
            d.rectangle((x,yy,x+2,yy+2),fill=c[1+k%3])
    else:
        # A travelling highlight and trailing ticks keep neutral shots animated
        # without moving their collision origin inside the sprite frame.
        x=30+round(t*62)
        yy=65 if style=='slash' else 63
        d.line((x,yy,x+7,yy),fill=c[4],width=2)
        for k in range(3):
            x=10+((k*13-round(t*28))%25)
            yy=54+k*10
            d.line((x,yy,x+6,yy),fill=c[1+k%2],width=1)
    return im

def effect(style,elem,t):
    im=Image.new('RGBA',(128,128));d=ImageDraw.Draw(im);c=COLORS[elem]
    env=math.sin(math.pi*t)**.65
    if env<.01:return im
    r=int(9+43*math.sin(min(1,t*1.5)*math.pi/2)); cy=82
    def ring(rad,y=cy,width=3):
        d.ellipse((64-rad,y-rad*.35,64+rad,y+rad*.35),outline=c[0],width=width+2)
        d.ellipse((65-rad,y-rad*.35,63+rad,y+rad*.35-1),outline=c[2],width=width)
        d.arc((65-rad,y-rad*.35,63+rad,y+rad*.35-1),190,320,fill=c[4],width=max(1,width-1))
    if style=='water_split':
        for k in range(3):
            aa=math.radians(-45+k*45);rr=8+44*t;x=45+rr*math.cos(aa);y=68+rr*math.sin(aa)
            d.polygon([(x-10,y),(x+1,y-5),(x+7,y),(x+1,y+5)],fill=c[2],outline=c[0])
            d.line((x-2,y-2,x+3,y-1),fill=c[4],width=2)
            d.line((x-19,y,x-12,y),fill=c[1],width=2)
    elif style in ('geyser','water_wall'):
        n=3 if style=='water_split' else (7 if style=='water_wall' else 1)
        for k in range(n):
            x=64+(k-(n-1)/2)*11;ht=(47+9*math.sin(k*1.2))*env;w=13 if n==1 else 7
            d.polygon([(x-w,94),(x-w*.7,94-ht),(x,85-ht),(x+w*.7,94-ht),(x+w,94)],fill=c[1],outline=c[0])
            d.line([(x-w*.4,92),(x-w*.3,96-ht),(x,90-ht)],fill=c[3],width=3)
            d.line((x+w*.3,92,x+w*.2,98-ht),fill=c[2],width=2)
        ring(r,95,3)
        for k in range(7):
            aa=k*math.pi/6;x=64+math.cos(aa)*r*.7;y=82-math.sin(aa)*r
            d.rectangle((x,y,x+2,y+4),fill=c[3])
    elif style in ('freeze_fan','ice_cone','blade_fan'):
        pts=[(27,85)]+[(27+r*1.7*math.cos(math.radians(a)),85+r*.6*math.sin(math.radians(a))) for a in range(-50,51,10)]
        d.polygon(pts,fill=c[0]);d.line(pts[1:],fill=c[2],width=2)
        for k in range(9):
            aa=math.radians(-48+k*12);rr=r*(.7+(k%3)*.36);x=27+rr*1.2*math.cos(aa);y=85+rr*.6*math.sin(aa)
            ht=(6+9*env) if style!='blade_fan' else 4
            d.polygon([(x-4,y+2),(x+5,y-ht),(x+4,y+3)],fill=c[3],outline=c[1])
    elif style=='ice_cross':
        for sign in (-1,1):
            pts=[(27,65-sign*31),(95,65+sign*30),(80,65+sign*24),(32,65-sign*21)]
            d.polygon(pts,fill=c[1],outline=c[0]);d.line(pts[:2],fill=c[4],width=3)
        for k in range(6):
            aa=k*math.tau/6;x=64+31*env*math.cos(aa);y=65+31*env*math.sin(aa)
            d.polygon([(x-3,y),(x,y-6),(x+4,y),(x,y+5)],fill=c[3],outline=c[1])
    elif style=='electric_burst':
        for k in range(9):
            aa=k*math.tau/9;x=64+r*math.cos(aa);y=67+r*math.sin(aa)
            p=[(64+10*math.cos(aa),67+10*math.sin(aa)),(x*.65+64*.35+5,y*.65+67*.35-5),(x,y)]
            d.line(p,fill=c[1],width=6);d.line(p,fill=c[4],width=2)
        d.polygon([(64,49),(77,67),(64,82),(50,67)],fill=c[2],outline=c[0])
        d.polygon([(64,55),(71,67),(64,75),(57,67)],fill=c[4])
    elif style in ('fire_ring','inferno','fire_burst'):
        ring(r,82,4)
        n=14 if style=='inferno' else 10
        for k in range(n):
            aa=k*math.tau/n;rr=r*(1 if style=='fire_ring' else .4+.6*env)
            x=64+rr*math.cos(aa);y=82+rr*.4*math.sin(aa);ht=(14+19*(.5+.5*math.sin(k*2+t*5)))*env
            if style=='inferno':ht*=1.5
            d.polygon([(x-7,y),(x-4,y-ht*.6),(x+2,y-ht),(x+3,y-ht*.3),(x+7,y)],fill=c[1],outline=c[0])
            d.polygon([(x-3,y-2),(x+1,y-ht*.65),(x+4,y-2)],fill=c[3])
            d.line((x,y-3,x,y-ht*.35),fill=c[4],width=2)
    elif any(s in style for s in ('slash','fan','wave','cone')):
        count=2 if style in ('double_slash','ice_cross') else (3 if style=='triple_slash' else 1)
        for k in range(count):
            angle=(-45+80*t+k*35); rad=26+int(24*env)-k*5
            pts=[]
            for a in range(-75,76,6):
                aa=math.radians(a+angle); pts.append((48+rad*math.cos(aa),65+rad*math.sin(aa)))
            for a in range(75,-76,-6):
                aa=math.radians(a+angle); rr=rad-(8*env+2)*math.cos(math.radians(a));pts.append((48+rr*math.cos(aa),65+rr*math.sin(aa)))
            d.polygon(pts,fill=c[2],outline=c[0]);d.line(pts[:26],fill=c[4],width=2)
        if elem=='water':ring(r,99,2)
        if style=='chain_wave':
            for k in range(8):
                aa=math.radians(-70+k*20+angle);x=48+(rad-5)*math.cos(aa);y=65+(rad-5)*math.sin(aa)
                d.ellipse((x-4,y-2,x+4,y+2),outline=c[1],width=2)
    elif any(s in style for s in ('lightning','linked','electric')):
        ring(r,96,2)
        count=4 if 'field' in style else (3 if 'chain' in style or 'linked' in style else 1)
        for k in range(count):
            if 'field' in style and (t<k*.12 or t>k*.12+.55):continue
            x=64+(k-(count-1)/2)*24 if count>1 else 65
            pts=[(x,17),(x-9,34),(x+3,40),(x-11,61),(x+4,66),(x-2,92)]
            if 'chain' in style or 'linked' in style:
                pts=[(16,55),(33,46),(45,65),(61,51),(78,67),(94,51),(113,58)]
                pts=pts[:max(2,min(7,2+int(t*10)))]
            d.line(pts,fill=c[0],width=9);d.line(pts,fill=c[2],width=5);d.line(pts,fill=c[4],width=2)
        if 'ring' in style:
            for k in range(8):
                aa=k*math.pi/4; x=64+r*math.cos(aa);y=74+r*.5*math.sin(aa)
                d.line([(x-4,y-6),(x+2,y),(x-3,y+6)],fill=c[4],width=2)
    elif elem=='fire':
        ring(r,92,3)
        if style=='fire_pool':
            d.ellipse((64-r+3,92-r*.3,64+r-3,92+r*.3),fill=c[1]);ring(r-7,92,2)
        count=9 if style in ('inferno','fire_pool','fire_ring') else 6
        for k in range(count):
            x=64+(k-(count-1)/2)*10; y=90+7*math.sin(k*2.3)
            ht=(18+22*(.5+.5*math.sin(k*1.7+t*4)))*env
            if style=='fissure':x=25+k*15;y=100-k*8;ht*=1.3
            d.polygon([(x-8,y),(x-6,y-ht*.5),(x-10,y-ht*.7),(x-3,y-ht*.62),(x+1,y-ht),(x+4,y-ht*.43),(x+8,y-ht*.6),(x+8,y)],fill=c[0])
            d.polygon([(x-6,y-2),(x-3,y-ht*.5),(x+1,y-ht+3),(x+5,y-ht*.4),(x+6,y-2)],fill=c[2])
            d.polygon([(x-3,y-2),(x+1,y-ht*.45),(x+4,y-2)],fill=c[4])
    elif elem=='ice':
        ring(r,94,3)
        n=8 if 'blizzard' in style else 6
        for k in range(n):
            aa=k*math.tau/n+t*2; x=64+r*.7*math.cos(aa);y=78+r*.28*math.sin(aa)
            ht=(15+23*(.5+.5*math.sin(k*2)))*env
            if 'blizzard' in style:y-=15+15*math.sin(aa);ht=12
            d.polygon([(x-6,y),(x-7,y-ht*.6),(x,y-ht),(x+6,y-ht*.5),(x+5,y)],fill=c[1],outline=c[0])
            d.polygon([(x,y-ht+2),(x+4,y-ht*.5),(x+3,y-2),(x,y-3)],fill=c[4])
    elif elem=='water':
        ring(r,90,5);ring(max(4,r-12),89,2)
        if style=='pool':
            d.ellipse((64-r+5,84-r*.2,64+r-5,90+r*.2),fill=c[1]);d.arc((64-r+9,84-r*.2,64+r-9,90+r*.2),180,320,fill=c[3],width=2)
        else:
            for k in range(9):
                x=23+k*10;y=25+((k*13+t*60)%59);ht=9 if style=='rain' else int(15+20*env)
                d.line((x,y,x-3,y+ht),fill=c[1],width=5);d.line((x,y,x-2,y+ht-2),fill=c[3],width=2)
    else:
        ring(r,82,5);ring(max(5,r-10),82,2)
        for k in range(10):
            aa=k*math.tau/10;x=64+r*math.cos(aa);y=82+r*.42*math.sin(aa)
            d.polygon([(x-3,y+2),(x,y-8*env),(x+4,y+1)],fill=c[2],outline=c[0])
    # Ordered pixel dissolve gives a clean transparent end without soft alpha.
    if t>.73:
        import numpy as np
        a=np.array(im);yy,xx=np.indices(a.shape[:2]);mask=((xx*3+yy*5)%13)/13 < (t-.73)/.27
        a[mask,3]=0;im=Image.fromarray(a)
    return im

def export_sequence(frames,dst,name,fps=12):
    dst.mkdir(parents=True,exist_ok=True)
    for i,f in enumerate(frames):f.save(dst/f'{name}_{i:02}.png')
    w,h=frames[0].size;sheet=Image.new('RGBA',(w*len(frames),h))
    for i,f in enumerate(frames):sheet.paste(f,(w*i,0))
    sheet.save(dst.parent/f'{name}_sheet.png')
    frames[0].save(dst.parent/f'{name}.webp',save_all=True,append_images=frames[1:],duration=round(1000/fps),loop=0,lossless=True,exact=True)

def build(c,dst):
    shot,area=STYLES[c['id']]
    if shot:export_sequence([sprite_shot(shot,c['element'],i/8) for i in range(8)],dst/'shot','shot')
    if area:export_sequence([effect(area,c['element'],i/11) for i in range(12)],dst/'effect','effect')
    return {'shot':shot or None,'effect':area or None,'fx_frame_size':128,'fx_fps':12,'fx_origin':[64,64],'fx_method':'deterministic hand-authored pixel geometry; separate from H3 character take'}
