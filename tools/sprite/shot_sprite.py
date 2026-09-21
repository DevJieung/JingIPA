#!/usr/bin/env python3
"""Step 5 — 시트를 Godot 안에서 돌려서 찍는다 (화면 없는 머신용).

`tools/screenshot.py` 의 Xvfb 준비를 그대로 빌려 쓰고, 장면만 갈아 끼운다.
★ 헤드리스(`--headless`)로는 안 된다 — `get_viewport().get_texture()` 가 그릴
  것이 없어서 그 자리에서 멎는다(실측: 2분 넘게 아무것도 안 찍고 매달려 있었다).

    python3 tools/sprite/shot_sprite.py --route sdxl
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / "tools"))

from godot_env import GODOT, xvfb                 # noqa: E402
from screenshot import DISPLAY_NUM                # noqa: E402  (촬영 도구와 같은 화면 번호)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--route", default="sdxl")
    ap.add_argument("--res", default="1760x800")
    ap.add_argument("--out", default=str(ROOT / "build/sprite"))
    a = ap.parse_args()

    with xvfb(DISPLAY_NUM, a.res) as env:
        cmd = [str(GODOT), "--path", str(ROOT), "--resolution", a.res,
               "res://tests/sprite_shot.tscn", "--",
               "--route", a.route, "--out", a.out]
        p = subprocess.run(cmd, env=env, text=True, capture_output=True, timeout=600)
        sys.stdout.write(p.stdout)
        if p.returncode != 0:
            sys.stderr.write(p.stderr)
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
