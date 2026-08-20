#!/usr/bin/env python3
"""공룡 50종이 **어느 쪽을 보는가** 표를 관리한다.

참참참이 "고개를 돌려" 방향을 말하려면 이 표가 있어야 한다 — 규칙 26 이
"뒤집기를 다시 넣고 싶으면 먼저 50종의 방향 표부터 만들어라"고 못 박은 그 표다.
방향 자체는 **사람이 눈으로 보고** games/dino/scripts/dino_species.gd 의 FACE 에 적는다.
이 도구가 하는 일은 둘뿐이다:

    python3 tools/dino/face_table.py --sheet   # 눈으로 볼 대조표를 만든다 (build/dino_faces/)
    python3 tools/dino/face_table.py --sha     # 그림 지문을 다시 계산해 .gd 에 써 넣는다

★ 지문(ART_SHA)이 왜 필요한가: 그림을 다시 뽑으면 방향이 바뀔 수 있는데, 화면 없는
  이 머신에서는 아무도 못 본다. 그러면 참참참이 아이에게 **반대 방향을 말하게 된다** —
  규칙 26 이 막으려던 바로 그 일이다. 지문이 다른데 표가 그대로면
  tests/cham_check.gd 가 실패시켜서 "다시 보라"고 시킨다.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GD = os.path.join(ROOT, "games", "dino", "scripts", "dino_species.gd")
ART = os.path.join(ROOT, "games", "dino", "dinos")
SHEET = os.path.join(ROOT, "build", "dino_faces")


def ids() -> list[str]:
    src = open(GD, encoding="utf-8").read()
    return re.findall(r'\{"id":\s*"([a-z_]+)"', src)


def sha12(name: str) -> str:
    with open(os.path.join(ART, name + ".png"), "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()[:12]


def make_sheet() -> None:
    from PIL import Image, ImageDraw
    os.makedirs(SHEET, exist_ok=True)
    names = ids()
    cw, ch = 300, 260
    for b in range((len(names) + 9) // 10):
        grp = names[b * 10:(b + 1) * 10]
        out = Image.new("RGB", (cw * 5, ch * 2), (247, 240, 228))
        d = ImageDraw.Draw(out)
        for j, n in enumerate(grp):
            im = Image.open(os.path.join(ART, n + ".png")).convert("RGBA")
            k = min((cw - 10) / im.size[0], (ch - 30) / im.size[1])
            im = im.resize((max(1, int(im.size[0] * k)), max(1, int(im.size[1] * k))),
                           Image.LANCZOS)
            x, y = (j % 5) * cw, (j // 5) * ch
            out.paste(im, (x + (cw - im.size[0]) // 2, y + 24 + (ch - 24 - im.size[1]) // 2), im)
            d.text((x + 6, y + 6), "%d %s" % (b * 10 + j, n), fill=(60, 50, 60))
            d.line([x + cw // 2, y + 24, x + cw // 2, y + ch - 1], fill=(220, 120, 120))
            d.rectangle([x, y, x + cw - 1, y + ch - 1], outline=(200, 190, 180))
        out.save(os.path.join(SHEET, "faces_%d.png" % b))
    print("대조표 %d장 -> %s (머리가 가운데 선의 어느 쪽인지 보면 된다)"
          % ((len(names) + 9) // 10, SHEET))


def write_sha() -> None:
    src = open(GD, encoding="utf-8").read()
    lines = ["\t\"%s\": \"%s\"," % (n, sha12(n)) for n in ids()]
    block = "const ART_SHA := {\n" + "\n".join(lines) + "\n}"
    new, n = re.subn(r"const ART_SHA := \{.*?\n\}", block, src, count=1, flags=re.S)
    if n == 0:
        print(block)
        print("\n!! .gd 에 ART_SHA 블록이 없어서 위 내용을 그냥 찍었습니다 — 붙여 넣으세요")
        return
    open(GD, "w", encoding="utf-8").write(new)
    print("ART_SHA %d종 갱신 -> %s" % (len(lines), GD))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sheet", action="store_true")
    ap.add_argument("--sha", action="store_true")
    a = ap.parse_args()
    if a.sheet:
        make_sheet()
    if a.sha:
        write_sha()
    if not (a.sheet or a.sha):
        ap.print_help()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
