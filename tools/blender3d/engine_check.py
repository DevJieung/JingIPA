#!/usr/bin/env python3
"""7단계 뒤 — **엔진 실기 확인.** 새 시트를 Godot 안에서 실제로 돌려 사진으로 남긴다.

    python3 tools/blender3d/engine_check.py --unit estoque

★ 헤드리스로는 못 찍는다 — Godot 의 헤드리스 드라이버는 그리지 않으므로 뷰포트를
  받아 봐야 빈 그림이다. `tools/screenshot.py` 와 같이 Xvfb 를 띄워 소프트웨어
  OpenGL 로 실제로 그린다.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import spec  # noqa: E402

ROOT = spec.ROOT
sys.path.insert(0, str(ROOT / "tools"))
from godot_env import GODOT, xvfb  # noqa: E402  (촬영 도구와 같은 Xvfb 를 나눠 쓴다)

DISPLAY_NUM = 95


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--unit", default="estoque")
    ap.add_argument("--res", default="1180x700")
    a = ap.parse_args()
    p = spec.paths(a.unit)
    sheet, qc = p["sheet"], p["qc"]
    if not (sheet / "anim.json").exists():
        raise SystemExit(f"시트가 없습니다: {sheet}/anim.json — 7단계를 먼저 돌리세요")
    qc.mkdir(parents=True, exist_ok=True)

    with xvfb(DISPLAY_NUM, a.res) as env:
        cmd = [str(GODOT), "--path", str(ROOT), "--resolution", a.res,
               "res://tools/blender3d/godot/b3d_shot.tscn", "--",
               "--dir", str(sheet), "--out", str(qc)]
        r = subprocess.run(cmd, env=env, text=True, capture_output=True, timeout=300)
        sys.stdout.write(r.stdout)
        if r.returncode != 0:
            sys.stderr.write(r.stderr)
            return 1
    shots = sorted(qc.glob("engine_*.png"))
    print(f"{len(shots)}장: " + ", ".join(s.name for s in shots))
    return 0 if shots else 1


if __name__ == "__main__":
    raise SystemExit(main())
