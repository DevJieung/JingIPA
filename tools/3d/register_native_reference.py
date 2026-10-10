#!/usr/bin/env python3
"""Register one directly reviewed built-in raster reference, never a GLB.

This records provenance/alpha, not an automatic identity or style PASS.
Use only after the artist has inspected the original and selected raster.
"""
import argparse,hashlib,json,shutil
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--id',required=True)
p.add_argument('--image',required=True);p.add_argument('--prompt',required=True)
p.add_argument('--note',required=True);a=p.parse_args()
if a.id=='limne':raise ValueError('Preserve accepted Limne')
spec=json.loads((ROOT/'tools/3d/native_visual_specs.json').read_text())['heroes'][a.id]
src=Path(a.image).resolve();im=Image.open(src)
if im.mode!='RGBA' or im.getchannel('A').getextrema()[0]!=0:
    raise ValueError('Actual transparent background required')
folder=ROOT/'build/character-3d/references'/a.id;folder.mkdir(parents=True,exist_ok=True)
dest=folder/'apose.png';digest=lambda f:hashlib.sha256(Path(f).read_bytes()).hexdigest()
if dest.exists() and src!=dest and digest(dest)!=digest(src):
    shutil.copy2(dest,folder/('previous-'+digest(dest)[:12]+'.png'))
if src!=dest:shutil.copy2(src,dest)
prompt=folder/'apose-prompt.txt';source_prompt=Path(a.prompt).resolve()
if source_prompt!=prompt:shutil.copy2(source_prompt,prompt)
original=ROOT/'build/hero-native/inputs'/f'{a.id}.png'
style=ROOT/'build/limne-game-motion/game-review/1280x800/gallery_three_quarter.png'
row={'id':a.id,'image':str(dest),'reference_type':'built-in image_gen original-sprite A-pose raster; NOT native GLB',
    'original':str(original.relative_to(ROOT)),'original_sha256':digest(original),
    'style_reference':str(style.relative_to(ROOT)),'style_reference_sha256':digest(style),
    'prompt':str(prompt),'prompt_sha256':digest(prompt),'image_sha256':digest(dest),
    'workflow_overrides':{},'reference_review':a.note}
path=ROOT/'tools/3d/character_apose_sources.json';rows=json.loads(path.read_text())
rows=[r for r in rows if r['id']!=a.id]+[row]
temp=path.with_suffix('.tmp');temp.write_text(json.dumps(rows,indent=2)+'\n');temp.replace(path)
(folder/'reference-provenance.json').write_text(json.dumps(row,indent=2)+'\n')
print(a.id,row['image_sha256'],'reviewed raster registered')
