#!/usr/bin/env python3
"""리그가 잡힌 캐릭터들의 **클립 3종을 한 번에** 만들어 게임에 얹는다.

    python3 tools/anim/build_clips.py                 # concepts.json 전부
    python3 tools/anim/build_clips.py a b c           # 고른 것만
    python3 tools/anim/build_clips.py --skip a,b      # 뺄 것

한 명마다: `mkanim.py` 를 돌리고 → `build/<id>/out/` 의 결과를 `art/anim/<id>/` 로 옮긴다.
게임은 `art/anim/<id>/anim.json` 과 `<id>_{idle,attack,shot}.png` 를 읽는다(core/anim.gd).

★ **파일 이름과 JSON 형식을 바꾸지 마라.** `Anim._meta` 가 `mkanim.py` 가 내는 그대로를
  읽는다 — 중간에 변환 단계를 두면 두 형식이 생기고, 둘 중 하나만 고치는 날 어긋난다.
★ 클립이 **없어도 게임은 돈다**(정지 그림 한 장으로). 그래서 실패한 캐릭터는 그냥
  건너뛰고 목록만 남긴다 — 한 명 때문에 스물아홉을 못 얹는 일이 없어야 한다.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
CONCEPTS = os.path.join(HERE, "concepts.json")


def one(uid: str, c: dict, fx_scale: float) -> tuple[bool, str]:
    src = os.path.join(ROOT, "build", uid)
    rigp = os.path.join(src, "rig.json")
    if not os.path.exists(rigp):
        return False, "리그가 없다 (autorig.py 를 먼저 돌려라)"
    with open(rigp, encoding="utf-8") as f:
        rig = json.load(f)
    lift = rig.get("lift", [0, -2])
    cmd = [sys.executable, os.path.join(HERE, "mkanim.py"), uid, "--src", src,
           "--lift=%d,%d" % (lift[0], lift[1]), "--fx", str(fx_scale)]
    for key, flag in (("motion", "--motion"), ("muzzle", "--muzzle"),
                      ("link", "--link"), ("stretch", "--stretch")):
        if c.get(key):
            cmd += [flag, str(c[key])]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        tail = (r.stdout + r.stderr).strip().splitlines()
        return False, tail[-1][:110] if tail else "mkanim 실패"

    out = os.path.join(src, "out")
    dst = os.path.join(ROOT, "art", "anim", uid)
    os.makedirs(dst, exist_ok=True)
    for name in ("idle", "attack", "shot"):
        p = os.path.join(out, "%s_%s.png" % (uid, name))
        if not os.path.exists(p):
            return False, "%s 클립이 안 나왔다" % name
        shutil.copy2(p, os.path.join(dst, "%s_%s.png" % (uid, name)))
    shutil.copy2(os.path.join(out, "%s_anim.json" % uid), os.path.join(dst, "anim.json"))
    with open(os.path.join(out, "%s_anim.json" % uid), encoding="utf-8") as f:
        meta = json.load(f)
    return True, "칸 %dx%d" % (meta["cell"]["w"], meta["cell"]["h"])


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("names", nargs="*")
    ap.add_argument("--skip", default="")
    ap.add_argument("--fx", type=float, default=1.0)
    a = ap.parse_args()
    with open(CONCEPTS, encoding="utf-8") as f:
        cs = json.load(f)
    skip = {x.strip() for x in a.skip.split(",") if x.strip()}
    names = a.names or [n for n in cs if n not in skip]
    ok, bad = [], []
    for n in names:
        if n not in cs:
            bad.append((n, "concepts.json 에 없다"))
            continue
        good, msg = one(n, cs[n], a.fx)
        (ok if good else bad).append((n, msg))
        print("  %-18s %s %s" % (n, "ok " if good else "!! ", msg))
    print("\n클립을 얹은 캐릭터 %d명 / 실패 %d명" % (len(ok), len(bad)))
    if bad:
        print("실패:", ", ".join(n for n, _ in bad))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
