#!/usr/bin/env python3
"""화면을 PNG 로 찍는다. 이 머신에 화면이 없어도 된다.

가상 프레임버퍼(Xvfb)를 띄우면 Godot 이 소프트웨어 OpenGL 로 실제로 그려 주므로
화면을 그대로 파일로 받을 수 있다. **배치가 어긋나거나 무언가가 가려지는 문제는
테스트로 안 잡힌다 — 눈으로 봐야 한다.**

    python3 tools/screenshot.py                       # 기본 한 벌
    python3 tools/screenshot.py title theme:11 draw:5 reveal:9 swap:24 shopp:14
    python3 tools/screenshot.py battle:12 frost:12 shop:8 over
    python3 tools/screenshot.py --portrait battle:12  # 세로 화면으로
    python3 tools/screenshot.py --setup               # Xvfb 만 준비

찍은 파일은 build/shots/ 에 들어간다.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

# ★ 다른 도구들이 예전부터 `from screenshot import ROOT, GODOT, XVFB_HOME, ensure_xvfb` 로
#   가져다 쓴다. 본체는 godot_env 로 옮겼고 여기서는 그대로 내보낸다.
from godot_env import ROOT, GODOT, XVFB_HOME, ensure_xvfb, xvfb  # noqa: F401

DISPLAY_NUM = 93

DEFAULT = ["title", "draw:6", "reveal:1", "reveal:6", "reveal:9",
           "battle:1", "battle:14", "frost:12", "stun:12", "battle:30",
           # 장판은 사거리 상한(6단계)에 닿는 40탄에서야 원반이 제일 커진다.
           "zone:16", "zone:40",
           "team:7", "swap:24", "hall:24", "shop:9", "shopp:14", "shopc:14", "theme:11",
           "result:12", "over"]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("shots", nargs="*", default=[])
    ap.add_argument("--portrait", action="store_true", help="세로 화면(800x1280)으로")
    ap.add_argument("--res", default=None, metavar="가로x세로")
    ap.add_argument("--out", default=str(ROOT / "build/shots"))
    ap.add_argument("--setup", action="store_true")
    args = ap.parse_args()

    ensure_xvfb()
    if args.setup:
        return 0
    shots = args.shots or DEFAULT
    res = args.res or ("800x1280" if args.portrait else "1280x800")
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    with xvfb(DISPLAY_NUM, res) as env:
        cmd = [str(GODOT), "--path", str(ROOT), "--resolution", res,
               "res://tests/shot.tscn", "--", "--shots", ",".join(shots),
               "--out", str(out)]
        p = subprocess.run(cmd, env=env, text=True, capture_output=True, timeout=600)
        sys.stdout.write(p.stdout)
        sys.stderr.write(p.stderr)
        if p.returncode != 0:
            print(f"!! Godot 이 {p.returncode} 로 끝났습니다")
            return 1
    made = sorted(out.glob("*.png"))
    print(f"\n{len(made)}장: " + ", ".join(m.name for m in made))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
