#!/usr/bin/env python3
"""별맞춤 의식 화면을 실제 Godot 렌더로 찍어 검수한다 (1280x800 · 1000x625, 한국어 · 영어).

    python3 tools/rite_design_review.py
    python3 tools/rite_design_review.py --res 1280x800      # 한 크기만
    python3 tools/rite_design_review.py --out build/rite-design-gate --root /다른/프로젝트/복사본

찍힌 그림은 build/rite-design/<해상도>/ 에 들어가고, 한눈에 보는 합본(*_contact.jpg ·
*_motion.jpg)도 같이 만든다. 검사가 하나라도 틀리면 종료 코드가 1 이다.
"""
from __future__ import annotations

import argparse
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw

from godot_env import ROOT, GODOT, xvfb

STILLS = ["title", "title_continue", "rite_1star", "rite_2star", "rite_3star", "rite_4star",
          "rite_5star", "rite_edges", "rite_paid", "rite_paid_again", "rite_no_gold",
          "rite_joker", "rite_eye", "rite_all_passives", "reveal_2star_burst_160",
          "reveal_3star_burst_160", "reveal_4star_burst_160", "reveal_5star_burst_160",
          "reveal_bumped_burst_160", "reveal_joker_burst_160", "formation",
          "support_choices", "support_summoned", "support_promoted", "menu_menu", "menu_rules",
          "menu_rite", "menu_elements", "book_water", "book_fire", "book_fusion_found",
          "book_fusion_locked", "fusion_result", "revive_hero"]
MOTION = ([f"spin_{i:02d}" for i in range(10)] + [f"respin_{i:02d}" for i in range(7)]
          + [f"pull_{i:02d}" for i in range(6)])
REVEAL = ["gather_020", "gather_055", "burst_006", "burst_030", "burst_075", "burst_160"]


def sheet(folder: Path, names: list[str], out: str, columns: int, cell=(640, 400)) -> None:
    files = [folder / f"{name}.png" for name in names if (folder / f"{name}.png").exists()]
    if not files:
        return
    rows = (len(files) + columns - 1) // columns
    page = Image.new("RGB", (cell[0] * columns, (cell[1] + 24) * rows), "#101a22")
    ink = ImageDraw.Draw(page)
    for index, path in enumerate(files):
        at = ((index % columns) * cell[0], (index // columns) * (cell[1] + 24))
        page.paste(Image.open(path).convert("RGB").resize(cell), at)
        ink.text((at[0] + 8, at[1] + cell[1] + 5), path.stem, fill="#f6c445")
    page.save(folder / out, quality=88)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--res", action="append", help="찍을 해상도(여러 번 줄 수 있다)")
    parser.add_argument("--out", default=str(ROOT / "build/rite-design"))
    parser.add_argument("--root", default=str(ROOT), help="돌릴 프로젝트 폴더(문 너비를 바꾼 복사본 검수용)")
    args = parser.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    failed = False
    with xvfb(131, "1280x800") as env:
        for resolution in args.res or ["1280x800", "1000x625"]:
            folder = out / resolution
            folder.mkdir(parents=True, exist_ok=True)
            result = subprocess.run([str(GODOT), "--path", args.root, "--resolution", resolution,
                                     "res://tests/rite_design_preview.tscn", "--", "--out", str(folder)],
                                    env=env, capture_output=True, text=True, timeout=900)
            log = result.stdout + result.stderr
            (out / f"{resolution}.log").write_text(log)
            print(resolution, log[-6000:], flush=True)
            if result.returncode or "SCRIPT ERROR" in log or "판정: 정상" not in log:
                failed = True
                continue
            for locale in ["ko", "en"]:
                sheet(folder, [f"{locale}_{name}" for name in STILLS], f"{locale}_contact.jpg", 4, (480, 300))
                sheet(folder, [f"{locale}_{name}" for name in MOTION], f"{locale}_motion.jpg", 5, (512, 320))
                for case in ["2star", "3star", "4star", "5star", "bumped", "joker"]:
                    names = sorted(path.stem for path in folder.glob(f"{locale}_reveal_{case}_*.png"))
                    order = [name for name in names if "_gather_" in name] + [name for name in names if "_burst_" in name]
                    sheet(folder, order, f"{locale}_reveal_{case}.jpg", 4, (512, 320))
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
