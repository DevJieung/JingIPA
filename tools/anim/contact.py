#!/usr/bin/env python3
"""후보를 한 판에 늘어놓는다 — ART.md 2-3.

★ **같은 속성 캐릭터를 오른쪽에 1:1 로 같이 세운다.** 혼자 보면 늘 괜찮아 보인다.
  나란히 놓아야 "이미 있는 서리마녀랑 똑같잖아"가 보인다.

    python3 tools/anim/contact.py frost_queen
    python3 tools/anim/contact.py frost_queen --pick a1     # 고른 것만 이웃과
"""
from __future__ import annotations

import argparse
import glob
import json
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.dirname(os.path.abspath(__file__))
SCALE = 3
BG = (26, 20, 32)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("name")
    ap.add_argument("--pick", default="", help="이 후보만 이웃과 나란히")
    ap.add_argument("--out", default="")
    a = ap.parse_args()

    with open(os.path.join(HERE, "concepts.json"), encoding="utf-8") as f:
        c = json.load(f)[a.name]
    cdir = os.path.join(ROOT, "build", a.name, "cand")

    if a.pick:
        items = [(a.pick, os.path.join(cdir, a.pick + ".png"))]
    else:
        ps = [p for p in sorted(glob.glob(os.path.join(cdir, "*.png")))
              if not p.endswith("_raw.png")]
        items = [(os.path.basename(p)[:-4], p) for p in ps]
    items += [("· " + n, os.path.join(ROOT, "art/units", n + ".png"))
              for n in c.get("neighbors", [])]

    ims = [(lab, Image.open(p).convert("RGBA")) for lab, p in items if os.path.exists(p)]
    if not ims:
        raise SystemExit(f"{cdir} 에 후보가 없다")
    cw = max(i.width for _, i in ims) * SCALE + 16
    chh = max(i.height for _, i in ims) * SCALE + 26
    sheet = Image.new("RGB", (cw * len(ims), chh), BG)
    d = ImageDraw.Draw(sheet)
    for k, (lab, im) in enumerate(ims):
        big = im.resize((im.width * SCALE, im.height * SCALE), Image.NEAREST)
        sheet.paste(big, (k * cw + (cw - big.width) // 2, chh - 22 - big.height), big)
        d.text((k * cw + 6, chh - 16), f"{lab} {im.width}x{im.height}", fill=(220, 210, 200))
        d.line([(k * cw, 0), (k * cw, chh)], fill=(60, 50, 66))
    out = a.out or os.path.join(ROOT, "build", a.name,
                                "contact_pick.png" if a.pick else "contact.png")
    sheet.save(out)
    print(out, sheet.size)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
