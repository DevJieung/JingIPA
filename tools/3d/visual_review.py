#!/usr/bin/env python3
"""Capture actual Godot 3D screens at both mobile sizes; audit portrait margins."""
import argparse,json,subprocess,sys
from pathlib import Path
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from godot_env import ROOT,GODOT,ensure_xvfb,xvfb
p=argparse.ArgumentParser();p.add_argument('--res',action='append');args=p.parse_args()
ensure_xvfb()
for index,res in enumerate(args.res or ['1280x800','1000x625']):
 out=ROOT/'build/stellar-3d'/res;out.mkdir(parents=True,exist_ok=True)
 with xvfb(96+index,res) as env:
  result=subprocess.run([str(GODOT),'--path',str(ROOT),'--resolution',res,'res://tests/3d/stellar_visual_preview.tscn','--','--out',str(out)],env=env,capture_output=True,text=True,timeout=600)
 (out/'render.log').write_text(result.stdout+'\n'+result.stderr)
 if result.returncode or 'ERROR:' in result.stderr: print(result.stderr);sys.exit(1)
 for locale in ['ko','en']:
  frames=[Image.open(out/f'{locale}_motion_{n:02d}.png').convert('RGB') for n in range(12)]
  frames[0].save(out/f'{locale}_battle_motion.gif',save_all=True,append_images=frames[1:],duration=110,loop=0)
  thumbs=[im.copy() for im in frames]
  for im in thumbs: im.thumbnail((426,267))
  contact=Image.new('RGB',(426*4,267*3),(12,22,32))
  for n,im in enumerate(thumbs):contact.paste(im,(n%4*426,n//4*267))
  contact.save(out/f'{locale}_motion_contact.jpg',quality=92)
 print(res,'actual screen captures passed')
files=list((ROOT/'art/models/portraits').glob('*/*.png'));bad=[]
for path in files:
 image=Image.open(path).convert('RGBA');box=image.getchannel('A').point(lambda v:255 if v>32 else 0).getbbox()
 if not box or box[0]<4 or box[1]<4 or box[2]>image.width-4 or box[3]>image.height-4:bad.append(str(path.relative_to(ROOT)))
report={'hero_portraits':len(files),'boundary_failures':bad,'resolutions':args.res or ['1280x800','1000x625'],'model_source':'game/3d/stellar_models.gd','reference':'https://www.youtube.com/watch?v=7gyIit5TtsI'}
(ROOT/'build/stellar-3d/visual-audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print('Portrait coverage',len(files),'boundary failures',len(bad))
sys.exit(1 if bad or len(files)!=550 else 0)
