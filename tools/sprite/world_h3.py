#!/usr/bin/env python3
"""V3 pixel roster -> one H3 turn/idle/attack take per unit; resumable."""
from __future__ import annotations
import argparse
import json
import sys
import time
import subprocess
import urllib.request
import urllib.parse
from pathlib import Path
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/sprite'))
sys.path.insert(0, str(ROOT / 'tools'))
import h3_i2v as h3
import gpu_guard

OUT = ROOT / 'art/animation/last_refuge_v3_pixel_h3'
SOURCE = ROOT / 'art/concepts/last_refuge_v3_pixel'
FRAMES = 141
SIZE = 768

# Body/equipment actions only. The Korean design remains alongside the English
# motion direction in the manifest. Root-travelling actions are adapted in place.
ACTIONS = {
 'limne': 'bend slightly at the waist, extend both wrist nozzles diagonally down toward frame right, hold the release pose, then straighten and lower both arms',
 'phorkys': 'draw the large water revolver, aim right with a braced elbow, perform six small recoil pulses, pull its pump handle and lower it',
 'protea': 'bring the triple-limbed bow forward, draw its three guides together once, release the string once and lower the bow',
 'marea': 'unlock the hose reel, swing the hose with one broad horizontal arm semicircle to the right, and reel it back',
 'glaukos': 'bend the knees slightly with the sword tip low, execute one strong rising sword cut toward frame right, then return to guard',
 'thalassa': 'open the chest valve with both hands, raise the reservoir ring above the head, hold both palms forward, and close the valve',
 'triton': 'brace the trumpet-shaped cannon on the shoulder, lock the pressure gauge, aim right, show one heavy upper-body recoil, then relax',
 'keto': 'raise the bow, close its two pressure chambers, draw the string slowly to the cheek, release once to the right, and relax',
 'galene': 'rotate the two wrist reservoirs in opposite directions, whip the wrist and hose through a wide horizontal semicircle, and recover',
 'nerea': 'open the back sluice, raise the greatsword overhead with both hands, deliver one vertical downward cut toward frame right, then recover',
 'chispa': 'turn the ignition wheel with the thumb, extend the pistol to the right, give one sharp recoil, open the chamber and reload',
 'solana': 'brush the arrow rest against the ignition jaw, raise the bow to chest level, draw and release the string once toward frame right, and recover',
 'ceniza': 'lower the torso and sweep the chain brush close to the ground toward frame right, then pull the chain back',
 'igni': 'bring the sword behind the upper body, twist the waist into one wide horizontal sword slash toward frame right, and recover',
 'volcan': 'raise both piston gauntlets, bend the knees without lifting either foot, hammer both fists down in front, then rise',
 'carmen': 'alternately extend the two pistols toward frame right with four brisk recoil pulses, open their side cooling fins, and lower both arms',
 'saeta': 'look diagonally upward to the right, raise the heavy bow, draw it fully, release once at an upward angle, and recover',
 'candela': 'swing the chain overhead and around the torso in one broad circle using only waist and arm rotation, then gather the chain',
 'estoque': 'keep both feet planted, aim the rapier right, extend the piston arm into a long precise thrust using upper-body lean only, then retract',
 'brasa': 'brace the knees, press both hand locks, open the back radiator doors, thrust both palms down, then close the doors and recover',
 'lind': 'pull the chain toward the elbow, snap its three ice joints forward toward frame right, then retract the chain',
 'jokull': 'raise the sword over one shoulder and deliver a long diagonal downward cut toward frame right, then recover',
 'vidarr': 'keep BOTH feet firmly planted, compress the large leg tanks with a deep knee bend, press both palms down forcefully, then rise',
 'kari': 'brace the double-barrel gun at chest height, aim right, give one simultaneous recoil from both barrels, then lower the gun',
 'eira': 'bring the arrow rest to the hexagonal mold, draw the bowstring to the ear, release once rightward, and return to guard',
 'snorri': 'swing the chain anchor low toward frame right while gripping its tether, lean the upper body back to winch it in, and recover',
 'helga': 'raise both swords beside the shoulders, execute two alternating diagonal cuts making an X toward frame right, and recover',
 'sigrid': 'rotate the wrist disks outward, open the four back turbines, hold both palms toward frame right, then sharply stop the turbines and lower the hands',
 'frosti': 'pull the rifle bolt with the left hand, brace the support frame, aim right and hold breath, show one precise recoil, then cycle the bolt',
 'isa': 'brace both shoulders, lean back with feet fixed to draw the giant bow fully, hold briefly, release once rightward, and recover',
 'brigid': 'raise the electrode bow, pull the string taut, release once toward frame right, and lower the bow',
 'rhiannon': 'unspool the cable reel, sweep the tethered clamp horizontally to the right, hold the grip firm, then reel it back',
 'finn': 'aim the short blade toward frame right, extend the elbow into two quick precise thrusts without stepping, then let the spring arm retract',
 'donn': 'spread one palm low toward frame right, raise the other hand beside the back lightning rod, press the first palm down, then recover',
 'conor': 'raise the pistol in one hand, aim right, deliver five small controlled recoil pulses, and lower it',
 'niamh': 'raise the bow and perform three quick draw-and-release cycles from the same planted stance toward frame right, then recover',
 'morrigan': 'raise one arm overhead, rotate the tethered chain in a broad loop around the upper body, slow the loop, then reel it back',
 'caden': 'grip the large green-and-silver sword hilt with both hands, lift the entire long blade from its low resting position above the right shoulder, then swing the sword itself in three visible arcs toward frame right: a diagonal cut, a horizontal cut and a downward cut; the blade follows the hands and finishes pointing diagonally right',
 'lugh': 'spread both arms widely beside the twin coils, draw the hands forward and press both palms downward, then recover',
 'brian': 'lock both foot grounding pins, raise the rail-cannon prosthetic arm toward frame right, hold the aim, show one heavy shoulder recoil, and lower the arm',
 'pip': 'turn the small winding key once, make one short forward blade slash toward frame right, and snap back to guard',
 'mimic': 'pull both plate palms back to compress the arms, thrust both palms forward toward frame right, then retract',
 'dummy': 'turn the head toward frame right, raise the gun, give exactly three controlled recoil pulses, open the three chamber vents, and recover',
 'echo': 'raise the bow, draw and release once to the right, allow the clockwork grip to reset, draw and release a second time, and recover',
 'shift': 'sweep one arm broadly to the right, extend the segmented tethered blades in sequence along a wide arc, then retract them along the same path',
 'phantom': 'grip the long silver sword hilt with both hands, lift the entire blade from its low resting position above the right shoulder, then swing the sword itself in a broad horizontal cut toward frame right; the long blade visibly follows both hands across the body, the secondary blade follows the main blade, and both finish pointing toward frame right',
 'blank': 'push both shield panels outward, drive both forearm stakes down in front with feet planted, then fold the panels and recompress',
 'grey': 'lower the head to align the three scope lenses, aim the heavy gun right, pause, give one heavy recoil and recover slowly',
 'null': 'fix the shoulders and draw the bowstring slowly to full tension, hold one beat, release once toward frame right, and recover',
 'zero': 'raise the connector wrist, swing the tethered chain through one broad horizontal arc toward frame right, then retract it',
}

