#!/usr/bin/env python3
"""Prepare per-ID built-in imagegen prompts, without calling any image API.

The identities below were checked against the actual 49 active/source sprites.
Limne is excluded. Native binding coordinates still require the actual mesh.
"""
import argparse,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
DESCRIPTIONS='''chispa|Petite red ponytail ignition mechanic, forehead goggles, orange overalls/crimson shirt, heatproof gauntlet and brass ignition pistol
lind|Mint spiky hair, ivory scarf, quilted cobalt jacket and blue trousers, icy belt chain
brigid|Purple bob, green vest, purple trousers, metal bow and quiver
phorkys|Older blue-capped harbor mechanic, white sideburns, blue raincoat and heavy boots, exposed water cylinder revolver
solana|Red topknot, orange/red archer workwear, brass fire bow and signal-arrow quiver
jokull|White hair and beard, blue hood/winter armor, broad ice blade
rhiannon|Dark purple ponytail, lime green jacket, purple trousers and boots, two yellow pressure hoses
mimic|Cream/navy rounded automaton, smiling faceplate, segmented armor and chunky boots
protea|Brown spiky hair, golden goggles, blue navigator coat, ornate bronze/aqua triple-limbed bow
ceniza|Cropped gray hair and black respirator, orange heatproof workwear, flexible chain and copper bristles
vidarr|Brown spikes, pale blue winter workwear, large blue rear reel and frost battery
finn|Lime hair, purple jacket and boots, green arm guard, compact knife
dummy|Wooden/cream faceplate mannequin, dark vest, brown belt and exposed pistol
marea|Cropped orange hair, muscular blue rescue overalls, life ring, large brass hose nozzle and blue reel
igni|Red swept spikes, red field jacket, charcoal trousers, bare thermal blade and brass pistol
kari|White hair, blue goggles, blue padded winter coat, blue cold gun
donn|White hair and beard, lime green jacket/purple trousers, enormous bronze overhead cannon rack
glaukos|Green hair and beard, heavy turquoise diving workwear, broad curved hooked blade
volcan|Black hair and beard, red/orange heavy armor, large black furnace back pipe
eira|White hair, furry blue cat-eared hood, blue/white winter archer clothing, ice bow
conor|Dark skin, purple flat-top hair, lime green workwear, pressure gauge and chunky gun
shift|Dark side-swept hair, cream/navy segmented work armor, exposed belt gears
thalassa|Silver bun, teal/navy coat, gold/cyan chest gem, large blue body pressure hoses
carmen|Dark curly hair, red bolero/orange-gold armor, two short red pistols
snorri|Blond hair and moustache, heavy blue fur coat, massive blue rear mechanism and anchor
niamh|White hair, green/purple workwear, rear wooden beads and bow
phantom|Silver ponytail, cream/black armor, red-gripped knife and rear tube
triton|Blue harbor cap, white beard, heavy blue coat, enormous rear water cannon and hose
saeta|Orange/red hood, red/gold archer field coat, visible quiver and bow
helga|White ponytail, silver/blue gem armor, broad ice sword
morrigan|Dark braided hair, purple armor, lime leaves and chains
blank|White hair, cream/navy armor, large cream rectangular rear unit
keto|Navy/blue hair, navy diving archer armor, cyan harpoon bow and quiver
candela|Red hood/work tunic, red/gold trousers, wide gold belt and heavy chain
sigrid|Pale blue hair, white/blue padded coat, gray triple rear fan assembly
caden|White spiky hair, lime green armor, exposed dagger
grey|Gray hat, white hair/moustache and round glasses, gray officer coat, long rifle
galene|Navy bob, blue officer coat/gold shoulders, broad blue reservoir/hose equipment
estoque|Brown hair/moustache and glasses, red/gold fencing coat, narrow rapier and piston
frosti|White hair, white/cyan coat, ice gauntlet and blue rear cannon pack
lugh|Blond hair and moustache, purple/gold coat, paired overhead green batteries
null|Black ponytail, ivory/gold archer workwear, exposed bow
nerea|Silver ponytail, blue/gold heavy armor, ice greatsword and broad gray rear sluice plates
isa|Silver ponytail, blue/gold eyeglasses, white/blue archer clothes, ice crystal pack and bow
brian|White spiky hair, purple/lime heavy armor, huge battery rifle
zero|White hair, cream/navy workwear, gold ring gauntlet and gray/gold rear cannon'''
HEAVY=set('phorkys jokull vidarr marea donn glaukos volcan snorri triton helga blank sigrid galene frosti lugh nerea brian zero'.split())
ROBOTS=set('mimic dummy'.split())

