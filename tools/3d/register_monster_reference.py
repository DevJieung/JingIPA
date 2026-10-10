#!/usr/bin/env python3
"""Register one artist-reviewed creature reconstruction raster, not a model."""
import argparse, hashlib, json, shutil
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
p = argparse.ArgumentParser()
for key in ['id','image','prompt','note']:
    p.add_argument('--'+key,required=True)
a = p.parse_args()
sources={row['id']:row for row in json.loads((ROOT/'tools/3d/monster_sources.json').read_text())}
source=sources[a.id]
original=ROOT/source['image']
input_image=Path(a.image).resolve()
im=Image.open(input_image)
if im.mode!='RGBA' or im.getchannel('A').getextrema()[0]!=0:
    raise ValueError('A real transparent alpha background is required')
folder=ROOT/'build/character-3d/monster-references'/a.id
folder.mkdir(parents=True,exist_ok=True)
dest=folder/'bind-reference.png'
digest=lambda path:hashlib.sha256(Path(path).read_bytes()).hexdigest()
if dest.exists() and digest(dest)!=digest(input_image):
    shutil.copy2(dest,folder/('previous-'+digest(dest)[:12]+'.png'))
shutil.copy2(input_image,dest)
prompt=folder/'selected-prompt.txt'
shutil.copy2(a.prompt,prompt)
row=dict(source,image=str(dest),reference_type='built-in image_gen creature bind-reference raster; NOT a native GLB',
         original=str(original.relative_to(ROOT)),original_sha256=digest(original),
         image_sha256=digest(dest),prompt=str(prompt),prompt_sha256=digest(prompt),reference_review=a.note)
path=ROOT/'tools/3d/monster_reference_sources.json'
rows=json.loads(path.read_text()) if path.exists() else []
rows=[r for r in rows if r['id']!=a.id]+[row]
temp=path.with_suffix('.tmp')
temp.write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n');temp.replace(path)
(folder/'reference-provenance.json').write_text(json.dumps(row,ensure_ascii=False,indent=2)+'\n')
print(a.id,row['image_sha256'])