def savejson(path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=2))

def prepare(c):
    dst = OUT/c['id']; dst.mkdir(parents=True, exist_ok=True)
    im = Image.open(SOURCE/(c['id']+'.png')).convert('RGB')
    a = np.asarray(im).astype(np.int16)
    # Warm paper is almost neutral; remove only connected exterior and enclosed
    # paper holes. Dark outlines protect skin and light costume panels.
    border = np.concatenate([a[0],a[-1],a[:,0],a[:,-1]])
    paper = np.median(border,axis=0)
    candidate = (np.max(abs(a-paper),axis=2)<45) & (a.min(axis=2)>170)
    labels,n = ndi.label(candidate)
    edgeids = np.unique(np.concatenate([labels[0],labels[-1],labels[:,0],labels[:,-1]]))
    bg=np.isin(labels,edgeids[edgeids>0])
    # Large enclosed holes of the same paper color are also background.
    counts=np.bincount(labels.ravel())
    for lab in range(1,n+1):
        if counts[lab]>500 and np.max(abs(np.median(a[labels==lab],axis=0)-paper))<15: bg[labels==lab]=True
    rgba=np.dstack([np.asarray(im),np.where(bg,0,255).astype('uint8')])
    matte=ROOT/'art/animation/last_refuge_v3_pixel_h3/_source_mattes'/(c['id']+'.png')
    cut=Image.open(matte).convert('RGBA') if matte.exists() else Image.fromarray(rgba)
    box=cut.getbbox(); cut=cut.crop(box)
    # Leave room for an overhead blade/bow and the full rightward arm extension.
    height=c.get('motion_height',360 if c['weapon'] in ('bow','sword') else 420)
    scale=min(c.get('motion_width',400)/cut.width,height/cut.height)
    cut=cut.resize((round(cut.width*scale),round(cut.height*scale)),Image.Resampling.NEAREST)
    alpha=np.array(cut.getchannel('A'))>0;foot_x=np.where(alpha[-8:])[1]
    foot_mid=round((int(foot_x.min())+int(foot_x.max()))/2)
    canvas=Image.new('RGBA',(SIZE,SIZE)); canvas.alpha_composite(cut,(c.get('motion_anchor_x',320)-foot_mid,650-cut.height))
    canvas.save(dst/'input_transparent.png')
    key=Image.new('RGB',(SIZE,SIZE),(255,0,255));key.paste(canvas,mask=canvas.getchannel('A'));key.save(dst/'input.png')
    savejson(dst/'input_meta.json',{'background_removal':'BiRefNet CPU' if matte.exists() else 'legacy paper key','source':str(SOURCE/(c['id']+'.png')),'body_height_limit':height,'foot_anchor_x':c.get('motion_anchor_x',320)})
    return dst/'input.png'

