#!/usr/bin/env python3
"""Actual Godot native hero captures; preserve source/old proof separately."""
import argparse,fcntl,hashlib,json,os,subprocess,sys
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from godot_env import ROOT,GODOT,ensure_xvfb,xvfb

p=argparse.ArgumentParser();p.add_argument('--ids',default='echo,brasa,pip')
p.add_argument('--res',action='append');p.add_argument('--candidate-only',action='store_true')
p.add_argument('--compose-only',action='store_true');p.add_argument('--display-base',type=int,default=120);a=p.parse_args()
ensure_xvfb();base=ROOT/'build/character-3d';font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',18)
def sheet(paths,labels,dest,columns=4,cell=(270,355)):
    im=Image.new('RGB',(columns*cell[0],((len(paths)+columns-1)//columns)*cell[1]),(15,27,40));d=ImageDraw.Draw(im)
    for i,(path,label) in enumerate(zip(paths,labels)):
        pic=Image.open(path).convert('RGBA');pic.thumbnail((cell[0]-20,cell[1]-45))
        x=(i%columns)*cell[0]+(cell[0]-pic.width)//2;y=(i//columns)*cell[1]+35
        im.paste(pic,(x,y),pic);d.text(((i%columns)*cell[0]+10,(i//columns)*cell[1]+7),label,font=font,fill=(235,243,247))
    im.save(dest)
report_path=base/'review/report.json';report_path.parent.mkdir(parents=True,exist_ok=True)
report=json.loads(report_path.read_text()) if report_path.exists() else {'renderer':'Godot GL Compatibility','device_fps_measured':False,'heroes':{}}
for cid in a.ids.split(','):
    baseline=base/'baseline'/cid;baseline.mkdir(parents=True,exist_ok=True)
    old=baseline/'old-3d.png'
    if not old.exists():old.write_bytes((ROOT/f'art/models/portraits/{cid}/00.png').read_bytes())
    model=ROOT/f'art/models/{cid}/{cid}.glb'
    row=report['heroes'].setdefault(cid,{'resolutions':{}});row['glb_sha256']=hashlib.sha256(model.read_bytes()).hexdigest()
    for ri,res in enumerate(a.res or ['1280x800','1000x625']):
        out=base/'review'/cid/res;out.mkdir(parents=True,exist_ok=True)
        if not a.compose_only:
            with xvfb(a.display_base+ri,res) as env:
                command=[str(GODOT),'--verbose','--path',str(ROOT),'--resolution',res,
                    'res://tests/3d/native_character_visual_preview.tscn','--','--id',cid,'--out',str(out)]
                if a.candidate_only:command.append('--candidate-only')
                result=subprocess.run(command,env=env,capture_output=True,text=True,timeout=600)
            log=result.stdout+'\n'+result.stderr;(out/'render.log').write_text(log)
            if result.returncode or 'ERROR:' in log or '!! ' in log:print(log);raise SystemExit(1)
        views=['front','side','back','three_quarter']
        sheet([out/f'gallery_{v}.png' for v in views],views,out/'turnaround.jpg')
        grades=['grade_00','grade_04','grade_09','awakened']
        sheet([out/(v+'.png') for v in grades],grades,out/'grades.jpg')
        seq={}
        for state,count,duration in [('idle',24,250),('attack',40,30),('battle_motion',8,90),('walk',24,33),('walk_stop',24,33),
                                     ('walk_curve',24,33),('turn',16,33),('aim',12,50),('walk_attack',24,33)]:
            if not (out/f'{state}_00.png').exists():continue
            frames=[]
            for n in range(count):
                pic=Image.open(out/f'{state}_{n:02d}.png').convert('RGBA');im=Image.new('RGBA',pic.size,(15,27,40,255));im.alpha_composite(pic);frames.append(im.convert('RGB'))
            seq[state]=frames;frames[0].save(out/f'{state}.gif',save_all=True,append_images=frames[1:],duration=duration,loop=0)
            chosen=list(range(0,count,max(1,count//12)))[:12]
            sheet([out/f'{state}_{n:02d}.png' for n in chosen],[f'{state} {n:02d}' for n in chosen],out/f'{state}_contact.jpg')
        frames=seq['idle'][:12]+seq['attack']+seq['idle'][:8];durations=[250]*12+[30]*40+[250]*8
        frames[0].save(out/'motion.gif',save_all=True,append_images=frames[1:],duration=durations,loop=0)
        if 'walk' in seq:
            loco=seq['walk']+seq['walk_stop']+seq['walk_curve']+seq['turn']+seq['aim']+seq['walk_attack']
            loco_durations=[33]*(len(seq['walk'])+len(seq['walk_stop'])+len(seq['walk_curve'])+len(seq['turn']))+[50]*len(seq['aim'])+[33]*len(seq['walk_attack'])
            loco[0].save(out/'locomotion.gif',save_all=True,append_images=loco[1:],duration=loco_durations,loop=0)
            frames=frames+loco;durations=durations+loco_durations
        # Save each actual frame once, retaining its hold duration. Hundreds
        # of duplicated full-size PNGs added I/O but no visual evidence.
        folder=out/'video-keyframes';folder.mkdir(exist_ok=True);lines=[]
        for n,(frame,duration) in enumerate(zip(frames,durations)):
            key=folder/f'{n:04d}.png';frame.save(key)
            lines.extend(["file '"+str(key)+"'",f'duration {duration/1000:.6f}'])
        lines.append("file '"+str(key)+"'")
        timeline=folder/'timeline.txt';timeline.write_text('\n'.join(lines)+'\n')
        video=subprocess.run(['ffmpeg','-y','-loglevel','error','-f','concat','-safe','0','-i',str(timeline),'-r','30','-fps_mode','cfr','-c:v','libx264','-pix_fmt','yuv420p','-crf','20',str(out/'motion.mp4')],capture_output=True,text=True)
        if video.returncode:raise RuntimeError(video.stderr)
        ref=base/'references'/cid/'apose.png'
        if not ref.exists():ref=base/'references'/cid/'target.png'
        if ref.exists():sheet([ROOT/f'build/hero-native/inputs/{cid}.png',old,ref,out/'gallery_three_quarter.png'],['Original 2D','Previous primitive 3D','AI RASTER reference','Actual native GLB'],out/'comparison.jpg')
        row['resolutions'][res]={'screenshots':len(list(out.glob('*.png'))),'render_errors':0,
            'battle_captured':(out/'battle.png').exists(),'model_geometry':json.loads((out/'model_geometry.json').read_text())}
        # Independent capture groups may use different X displays. Merge
        # only this frozen ID/resolution so their reports cannot erase peers.
        with (base/'review/report.lock').open('a') as lock:
            fcntl.flock(lock,fcntl.LOCK_EX)
            latest=json.loads(report_path.read_text()) if report_path.exists() else {'renderer':'Godot GL Compatibility','device_fps_measured':False,'heroes':{}}
            merged=latest['heroes'].setdefault(cid,{'resolutions':{}})
            merged['glb_sha256']=row['glb_sha256'];merged['resolutions'][res]=row['resolutions'][res]
            temporary=report_path.with_suffix('.tmp.'+str(os.getpid()))
            temporary.write_text(json.dumps(latest,indent=2)+'\n');temporary.replace(report_path)
            fcntl.flock(lock,fcntl.LOCK_UN)
        print('Actual native QA captures',cid,res,flush=True)
