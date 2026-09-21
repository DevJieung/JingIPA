#!/usr/bin/env python3
"""Install the approved 50 H3 characters into the existing runtime asset format.

Run: python3 tools/sprite/world_h3_to_game.py
Then: python3 tools/sprite/readability.py --install
Then: python3 tools/gen_roster.py && godot --headless --path . --import

The reviewed sheets are copied without recoloring or resizing. Only the static
fallback portrait is cropped/resized. readability.py derives clean combat sheets
and dedicated UI portraits after this base installation. Originals remain in
art/animation, and the reviewed combat scale/foot anchor stays fixed.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import shutil
import sys

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import gen_art

SOURCE = ROOT / "art/animation/last_refuge_v3_pixel_h3"
CHARACTERS = ROOT / "art/concepts/last_refuge_v3_pixel/characters.json"


def install() -> None:
    roster_path = ROOT / "tools/roster.json"
    roster = json.loads(roster_path.read_text())
    designs = {c["id"]: c for c in json.loads(CHARACTERS.read_text())}
    units = [(ti, u) for ti, tier in enumerate(roster["tiers"]) for u in tier["units"]]
    if len(units) != 50 or {u["id"] for _, u in units} != set(designs):
        raise ValueError("The approved designs must match all 50 runtime character IDs")

    # Validate every input before replacing any runtime file.
    prepared = []
    for ti, u in units:
        uid = u["id"]
        src = SOURCE / uid
        info = json.loads((src / "animation.json").read_text())
        design = designs[uid]
        assert info["id"] == uid and info["tier"] == ti + 1
        assert info["element"] == u["elem"] == design["element"]
        assert design["tier"] == ti + 1 and design["name"] == u["ko"]
        assert info["qc"]["feet_pixels_identical"] and not info["qc"]["canvas_clipping"]
        size = info["frame_size"]
        clips = {}
        sheets = {}
        for name in ("idle", "attack", "shot", "effect"):
            if name in ("shot", "effect") and not info.get(name):
                continue
            n = info.get(name + "_frames", 8 if name == "shot" else 12)
            cell = info["fx_frame_size"] if name in ("shot", "effect") else size
            sheet = src / (name + "_sheet.png")
            with Image.open(sheet) as im:
                assert im.size == (cell * n, cell), (uid, name, im.size)
                sheets[name] = im.convert("RGBA")
            fps = info["fx_fps"] if name in ("shot", "effect") else info["fps"]
            ms = [1000.0 / fps] * n
            clips[name] = {"frames": n, "ms": ms, "total_ms": sum(ms),
                           "loop": name in ("idle", "shot"),
                           "cell": {"w": cell, "h": cell},
                           "sha256": hashlib.sha256(sheet.read_bytes()).hexdigest()}
            if name in ("shot", "effect"):
                clips[name]["scale"] = 1.0

        idle = sheets["idle"].crop((0, 0, size, size))
        box = idle.getbbox()
        assert box is not None
        ax, ay = info["origin"]
        body_h = box[3] - box[1]
        # Frame 5 is still preparation in many H3 clips. The reviewed release
        # pose lives in selection.json so re-extraction preserves its timing.
        hit = int(info.get("selection", {}).get("hit_frame", info.get("hit_frame", 6)))
        assert 0 < hit < clips["attack"]["frames"]
        clips["attack"]["hit_frame"] = hit
        attack = sheets["attack"].crop((hit * size, 0, (hit + 1) * size, size))
        ab = attack.getbbox()
        assert ab is not None
        if u["bullet"] == "zone":
            mx, my = max(2, round(body_h * .10)), -round(body_h * .62)
        else:
            # Furthest opaque weapon/hand point above the legs, relative to feet.
            points = [(x, y) for y in range(ab[1], min(ay, ab[1] + round((ay-ab[1])*.65)))
                      for x in range(max(ax + 2, ab[0]), ab[2])
                      if attack.getpixel((x, y))[3]]
            x, y = max(points, default=(ax + round(body_h*.3), ay-round(body_h*.62)))
            mx, my = x - ax, y - ay
        meta = {"name": uid, "ko": u["ko"], "elem": u["elem"],
                "source": "last_refuge_v3_pixel_h3", "cell": {"w": size, "h": size},
                "static": {"w": box[2]-box[0], "h": body_h},
                "anchor": {"x": ax, "y": ay}, "scale": gen_art.unit_h(ti)/body_h,
                "muzzle_at": {"x": mx, "y": my},
                "hit_ms": sum(clips["attack"]["ms"][:hit]), "face": 1,
                "fixed_feet": True, "foot_pin_box": info["qc"]["foot_pin_box"],
                "palette_colors": info["palette_colors"], "clips": clips}
        prepared.append((ti, u, design, src, idle, box, meta))

    for ti, u, design, src, idle, box, meta in prepared:
        dst = ROOT / "art/anim" / u["id"]
        dst.mkdir(parents=True, exist_ok=True)
        for name in meta["clips"]:
            shutil.copyfile(src / (name + "_sheet.png"), dst / f"{u['id']}_{name}.png")
        (dst / "anim.json").write_text(json.dumps(meta, ensure_ascii=False, indent=1) + "\n")
        height = gen_art.unit_h(ti)
        portrait = idle.crop(box)
        portrait.resize((round(portrait.width * height / portrait.height), height),
                        Image.Resampling.NEAREST).save(ROOT / "art/units" / f"{u['id']}.png")
        u.update(anim=True, sc=1.0, lore=design["story"], prompt=design["prompt_en"])
    roster_path.write_text(json.dumps(roster, ensure_ascii=False, indent=1) + "\n")
    print(f"Installed {len(prepared)} characters, "
          f"{sum(len(p[-1]['clips']) for p in prepared)} animation sheets.")


if __name__ == "__main__":
    install()
