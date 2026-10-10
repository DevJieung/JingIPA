#!/usr/bin/env python3
"""Capture final actual 12-hero/41-creature fixture, not per-device FPS."""
import argparse, hashlib, json, subprocess, sys
from pathlib import Path
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from godot_env import ROOT,GODOT,ensure_xvfb,xvfb
p=argparse.ArgumentParser();p.add_argument('--compose-only',action='store_true');a=p.parse_args()
ensure_xvfb()
base=ROOT/'build/character-3d/density-review'
report={'device_fps_measured':False,'source_sha256':{},'resolutions':{}}
for folder,key in [('native_heroes.json','heroes'),('native_monsters.json','monsters')]:
    m=json.loads((ROOT/'art/models'/folder).read_text())
    for cid in m['ready_ids']:
        source=ROOT/m[key][cid]['path'].removeprefix('res://')
        report['source_sha256'][cid]=hashlib.sha256(source.read_bytes()).hexdigest()
report['source_sha256']['limne']=hashlib.sha256((ROOT/'art/models/limne/limne.glb').read_bytes()).hexdigest()
for i,res in enumerate(['1280x800','1000x625']):
    out=base/res;out.mkdir(parents=True,exist_ok=True)
    if not a.compose_only:
        with xvfb(217+i,res)as env:
            env['STELLARDEFENSE_NO_SAVE']='1'
            r=subprocess.run([str(GODOT),'--verbose','--path',str(ROOT),'--resolution',res,
                'res://tests/3d/native_density_visual_preview.tscn','--','--density','--out',str(out)],
                env=env,capture_output=True,text=True,timeout=600)
        log=r.stdout+'\n'+r.stderr;(out/'render.log').write_text(log)
        if r.returncode:raise RuntimeError(log[-3000:])
    else:log=(out/'render.log').read_text()
    if 'ERROR:'in log or'!! 'in log or'Actual final native density visual capture:'not in log:raise RuntimeError(log[-3000:])
    metadata=json.loads((out/'battle_metadata.json').read_text())
    if not metadata['all_native']or metadata['distinct_monsters']!=25:raise ValueError('Incomplete actual native density')
    frames=[Image.open(out/f'battle_motion_{n:02d}.png').convert('RGB')for n in range(12)]
    frames[0].save(out/'density-motion.gif',save_all=True,append_images=frames[1:],duration=70,loop=0)
    video=subprocess.run(['ffmpeg','-y','-loglevel','error','-framerate','14',
        '-i',str(out/'battle_motion_%02d.png'),'-c:v','libx264','-pix_fmt','yuv420p',
        '-vf','pad=ceil(iw/2)*2:ceil(ih/2)*2',
        '-crf','20',str(out/'motion.mp4')],capture_output=True,text=True)
    if video.returncode:raise RuntimeError(video.stderr)
    report['resolutions'][res]={'render_errors':0,'screenshots':len(list(out.glob('*.png'))),'actual_actors':metadata}
    (base/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print('Actual final native density',res,flush=True)
