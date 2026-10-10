#!/usr/bin/env python3
"""Actual Godot creature multiview/loop/status/density proof, not source edits."""
import argparse,hashlib,json,subprocess,sys,fcntl
from pathlib import Path
from PIL import Image,ImageDraw
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from godot_env import ROOT,GODOT,ensure_xvfb,xvfb
p=argparse.ArgumentParser();p.add_argument('--ids',required=True);p.add_argument('--res',action='append');p.add_argument('--density',action='store_true');p.add_argument('--compose-only',action='store_true');p.add_argument('--display-base',type=int,default=167);a=p.parse_args();ensure_xvfb()
base=ROOT/'build/character-3d/monster-review';base.mkdir(parents=True,exist_ok=True)
rp=base/'report.json';report=json.loads(rp.read_text())if rp.exists()else{'renderer':'Godot GL Compatibility','device_fps_measured':False,'monsters':{}}
def contact(paths,labels,dest,columns=4):
 s=Image.new('RGB',(columns*240,((len(paths)+columns-1)//columns)*310),'#102030');d=ImageDraw.Draw(s)
 for n,(path,label)in enumerate(zip(paths,labels)):
  im=Image.open(path).convert('RGBA');im.thumbnail((230,270));x=(n%columns)*240;y=(n//columns)*310;s.paste(im,(x+(240-im.width)//2,y+30),im);d.text((x+5,y+5),label,fill='white')
 s.save(dest)
for cid in a.ids.split(','):
 glb=ROOT/f'art/models/monsters/{cid}/{cid}.glb';sha=hashlib.sha256(glb.read_bytes()).hexdigest()
 baseline=ROOT/'build/character-3d/monster-baseline'/cid;baseline.mkdir(parents=True,exist_ok=True)
 old=baseline/'old-3d.png'
 if not old.exists():old.write_bytes((ROOT/f'art/models/monsters/{cid}.png').read_bytes())
 row=report['monsters'].setdefault(cid,{'resolutions':{}});row['glb_sha256']=sha
 for i,res in enumerate(a.res or['1280x800','1000x625']):
  out=base/cid/res;out.mkdir(parents=True,exist_ok=True)
  if not a.compose_only:
   with xvfb(a.display_base+i,res)as env:
    env['STELLARDEFENSE_NO_SAVE']='1'
    cmd=[str(GODOT),'--verbose','--path',str(ROOT),'--resolution',res,'res://tests/3d/native_monster_visual_preview.tscn','--','--id',cid,'--out',str(out)]
    if a.density:cmd.append('--density')
    r=subprocess.run(cmd,env=env,capture_output=True,text=True,timeout=600)
   log=r.stdout+'\n'+r.stderr;(out/'render.log').write_text(log)
   if r.returncode or'ERROR:'in log or'!! 'in log:raise RuntimeError(log[-4000:])
  else:
   log=(out/'render.log').read_text()
   if 'ERROR:'in log or'!! 'in log or('Actual native creature visual capture: '+cid)not in log:
    raise RuntimeError('Compose requires successful actual native capture '+cid+' '+res)
  views=['front','side','back','three_quarter'];contact([out/f'gallery_{v}.png'for v in views],views,out/'turnaround.jpg')
  sequences={}
  # Reaction sequences have a variable length (death stops when the body reports done).
  for state,count,ms in [('idle',24,125),('move',32,33),('battle_motion',12,70),('turn',16,33),('blocked',12,66),('siege',30,33),('hit',8,50),('spawn',14,33),('die',48,33)]:
   frames=[]
   for n in range(count):
    path=out/f'{state}_{n:02d}.png'
    if not path.exists():break
    im=Image.open(path).convert('RGBA');background=Image.new('RGBA',im.size,'#102030');background.alpha_composite(im);frames.append(background.convert('RGB'))
   if not frames:raise RuntimeError('Missing capture '+state+' '+cid)
   frames[0].save(out/(state+'.gif'),save_all=True,append_images=frames[1:],duration=ms,loop=0)
   selected=list(range(0,len(frames),max(1,len(frames)//12)))[:12];contact([out/f'{state}_{n:02d}.png'for n in selected],[f'{state} {n}'for n in selected],out/(state+'_contact.jpg'));sequences[state]=frames
  frames=sequences['idle'][:8]+sequences['move'];durations=[125]*8+[33]*32
  frames[0].save(out/'motion.gif',save_all=True,append_images=frames[1:],duration=durations,loop=0)
  reaction=[];reaction_ms=[]
  for state,ms in [('spawn',40),('turn',40),('hit',66),('blocked',66),('siege',40),('die',40)]:
   reaction+=sequences[state];reaction_ms+=[ms]*len(sequences[state])
  reaction[0].save(out/'reactions.gif',save_all=True,append_images=reaction[1:],duration=reaction_ms,loop=0)
  strip=[];labels=[]
  for state,picks in [('spawn',[0,4,8,13]),('turn',[0,5,10,15]),('hit',[0,1,3,6]),('siege',[18,24,27,29]),('die',[0,10,20,len(sequences['die'])-1])]:
   for n in picks:
    n=min(n,len(sequences[state])-1);strip.append(out/f'{state}_{n:02d}.png');labels.append(f'{state} {n}')
  contact(strip,labels,out/'reactions_contact.jpg',columns=4)
  folder=out/'video-frames';folder.mkdir(exist_ok=True);index=0
  for im,ms in zip(frames,durations):
   for _ in range(max(1,round(ms/33))):im.save(folder/f'{index:04d}.png');index+=1
  r=subprocess.run(['ffmpeg','-y','-loglevel','error','-framerate','30','-i',str(folder/'%04d.png'),'-c:v','libx264','-pix_fmt','yuv420p','-crf','20',str(out/'motion.mp4')],capture_output=True,text=True)
  if r.returncode:raise RuntimeError(r.stderr)
  contact([ROOT/f'build/monster-native/inputs/{cid}.png',old,ROOT/f'build/character-3d/monster-references/{cid}/bind-reference.png',out/'gallery_three_quarter.png'],['Original active sprite','Previous primitive3D','AI RASTER reference','Actual nativeGLB'],out/'comparison.jpg')
  row['resolutions'][res]={'screenshots':len(list(out.glob('*.png'))),'render_errors':0,'battle_captured':(out/'battle.png').exists(),'density_count':41 if a.density else 12,'heroes':12,'model_geometry':json.loads((out/'model_geometry.json').read_text()),'reaction_frames':{k:len(v)for k,v in sequences.items()},'motion_version':2}
  with (base/'report.lock').open('a')as lock:
   fcntl.flock(lock,fcntl.LOCK_EX)
   latest=json.loads(rp.read_text())if rp.exists()else{'renderer':'Godot GL Compatibility','device_fps_measured':False,'monsters':{}}
   latest['monsters'][cid]=row
   temp=rp.with_suffix('.tmp');temp.write_text(json.dumps(latest,indent=2)+'\n');temp.replace(rp)
   fcntl.flock(lock,fcntl.LOCK_UN)
  print('Actual native creature QA',cid,res,flush=True)
