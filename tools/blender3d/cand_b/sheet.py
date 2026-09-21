#!/usr/bin/env python3
"""후보 B — 눈으로 보는 도구. 낱장들을 한 판에 3배로 확대해 붙인다."""
import sys, glob, os
from PIL import Image

def strip(paths, z=3, gap=2, bg=(28,28,34)):
    ims=[Image.open(p).convert("RGBA") for p in paths]
    w,h=ims[0].size
    W=len(ims)*(w*z+gap)+gap; H=h*z+2*gap
    out=Image.new("RGBA",(W,H),bg+(255,))
    for i,im in enumerate(ims):
        out.paste(im.resize((w*z,h*z),Image.NEAREST),(gap+i*(w*z+gap),gap),
                  im.resize((w*z,h*z),Image.NEAREST))
    return out

if __name__=="__main__":
    pat=sys.argv[1]; out=sys.argv[2]; z=int(sys.argv[3]) if len(sys.argv)>3 else 3
    ps=sorted(glob.glob(pat))
    strip(ps,z).save(out); print(out,len(ps))