def initialize_specs():
    path=ROOT/'tools/3d/native_visual_specs.json';spec=json.loads(path.read_text())
    roster=json.loads((ROOT/'tools/roster.json').read_text())
    units={u['id']:u for t in roster['tiers']for u in t['units']}
    for line in DESCRIPTIONS.splitlines():
        cid,description=line.split('|',1);unit=units[cid]
        build='heavy' if cid in HEAVY else 'automaton' if cid in ROBOTS else 'slim' if unit['weapon']=='bow' else 'normal'
        spec['heroes'].setdefault(cid,{'identity':description,'build':build,
            'attack':{'bow':'bow','sword':'sword','gun':'rifle','deck':'cast','whip':'cast'}[unit['weapon']],
            'height':1.70 if build=='heavy' else 1.65,'element':unit['elem'],
            'gear':'Preserve actual sprite; fit articulation/sockets to actual native output',
            'bind_pose':'a_pose_35','idle_inward_angle':.28,
            'spec_status':'original directly inspected; native anatomy and binding pending'})
    assert len(spec['heroes'])==49 and 'limne' not in spec['heroes']
    path.write_text(json.dumps(spec,indent=2)+'\n');return spec['heroes']

def prompt(cid,row):
    return f'''Use case: a SINGLE character modeling reference raster for a later REAL native 3D game mesh, not a final 3D deliverable.
Image 1: {cid}'s actual original sprite. Preserve its identity, hair/face/eye colors, glasses if present, stature, clothing colors and recognizable equipment. Image 2: accepted Limne game character MATERIAL/STYLE reference only; do not copy her face, costume, tank or proportions.
Identity observed in the actual original: {row['identity']}. If old written descriptions conflict, the original visible sprite wins. Keep the same compact adult/chibi body proportions and gender presentation as Image1; for an automaton keep a mechanical face and joints, no human hair/skin.
Render this one character as polished moderately stylized 3D GAME artwork: continuous sculpted face with lids and calm expression, clean hair masses, sewn clothing folds, machined equipment edges, broad readable matte color surfaces and restrained smooth metal accents. No photoreal grain, plastic figurine gloss, pixel block surfaces or black outlines.
MODEL BIND POSE is essential: near-orthographic straight FRONT view, arms extended down/out at35 degrees, elbows almost straight, hands at least a palm-width away from hips, legs, pouches and torso; genuine transparent gaps around both forearms and hands. Shoulder/elbow/wrist joints clearly separate. Legs slightly apart, both feet flat and fully visible. Equipment follows original placement, but weapons held in hands must stay completely outside body/legs with no accidental contact. Every weapon must be whole and connected to its grip; no duplicate weapons. For fixed back equipment keep the original count/silhouette, centered behind torso and separated from moving arms. Hoses connect to their original equipment/hand anchors with a clean unbroken arc separated from clothes. Preserve chain/tube equipment rather than inventing a different weapon.
Full body and all gear in frame with8% margins, soft neutral diffuse studio light, genuine TRANSPARENT background. No floor/pedestal, environment, shadows painted into background, checkerboard, labels, text, extra fingers/limbs or multiple views/characters.'''

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--ids',default='all');args=parser.parse_args()
    heroes=initialize_specs();ids=list(heroes) if args.ids=='all' else args.ids.split(',')
    for cid in ids:
        if cid=='limne':raise ValueError('Accepted Limne is preserved')
        folder=ROOT/'build/character-3d/references'/cid;folder.mkdir(parents=True,exist_ok=True)
        path=folder/'modeling-prompt.txt';path.write_text(prompt(cid,heroes[cid])+'\n');print(cid,path)
