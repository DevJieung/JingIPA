#!/usr/bin/env python3
"""공룡 목록이 두 곳에서 어긋나지 않았는지 확인한다.

  tools/dino/gen_dinos.py 의 DINOS      (그림을 만드는 쪽)
  games/dino/scripts/dino_species.gd 의 LIST  (게임이 읽는 쪽)

둘은 순서·이름·키가 똑같아야 한다. 종을 늘리거나 고쳤으면 이걸 돌려볼 것.
    python3 tools/check_species.py
"""

import importlib.util
import os
import re
import sys

# tools/dino/ 에 있으므로 저장소 뿌리는 세 번 올라가야 한다.
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def main() -> int:
    spec = importlib.util.spec_from_file_location("g", os.path.join(ROOT, "tools/dino/gen_dinos.py"))
    g = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(g)
    py = [(d["id"], d["ko"], int(d["h"])) for d in g.DINOS]

    src = open(os.path.join(ROOT, "games/dino/scripts/dino_species.gd"), encoding="utf-8").read()
    gd = [(a, b, int(float(c)))
          for a, b, c in re.findall(r'\{"id": "(\w+)", "ko": "([^"]+)", "h": ([\d.]+)', src)]

    bad = 0
    if len(py) != len(gd):
        print(f"!! 종 수가 다릅니다 — gen_dinos.py {len(py)}종, dino_species.gd {len(gd)}종")
        bad += 1
    for i, (a, b) in enumerate(zip(py, gd)):
        if a != b:
            print(f"!! {i}번째가 다릅니다 — gen_dinos.py {a} / dino_species.gd {b}")
            bad += 1

    missing = [i for i, _, _ in py
               if not os.path.exists(os.path.join(ROOT, "games/dino/dinos", i + ".png"))]
    if missing:
        print(f"!! 그림 없는 공룡 {len(missing)}종 (손그림으로 대체됨): {', '.join(missing)}")

    longest = max((len(k), k) for _, k, _ in gd)
    print(f"{'!!' if bad else '  '} 공룡 {len(gd)}종, 가장 긴 이름 {longest[1]} ({longest[0]}자), "
          f"어긋난 곳 {bad}건")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
