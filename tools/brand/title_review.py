#!/usr/bin/env python3
"""Run tests/brand/title_preview.tscn on the GPU X session (falls back to Xvfb) at 1280x800 and 1000x625.

    python3 tools/brand/title_review.py [--res 1280x800 ...] [--locales ko,en]
"""
from __future__ import annotations

import argparse
import contextlib
import fcntl
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from godot_env import GODOT, ROOT, xvfb  # noqa: E402

OUT = ROOT / "build/feedback-2026-10-19/D4/title"


def gpu_env():
    auth = Path(f"/run/user/{os.getuid()}/gdm/Xauthority")
    if not auth.exists():
        return None
    env = dict(os.environ, DISPLAY=":1", XAUTHORITY=str(auth), STELLARDEFENSE_NO_SAVE="1")
    probe = subprocess.run(["xdpyinfo", "-queryExtensions"], env=env, capture_output=True, text=True)
    return env if probe.returncode == 0 and "NV-GLX" in probe.stdout else None


@contextlib.contextmanager
def display():
    env = gpu_env()
    if env is not None:
        lock = ROOT / "build/casual-overhaul/gpu.lock"
        lock.parent.mkdir(parents=True, exist_ok=True)
        with open(lock, "w") as fh:
            fcntl.flock(fh, fcntl.LOCK_EX)
            yield env, ["--disable-vsync"]
        return
    with xvfb(161, "1280x800") as env:
        yield env, []


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--res", action="append")
    ap.add_argument("--locales", default="ko,en")
    args = ap.parse_args()
    with display() as (env, extra):
        for res in args.res or ["1280x800", "1000x625"]:
            folder = OUT / res
            folder.mkdir(parents=True, exist_ok=True)
            r = subprocess.run([str(GODOT), "--path", str(ROOT), "--resolution", res, *extra,
                                "res://tests/brand/title_preview.tscn", "--", "--out", str(folder), "--locales", args.locales],
                               env=env, text=True, capture_output=True, timeout=900)
            log = r.stdout + r.stderr
            (folder / "godot.log").write_text(log)
            print(res, "\n".join(l for l in log.splitlines() if "판정" in l or "!!" in l or "SCRIPT ERROR" in l or "ERROR:" in l)[:3000])


if __name__ == "__main__":
    main()
