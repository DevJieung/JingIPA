#!/usr/bin/env python3
"""Capture the genuine Limne GLB in Godot, then assemble inspection artifacts."""
import argparse
import json
import hashlib
import subprocess
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from godot_env import ROOT,GODOT,ensure_xvfb,xvfb

p=argparse.ArgumentParser();p.add_argument('--res',action='append');p.add_argument('--compose-only',action='store_true');args=p.parse_args()
ensure_xvfb()
font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',19)

def sheet(paths,labels,dest,cell=(320,430),columns=4):
    out=Image.new('RGB',(cell[0]*columns,cell[1]*((len(paths)+columns-1)//columns)),(15,27,40))
    draw=ImageDraw.Draw(out)
    for i,(path,label) in enumerate(zip(paths,labels)):
        shot=Image.open(path).convert('RGBA')
        box=shot.getbbox()
        if box: shot=shot.crop(box)
        shot.thumbnail((cell[0]-24,cell[1]-60))
        x=(i%columns)*cell[0]+(cell[0]-shot.width)//2;y=(i//columns)*cell[1]+36
        out.paste(shot,(x,y),shot)
        draw.text(((i%columns)*cell[0]+12,(i//columns)*cell[1]+10),label,font=font,fill=(231,235,241))
    out.save(dest)

BASE=ROOT/'build/limne-game-motion'
report={'renderer':'Godot GL Compatibility','device_fps_measured':False,
    'quality_status':'accepted Limne shape; stylized game material and articulated motion revision',
    'glb_sha256':hashlib.sha256((ROOT/'art/models/limne/limne.glb').read_bytes()).hexdigest(),
    'resolutions':{}}
report_path=BASE/'game-review/report.json'
report_path.parent.mkdir(parents=True,exist_ok=True)
if not args.compose_only:report_path.write_text(json.dumps(report,indent=2)+'\n')
for index,res in enumerate([] if args.compose_only else args.res or ['1280x800','1000x625']):
    out=BASE/'game-review'/res;out.mkdir(parents=True,exist_ok=True)
    with xvfb(111+index,res) as env:
        result=subprocess.run([str(GODOT),'--verbose','--path',str(ROOT),'--resolution',res,
            'res://tests/3d/limne_visual_preview.tscn','--','--out',str(out)],
            env=env,capture_output=True,text=True,timeout=600)
    log=result.stdout+'\n'+result.stderr;(out/'render.log').write_text(log)
    if result.returncode or 'ERROR:' in log or '!! ' in log:
        report['resolutions'][res]={'render_errors':1,'exit_code':result.returncode}
        report_path.write_text(json.dumps(report,indent=2)+'\n')
        print(log);raise SystemExit(1)
    views=['front','side','back','three_quarter']
    sheet([out/f'gallery_{v}.png' for v in views],views,out/'turnaround.jpg')
    grades=['grade_00','grade_04','grade_09','awakened']
    sheet([out/f'{v}.png' for v in grades],['Grade 0','Grade 4','Grade 9','Awakened'],out/'grades.jpg')
    sequences={}
    for state,count in [('idle',60),('attack',40),('battle_motion',8)]:
        frames=[Image.open(out/f'{state}_{n:02d}.png').convert('RGBA') for n in range(count)]
        rgb=[]
        for frame in frames:
            base=Image.new('RGBA',frame.size,(15,27,40,255));base.alpha_composite(frame)
            rgb.append(base.convert('RGB'))
        sequences[state]=rgb
        rgb[0].save(out/f'{state}.gif',save_all=True,append_images=rgb[1:],duration=100 if state=='idle' else 40 if state=='attack' else 90,loop=0)
        chosen=list(range(0,count,max(1,count//12)))[:12]
        sheet([out/f'{state}_{n:02d}.png' for n in chosen],
            [f'{state} {n:02d}' for n in chosen],out/f'{state}_contact.jpg',cell=(260,340))
    combined=sequences['idle'][:30]+sequences['attack']+sequences['idle'][:20]
    durations=[100]*30+[40]*40+[100]*20
    combined[0].save(out/'motion.gif',save_all=True,append_images=combined[1:],duration=durations,loop=0)
    # CFR video uses the same actual captured frames; no generated image poses.
    video_frames=out/'video-frames';video_frames.mkdir(exist_ok=True)
    index=0
    for frame,duration in zip(combined,durations):
        for repeat in range(round(duration/20)):
            frame.save(video_frames/f'{index:04d}.png');index+=1
    video=subprocess.run(['ffmpeg','-y','-loglevel','error','-framerate','50','-i',str(video_frames/'%04d.png'),
        '-c:v','libx264','-pix_fmt','yuv420p','-crf','20',str(out/'motion.mp4')],capture_output=True,text=True)
    if video.returncode:raise RuntimeError(video.stderr)
    # Inspection comparison only; the original sprite/portrait remain untouched.
    ref=BASE/'game-review/reference'
    ref.mkdir(parents=True,exist_ok=True)
    idle=Image.open(ROOT/'art/anim/limne/limne_idle.png').convert('RGBA')
    idle.crop((0,0,idle.width//8,idle.height)).save(ref/'sprite_frame.png')
    sheet([BASE/'before/game/gallery_three_quarter.png',out/'gallery_three_quarter.png'],
        ['Accepted figure materials','Game style materials'],out/'style_before_after.jpg',columns=2)
    report['resolutions'][res]={'screenshots':len(list(out.glob('*.png'))),
        'model_geometry':json.loads((out/'model_geometry.json').read_text()),'render_errors':0}
    report_path.write_text(json.dumps(report,indent=2)+'\n')
    print(res,'Limne GLB captures completed')
if not args.compose_only:report_path.write_text(json.dumps(report,indent=2)+'\n')
# Larger side-by-side proof shows the actual offline render beside the rejected
# model and source. Raster target is explicitly labelled in a separate panel.
studio=BASE/'studio'
if (studio/'three_quarter.png').exists():
    views=['front','side','back','three_quarter']
    sheet([studio/(v+'.png') for v in views],views,studio/'turnaround.jpg',cell=(480,660))
    sheet([BASE/'before/studio/three_quarter.png',studio/'three_quarter.png'],
        ['Accepted previous materials','Stylized game materials'],studio/'style_before_after.jpg',cell=(480,660),columns=2)
portraits=ROOT/'art/models/portraits/limne'
names=[f'{i:02d}' for i in range(10)]+['00_awakened']
if all((portraits/(v+'.png')).exists() for v in names):
    sheet([portraits/(v+'.png') for v in names],names,BASE/'portraits.jpg',cell=(224,280),columns=6)
    audit={}
    for name in names:
        im=Image.open(portraits/(name+'.png')).convert('RGBA');box=im.getchannel('A').getbbox()
        audit[name]={'size':im.size,'alpha_bounds':box,'minimum_margin':min(box[0],box[1],im.width-box[2],im.height-box[3]) if box else None}
    (BASE/'portrait-audit.json').write_text(json.dumps(audit,indent=2)+'\n')
