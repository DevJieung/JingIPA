#!/usr/bin/env python3
"""화면을 PNG 로 찍는다. 이 머신에 화면이 없어도 된다.

이 서버는 SSH 전용이라 눈으로 확인할 방법이 웹 빌드로 띄워 브라우저로 보는 것뿐이었다.
가상 프레임버퍼(Xvfb)를 띄우면 Godot 이 소프트웨어 OpenGL 로 실제로 그려 주므로
화면을 그대로 파일로 받을 수 있다. 배치가 어긋나거나 무언가가 가려지는 문제는
테스트로 잡기 어렵고 눈으로 봐야 알기 때문에, 화면을 고쳤으면 이걸로 한 번 찍어 보자.

(실제로 이 도구로 "세로 화면에서 배경이 지도를 통째로 덮는" 버그를 찾았다.)

쓰기:
    python3 tools/screenshot.py map:0 map:1            # 지도 1·2월드
    python3 tools/screenshot.py --portrait map:1       # 세로 화면으로
    python3 tools/screenshot.py battle:8 title:0
    python3 tools/screenshot.py attack:2                # 혀를 뻗은 순간
    python3 tools/screenshot.py --setup                # Xvfb 만 깔고 끝

찍은 파일은 build/shots/ 에 들어간다 (zip 에는 안 들어간다).
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GODOT = Path.home() / ".local/bin/godot"
XVFB_HOME = Path.home() / ".local/opt/xvfb"
# 구글이 아니라 우분투 저장소에서 받는다 — 이 머신은 aarch64 다.
XVFB_PACKAGES = ["xvfb", "x11-common", "xauth", "libxfont2", "libfontenc1",
                 "xserver-common"]
DISPLAY_NUM = 91


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
    print(f"  -> {XVFB_HOME}")
    return exe


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("shots", nargs="*", default=[],
                    help="찍을 화면. map:<월드0-5> / battle:<탄0-17> / "
                         "attack:<탄> (혀 뻗은 순간) / title:0")
    ap.add_argument("--portrait", action="store_true", help="세로 화면(800x1280)으로")
    ap.add_argument("--res", default=None, metavar="가로x세로",
                    help="해상도를 직접 지정 (예: 1194x834 = 11인치 아이패드)")
    ap.add_argument("--out", default=str(ROOT / "build/shots"))
    ap.add_argument("--setup", action="store_true", help="Xvfb 만 준비하고 끝낸다")
    args = ap.parse_args()

    exe = ensure_xvfb()
    if args.setup:
        return 0
    shots = args.shots or ["map:0"]
    res = args.res or ("800x1280" if args.portrait else "1280x800")
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    env = dict(os.environ)
    env["LD_LIBRARY_PATH"] = "%s:%s" % (
        XVFB_HOME / "usr/lib/aarch64-linux-gnu", env.get("LD_LIBRARY_PATH", ""))
    xvfb = subprocess.Popen([str(exe), f":{DISPLAY_NUM}", "-screen", "0",
                             f"{res.replace('x', 'x', 1)}x24"],
                            env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        time.sleep(1.5)
        env["DISPLAY"] = f":{DISPLAY_NUM}"
        cmd = [str(GODOT), "--path", str(ROOT), "--resolution", res,
               "res://tests/shot.tscn", "--", f"--out={out}", *shots]
        proc = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=600)
        for line in proc.stdout.splitlines():
            if "찍음" in line or "ERROR" in line:
                print(line)
        if proc.returncode != 0:
            print(proc.stderr[-2000:], file=sys.stderr)
            return proc.returncode
    finally:
        xvfb.terminate()
    print(f"-> {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