def prompt(c):
    return ('How the reference pictures align with the target video — Picture 1 (from Shot 1) aligns with the 0.00-second mark of the target video; Picture 2 (from Shot 1) aligns with the 5.88-second mark of the target video.\n\n'
      'integrated_multimodal_description: [Shot 1] One single continuous 2D pixel-art sprite animation take with no cuts or scene changes. A single full-body character from the reference on a perfectly uniform flat magenta background. '
      + h3.CAMERA.format(S='5.88') +
      'The two soles are glued to their exact original pixel coordinates for the entire shot. The feet never lift, slide, step or change separation. '
      'The hips remain over this fixed base. The character has exactly the same body size throughout, framed slightly left of center with generous empty space toward frame right. '
      '0.00-0.80 seconds: lower the T-pose arms into a natural ready stance, turn the head and upper body to face FRAME RIGHT while keeping both soles fixed. '
      '0.80-2.40 seconds: hold a clear right-facing three-quarter side view and perform ONE gentle idle breathing cycle; shoulders rise slightly then settle, equipment remains still. '
      '2.40-5.10 seconds: still facing FRAME RIGHT, '+ACTIONS[c['id']]+'. '
      '5.10-5.88 seconds: smoothly return to the exact original pose and framing of Picture 2, identical to Picture 1. '
      'This is an unloaded dry practice gesture. Only the body and attached equipment animate. Nothing leaves the equipment. '
      'Keep the original outfit, face and especially the unusual custom equipment, its exact shape and colors; keep the same chunky pixel grid and hard outlines. Everything fits within the frame. '
      'Exactly one actor and its attached equipment occupy the canvas. The surrounding canvas remains perfectly flat, uniform solid magenta throughout. All background pixels and lighting remain constant.\n\n'
      'overall_soundscape: Silent.\n\nnon_diegetic_music: None.')

def generate(c):
    dst=OUT/c['id']; raw=dst/'raw'; meta=dst/'generation.json'
    if meta.exists() and len(list(raw.glob('f_*.png')))==FRAMES: return
    resume=dst/'resume_prompt.json'
    if resume.exists():
        state=json.loads(resume.read_text());g=state['workflow'];pos=g['cond']['inputs']['prompt']
        seed=g['noise']['inputs']['noise_seed'];src=dst/'input.png';t=state['started'];pid=state['prompt_id']
    else:
        src=prepare(c); pos=prompt(c); seed=c.get('motion_seed',7)
        name=h3.upload(str(src),'world_v3_'+c['id']+'.png')
        g=h3.graph(name,pos,seed=seed,frames=FRAMES,size=SIZE,steps=4,turbo=4,pin_last=True,prefix='pocker_world_v3/'+c['id'])
        t=time.time();pid=h3._post('/prompt',{'prompt':g})['prompt_id']
        savejson(resume,{'prompt_id':pid,'workflow':g,'started':t})
    savejson(dst/'workflow.json',g); (dst/'prompt.txt').write_text(pos)
    while True:
        history=h3._get('/history/'+pid)
        if pid in history:break
        if time.time()-t>3600:raise RuntimeError('H3 timeout: '+c['id'])
        time.sleep(3)
    result=history[pid]
    if result.get('status',{}).get('status_str')=='error':raise RuntimeError(str(result['status']))
    items=[]
    for node in result['outputs'].values():items+=node.get('images',[])
    raw.mkdir(parents=True,exist_ok=True)
    for i,it in enumerate(sorted(items,key=lambda x:x['filename'])):
        q=urllib.parse.urlencode({'filename':it['filename'],'subfolder':it.get('subfolder',''),'type':it.get('type','output')})
        with urllib.request.urlopen('http://'+h3.HOST+'/view?'+q,timeout=120) as r:(raw/f'f_{i:04}.png').write_bytes(r.read())
    n=len(items)
    if n!=FRAMES: raise RuntimeError(f'{c["id"]}: expected {FRAMES}, got {n}')
    savejson(meta,{'model':h3.UNET,'turbo':h3.TURBO[4],'seed':seed,'fps':24,'frames':n,'pin_last':True,'elapsed_seconds':round(time.time()-t,1),'source':str(src.relative_to(ROOT)),'character':c,'windows_seconds':{'turn':[0,.8],'idle':[.8,2.4],'attack':[2.4,5.1],'return_to_input':[5.1,5.875]}})
    subprocess.run(['ffmpeg','-v','error','-y','-framerate','24','-i',str(raw/'f_%04d.png'),'-c:v','libx264','-crf','18','-pix_fmt','yuv420p',str(dst/'source.mp4')],check=True)
    print(f'  {c["id"]}: {n} frames {time.time()-t:.0f}s',flush=True)

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--only',default='');ap.add_argument('--prepare',action='store_true');a=ap.parse_args()
    chars=json.loads((ROOT/'art/concepts/last_refuge_v3/characters.json').read_text())
    if a.only: chars=[c for c in chars if c['id'] in a.only.split(',')]
    assert all(c['id'] in ACTIONS for c in chars)
    if not a.prepare: gpu_guard.claim('h3')
    for c in chars:
        print('START',c['id'],flush=True)
        if a.prepare: prepare(c)
        else: generate(c)
    print('DONE',len(chars),flush=True)

if __name__=='__main__':main()
