#!/usr/bin/env python3
"""배경 떼기 — pixelforge 의 BiRefNet(MIT) 을 빌려 쓴다.

SDXL 은 「plain white background」를 자주 어긴다(실측: 열다섯 장 중 열셋이 회색·
풍경 배경이었다). 흰 배경을 전제로 한 물 붓기(`gen_art.cut_white`)는 그 순간
아무 일도 못 한다 — 배경이 흰색이 아니면 모서리에서 부은 물이 한 픽셀도 못 번진다.

BiRefNet 은 **무엇이 배경인지를 뜻으로** 가르므로 배경 색을 안 가린다.

★ pixelforge 의 `.venv` 로 따로 띄운다. `timm`·`kornia` 가 그 venv 안에만 있고,
  이 저장소의 파이썬으로 부르면 import 에서 죽는다.

    python3 tools/sprite/cutbg.py in.png out.png [in2.png out2.png …]
"""

from __future__ import annotations

import os
import subprocess
import sys

PIXELFORGE = "/home/dgxmaruta/pjt/pixelforge"
PY = os.path.join(PIXELFORGE, ".venv", "bin", "python")

_WORKER = r'''
import sys
sys.path.insert(0, "%s")
from pixelforge.gen.matting import BiRefNetMatting
from PIL import Image
m = BiRefNetMatting().load()
pairs = list(zip(sys.argv[1::2], sys.argv[2::2]))
for src, dst in pairs:
    rgba = m.cutout(src)
    if not isinstance(rgba, Image.Image):
        rgba = Image.fromarray(rgba)
    rgba.save(dst)
    print("cut", dst, flush=True)
''' % PIXELFORGE


def cut(pairs: list[tuple[str, str]]) -> None:
    """(원본, 결과) 여러 쌍을 한 번에 — 모델을 한 번만 올린다."""
    args = [a for p in pairs for a in p]
    subprocess.run([PY, "-c", _WORKER] + args, cwd=PIXELFORGE, check=True)


if __name__ == "__main__":
    a = sys.argv[1:]
    if len(a) < 2 or len(a) % 2:
        raise SystemExit(__doc__)
    cut(list(zip(a[0::2], a[1::2])))
