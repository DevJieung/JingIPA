#!/usr/bin/env python3
"""Targeted actual muzzle-basis correction proof; no source asset changes."""
import argparse,hashlib,json,subprocess,sys
from pathlib import Path
from PIL import Image,ImageDraw
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from godot_env import ROOT,GODOT,ensure_xvfb,xvfb
p=argparse.ArgumentParser();p.add_argument('--ids',required=True);a=p.parse_args();ensure_xvfb()
base=ROOT/'build/character-3d/review/release-xyz';base.mkdir(parents=True,exist_ok=True);report={}
for cid in a.ids.split(','):
 out=base/cid/'1000x625';out.mkdir(parents=True,exist_ok=True)
 with xvfb(153,'1000x625')as env:
  env['STELLARDEFENSE_NO_SAVE']='1'
  r=subprocess.run([str(GODOT),'--verbose','--path',str(ROOT),'--resolution','1000x625','res://tests/3d/native_character_visual_preview.tscn','--','--id',cid,'--out',str(out),'--release-only'],env=env,capture_output=True,text=True,timeout=600)
 log=r.stdout+'\n'+r.stderr;(out/'render.log').write_text(log)
 if r.returncode or 'ERROR:'in log or '!! 'in log:raise RuntimeError(log[-3000:])
 sheet=Image.new('RGB',(800,560),'#101b27');d=ImageDraw.Draw(sheet)
 for n in range(8):
  im=Image.open(out/f'release_{n:02d}.png').convert('RGBA');im.thumbnail((200,255));x=(n%4)*200;y=(n//4)*280;sheet.paste(im,(x+(200-im.width)//2,y+25),im);d.text((x+5,y+5),f'{cid} release+{n*.02:.2f}',fill='white')
 sheet.save(out/'release_contact.jpg')
 report[cid]={'glb_sha256':hashlib.sha256((ROOT/f'art/models/{cid}/{cid}.glb').read_bytes()).hexdigest(),'adapter_sha256':hashlib.sha256((ROOT/'game/3d/native_character_model.gd').read_bytes()).hexdigest(),'render_errors':0,'release_frames':8,'battle_captured':(out/'battle.png').exists()}
 (base/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('Actual XYZ socket proof',cid,flush=True)
