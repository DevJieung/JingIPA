#!/usr/bin/env python3
"""Godot 을 이 머신(aarch64 · 화면 없음)에서 띄우는 데 필요한 것을 한 곳에 둔다.

    from godot_env import ROOT, GODOT, ensure_xvfb, xvfb

★ 화면이 없는 머신이라 실제로 그리려면 Xvfb 가 필요하다. 예전에는 촬영·녹화·검토·
  스프라이트 미리보기 도구 여섯이 저마다 Xvfb 를 띄우는 열 줄을 베껴 갖고 있었다 —
  베낀 것은 언젠가 한 곳만 고쳐진다(실제로 기다리는 시간이 1초와 1.5초로 갈려 있었다).
★ 헤드리스로는 못 찍는다 — Godot 의 헤드리스 드라이버는 그리지 않으므로 뷰포트를
  받아 봐야 빈 그림이다. Xvfb 위에서 소프트웨어 OpenGL 로 실제로 그린다.
★ 도구마다 **디스플레이 번호를 다르게** 쓴다(촬영 93 · 녹화 94 · 검토 95). 같은 번호를
  쓰는 둘은 같이 못 돈다.
"""
from __future__ import annotations

import contextlib
import os
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Iterator

ROOT = Path(__file__).resolve().parent.parent
## tools/verify.sh 와 같은 규칙 — GODOT 환경 변수가 있으면 그것, 없으면 ~/.local/bin/godot.
GODOT = Path(os.environ.get("GODOT", str(Path.home() / ".local/bin/godot")))
XVFB_HOME = Path.home() / ".local/opt/xvfb"
# 구글이 아니라 우분투 저장소에서 받는다 — 이 머신은 aarch64 다.
XVFB_PACKAGES = ["xvfb", "x11-common", "xauth", "libxfont2", "libfontenc1", "xserver-common"]


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


def godot_env(display: int) -> dict[str, str]:
    """Xvfb 위에서 Godot 을 돌릴 환경 변수.

    ★ POCKER_NO_SAVE=1 이 언제나 들어간다 — 촬영·검사가 아이의 저장 파일을 덮어쓰지 않게
      (CLAUDE.md 21).
    """
    env = dict(os.environ)
    env["DISPLAY"] = f":{display}"
    env["LD_LIBRARY_PATH"] = str(XVFB_HOME / "usr/lib/aarch64-linux-gnu") + ":" + \
        env.get("LD_LIBRARY_PATH", "")
    env["POCKER_NO_SAVE"] = "1"
    return env


@contextlib.contextmanager
def xvfb(display: int, res: str, settle: float = 1.5) -> Iterator[dict[str, str]]:
    """Xvfb 하나를 `res`(가로x세로) 크기로 띄워 두고 그 환경 변수를 내준다. 나갈 때 끈다.

        with xvfb(93, "1280x800") as env:
            subprocess.run([str(GODOT), "--path", str(ROOT), ...], env=env)
    """
    exe = ensure_xvfb()
    env = godot_env(display)
    w, h = res.split("x")
    proc = subprocess.Popen([str(exe), f":{display}", "-screen", "0", f"{w}x{h}x24",
                             "-nolisten", "tcp"], env=env,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        time.sleep(settle)          # 서버가 뜨기 전에 Godot 을 띄우면 화면을 못 잡는다
        yield env
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
