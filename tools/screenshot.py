#!/usr/bin/env python3
"""화면을 PNG 로 찍는다. 이 머신에 화면이 없어도 된다.

가상 프레임버퍼(Xvfb)를 띄우면 Godot 이 소프트웨어 OpenGL 로 실제로 그려 주므로
화면을 그대로 파일로 받을 수 있다. **배치가 어긋나거나 무언가가 가려지는 문제는
테스트로 안 잡힌다 — 눈으로 봐야 한다.**

    python3 tools/screenshot.py                       # 기본 한 벌
    python3 tools/screenshot.py title draw:5 reveal:9
    python3 tools/screenshot.py battle:12 shop:8 over
    python3 tools/screenshot.py --portrait battle:12  # 세로 화면으로
    python3 tools/screenshot.py --setup               # Xvfb 만 준비

찍은 파일은 build/shots/ 에 들어간다.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GODOT = Path.home() / ".local/bin/godot"
XVFB_HOME = Path.home() / ".local/opt/xvfb"
# 구글이 아니라 우분투 저장소에서 받는다 — 이 머신은 aarch64 다.
XVFB_PACKAGES = ["xvfb", "x11-common", "xauth", "libxfont2", "libfontenc1", "xserver-common"]
DISPLAY_NUM = 93

DEFAULT = ["title", "draw:6", "reveal:1", "reveal:6", "reveal:9",
           "battle:3", "battle:14", "shop:9", "over"]


def ensure_xvfb() -> Path:
    """Xvfb 를 ~/.local/opt 에 풀어 둔다 (설치가 아니라 풀기라서 sudo 가 필요 없다)."""
    exe = XVFB_HOME / "usr/bin/Xvfb"
    if exe.exists():
        return exe
    print("Xvfb 가 없어서 받아서 풀어 둡니다 (sudo 불필요)...")
    with tempfile.TemporaryDirectory(prefix="xvfb-") as tmp:
        subprocess.run(["apt-get", "download", *XVFB_PACKAGES], cwd=tmp, check=True,
                       capture_output=True, text=True)
        XVFB_HOME.mkdir(parents=True, exist_ok=True)
        for deb in sorted(Path(tmp).glob("*.deb")):
            subprocess.run(["dpkg-deb", "-x", str(deb), str(XVFB_HOME)], check=True)
    if not exe.exists():
        raise SystemExit("Xvfb 를 풀지 못했습니다.")
    return exe


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("shots", nargs="*", default=[])
    ap.add_argument("--portrait", action="store_true", help="세로 화면(800x1280)으로")
    ap.add_argument("--res", default=None, metavar="가로x세로")
    ap.add_argument("--out", default=str(ROOT / "build/shots"))
    ap.add_argument("--setup", action="store_true")
    args = ap.parse_args()

    exe = ensure_xvfb()
    if args.setup:
        return 0
    shots = args.shots or DEFAULT
    res = args.res or ("800x1280" if args.portrait else "1280x800")
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    env = dict(os.environ)
    env["DISPLAY"] = f":{DISPLAY_NUM}"
    env["LD_LIBRARY_PATH"] = str(XVFB_HOME / "usr/lib/aarch64-linux-gnu") + ":" + \
        env.get("LD_LIBRARY_PATH", "")
    # ★ 검사·촬영이 아이의 저장 파일을 덮어쓰지 않게.
    env["POCKER_NO_SAVE"] = "1"

    w, h = res.split("x")
    xv = subprocess.Popen([str(exe), f":{DISPLAY_NUM}", "-screen", "0", f"{w}x{h}x24",
                           "-nolisten", "tcp"], env=env,
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        time.sleep(1.5)
        cmd = [str(GODOT), "--path", str(ROOT), "--resolution", res,
               "res://tests/shot.tscn", "--", "--shots", ",".join(shots),
               "--out", str(out)]
        p = subprocess.run(cmd, env=env, text=True, capture_output=True, timeout=600)
        sys.stdout.write(p.stdout)
        if p.returncode != 0:
            sys.stderr.write(p.stderr)
            print(f"!! Godot 이 {p.returncode} 로 끝났습니다")
            return 1
    finally:
        xv.terminate()
    made = sorted(out.glob("*.png"))
    print(f"\n{len(made)}장: " + ", ".join(m.name for m in made))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
