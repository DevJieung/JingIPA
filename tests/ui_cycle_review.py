#!/usr/bin/env python3
"""Photograph the whole play cycle at both review sizes, in both languages.

    python3 tests/ui_cycle_review.py --out-root build/ui-cycle-2026-10-17/after
    python3 tests/ui_cycle_review.py --out-root build/feedback-2026-10-19/D6/ui --only hud,wave,result
    python3 tests/ui_cycle_review.py --only box --sizes 1280x800 --locales ko
    python3 tests/ui_cycle_review.py --preview stage_store --only card,hud,wave,banner,result

Sets (tests/ui_cycle_preview.gd): title card box hud wave talent bench shop menu result hell
(the default), motion. "rite" is the old name of "box".
--preview stage_store runs tests/stage_store_preview.gd instead: card hud wave banner result shop
title help (the default), motion, probe.
Runs tests/ui_cycle_preview.tscn on the login session's GPU display when it is there
(off-screen film of the review size, serialised through build/casual-overhaul/gpu.lock),
else on a software Xvfb. Writes, per size, <locale>_<state>.png + .json, and a contact
sheet per size under <out-root>/sheets/. A run that stalls is stopped by the preview's own
watchdog (--watchdog, default 1800 s) and by the timeout here.
"""
import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from arena_visual_review import gpu_display, locked, sheet  # noqa: E402
from godot_env import ROOT, GODOT  # noqa: E402

SIZES = ["1280x800", "1000x625"]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out-root", default="build/ui-cycle-2026-10-17/after")
    ap.add_argument("--preview", default="ui_cycle", choices=["ui_cycle", "stage_store"],
                    help="which preview scene to run (both take the same arguments)")
    ap.add_argument("--only", default="")
    ap.add_argument("--locales", default="ko,en")
    ap.add_argument("--sizes", default=",".join(SIZES))
    args = ap.parse_args()
    root = ROOT / args.out_root
    failed = False
    for n, size in enumerate(args.sizes.split(",")):
        out = root / size
        out.mkdir(parents=True, exist_ok=True)
        with gpu_display(size, 95 + n) as env:
            gpu = env.get("DISPLAY") == ":1"
            # The GPU display draws into an off-screen film behind a tiny window (no vsync, no
            # monitor); on software GL the window itself is the picture.
            window = ["--disable-vsync", "--resolution", "96x60"] if gpu else ["--resolution", size]
            film = ["--film", size] if gpu else []
            cmd = [str(GODOT), *window, "--path", str(ROOT), f"res://tests/{args.preview}_preview.tscn", "--",
                   *film, "--out", str(out), "--locales", args.locales]
            if args.only:
                cmd += ["--only", args.only]
            try:
                p = subprocess.run(locked(cmd, env), env=env, text=True, capture_output=True, timeout=2400)
            except subprocess.TimeoutExpired as stalled:
                print(size, "TIMEOUT: the preview did not end in 2400 s")
                (root / f"log_{size}.txt").write_text(str(stalled.stdout or "") + "\n--- stderr ---\n" + str(stalled.stderr or ""))
                failed = True
                continue
        (root / f"log_{size}.txt").write_text(p.stdout + "\n--- stderr ---\n" + p.stderr)
        verdict = [line for line in p.stdout.splitlines() if "판정" in line or "건 · 실패" in line]
        errors = [line for line in p.stderr.splitlines() if "SCRIPT ERROR" in line or line.startswith("!!")]
        print(size, verdict[-2:] if verdict else "(no verdict)", f"{len(errors)} error lines")
        for line in errors[:12]:
            print("   ", line)
        failed = failed or p.returncode != 0 or bool(errors)
        shots = sorted(out.glob("*.png"))
        if shots:
            (root / "sheets").mkdir(exist_ok=True)
            for locale in args.locales.split(","):
                mine = [s for s in shots if s.name.startswith(locale + "_") and "motion_" not in s.name]
                if mine:
                    sheet(mine, [s.stem for s in mine], 4, 480, root / "sheets" / f"{size}_{locale}_contact.jpg", label_h=14)
                frames = [s for s in shots if s.name.startswith(locale + "_motion_")]
                if frames:
                    sheet(frames, [s.stem for s in frames], 7, 300, root / "sheets" / f"{size}_{locale}_motion.jpg", label_h=14)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
