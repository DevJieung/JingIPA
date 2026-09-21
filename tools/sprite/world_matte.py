#!/usr/bin/env python3
"""CPU-only semantic fallback; safe to run while the H3 GPU is busy."""
import sys
from pathlib import Path
sys.path.insert(0,'/home/dgxmaruta/pjt/pixelforge')
import torch
import numpy as np
from PIL import Image
from pixelforge.gen.matting import BiRefNetMatting
torch.set_num_threads(4)
m=BiRefNetMatting(device='cpu',resolution=512).load()
for src,dst in zip(sys.argv[1::2],sys.argv[2::2]):
    a=m.cutout(src)
    # Preserve character colors, including magenta cuffs and electric accents.
    # Any trapped background is corrected per character after visual review.
    a[a[:,:,3]==0,:3]=0
    Path(dst).parent.mkdir(parents=True,exist_ok=True)
    temp=Path(dst).with_suffix('.tmp.png');Image.fromarray(a).save(temp);temp.replace(dst)
    print('MATTE',Path(src).name,flush=True)
