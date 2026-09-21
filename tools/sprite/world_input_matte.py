#!/usr/bin/env python3
"""Preserve light faces/armor in the H3 input copies; CPU only."""
import json
import sys
from pathlib import Path
sys.path.insert(0,'/home/dgxmaruta/pjt/pixelforge')
import torch
import numpy as np
from PIL import Image
from pixelforge.gen.matting import BiRefNetMatting
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'art/animation/last_refuge_v3_pixel_h3'
chars=json.loads((ROOT/'art/concepts/last_refuge_v3/characters.json').read_text())
chars.sort(key=lambda c:(OUT/c['id']/'generation.json').exists())
torch.set_num_threads(4)
m=BiRefNetMatting(device='cpu',resolution=512).load()
for c in chars:
    dst=OUT/'_source_mattes'/(c['id']+'.png')
    if dst.exists():continue
    dst.parent.mkdir(parents=True,exist_ok=True)
    a=m.cutout(str(ROOT/'art/concepts/last_refuge_v3_pixel'/(c['id']+'.png')))
    a[a[:,:,3]==0,:3]=0
    tmp=dst.with_suffix('.tmp.png');Image.fromarray(a).save(tmp);tmp.replace(dst)
    print('INPUT',c['id'],flush=True)
