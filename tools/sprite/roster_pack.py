#!/usr/bin/env python3
"""Package image_gen 4×3 character atlases into native animation strips.

This is deterministic asset preparation: keyed matte, cell extraction, nearest
sampling, shared palette, planted lower legs, and metadata. It draws no artwork.
Generated inputs and prior approved sheets remain under art/animation/element_aoe_v1.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil

import numpy as np
from PIL import Image
from scipy.ndimage import binary_erosion, distance_transform_edt, label

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "art/animation/roster_v1"
UNITS = {u["id"]: u for u in json.loads((WORK / "roster.json").read_text())}
IDS = list(UNITS)


def matte(im):
    arr = np.array(im.convert("RGBA"))
    rgb = arr[:, :, :3].astype(float)
    # Only near-pure key magenta; legitimate pink highlights and purple costume
    # colors have different red/blue balance or appreciable green content.
    key = (rgb[:, :, 0] > 210) & (rgb[:, :, 2] > 210) & \
        (rgb[:, :, 1] < 32) & (np.abs(rgb[:, :, 0] - rgb[:, :, 2]) < 28)
    keep = (~key) & (arr[:, :, 3] >= 128)
    # Remove subpixel key contamination at generated edges without blending.
    core = binary_erosion(keep, iterations=1)
    _, near = distance_transform_edt(~core, return_indices=True)
    edge = keep & ~core
    arr[edge, :3] = arr[near[0][edge], near[1][edge], :3]
    arr[:, :, 3] = keep.astype(np.uint8) * 255
    arr[~keep] = 0
    return Image.fromarray(arr)


def shared_palette(frames, count=96):
    size = frames[0].width
    sample = Image.new("RGB", (size * len(frames), size))
    for i, im in enumerate(frames):
        sample.paste(im.convert("RGB"), (size * i, 0))
    pal = sample.quantize(count, method=Image.Quantize.MEDIANCUT)
    out = []
    for im in frames:
        q = im.convert("RGB").quantize(palette=pal, dither=Image.Dither.NONE).convert("RGBA")
        q.putalpha(im.getchannel("A"))
        out.append(q)
    return out


def separators(im, count, vertical):
    """Find empty gutters near requested divisions, never cut a silhouette.

    image_gen may shift rows or extend a release pose beyond its nominal cell.
    The source remains untouched; only extraction rectangles adapt to its gaps.
    """
    mask = np.array(im.getchannel("A")) > 0
    profile = mask.sum(axis=1 if vertical else 0)
    length = len(profile)
    out = [0]
    for i in range(1, count):
        wanted = round(i * length / count)
        reach = round(length / count * 0.48)
        candidates = [p for p in range(max(out[-1] + 1, wanted - reach), min(length, wanted + reach))
                      if profile[p] <= 1]
        if not candidates:
            raise ValueError("No empty gutter near atlas division; regenerate source")
        out.append(min(candidates, key=lambda p: abs(p - wanted)))
    return out + [length]


def prepare(uid):
    raw = Image.open(WORK / "source" / (uid + ".png"))
    clean = matte(raw)
    clean.save(WORK / "source" / (uid + "_rgba.png"))
    cells, rectangles = [], []
    try:
        rows = separators(clean, 3, True)
        for y in range(3):
            row = clean.crop((0, rows[y], clean.width, rows[y + 1]))
            columns = separators(row, 4, False)
            for x in range(4):
                rectangles.append((columns[x], rows[y], columns[x + 1], rows[y + 1]))
    except ValueError:
        # A raised bow can extend above another column's boots without touching
        # that column. Extract along each column's genuine empty row gutter.
        columns = separators(clean, 4, False)
        by_column = []
        for x in range(4):
            column = clean.crop((columns[x], 0, columns[x + 1], clean.height))
            rows = separators(column, 3, True)
            by_column.append([(columns[x], rows[y], columns[x + 1], rows[y + 1]) for y in range(3)])
        rectangles = [by_column[x][y] for y in range(3) for x in range(4)]
    cells = [clean.crop(box) for box in rectangles]
    meta = json.loads((WORK / "previous" / uid / "anim.json").read_text())
    target_h = int(meta["static"]["h"])
    # Use the idle body height for ALL cells, preserving equipment scale.
    b0 = cells[0].getbbox()
    factor = target_h / (b0[3] - b0[1])
    placed, transforms = [], []
    for cell in cells[:8]:
        bounds = cell.getbbox()
        # Measure the boots rather than swinging arms/backpack when aligning x.
        low = cell.crop((0, bounds[3] - 24, cell.width, bounds[3])).getbbox()
        boot_x = (low[0] + low[2]) / 2
        resized = cell.resize((round(cell.width * factor), round(cell.height * factor)), Image.Resampling.NEAREST)
        offset = (round(128 - boot_x * factor), round(224 - bounds[3] * factor))
        transformed = tuple(v + offset[i % 2] for i, v in enumerate(resized.getbbox()))
        if min(transformed[:2]) < 3:
            raise ValueError(f"{uid}: actor extends above/left of the preserved anchor: {transformed}")
        placed.append((resized, offset, transformed))
        transforms.append({"factor": factor, "offset": offset})
    cell_size = max(256, int(np.ceil((max(max(p[2][2:]) for p in placed) + 4) / 64)) * 64)
    actor = []
    for resized, offset, _ in placed:
        frame = Image.new("RGBA", (cell_size, cell_size))
        frame.paste(resized, offset, resized)
        # Suppress isolated sampling specks, including a one-pixel spark at a
        # source gutter. Connected body/weapon silhouettes remain untouched.
        array = np.array(frame)
        components, _ = label(array[:, :, 3] > 0, structure=np.ones((3, 3)))
        sizes = np.bincount(components.ravel())
        array[(components > 0) & (sizes[components] <= 3)] = 0
        frame = Image.fromarray(array)
        actor.append(frame)
    actor = shared_palette(actor)
    # Keep generated anatomy/equipment intact; every pose already shares the
    # pixel foot baseline and boot-center origin established above.
    # Symmetric idle cycle returns through the same keyframes without a jump.
    idle = [actor[i] for i in [0, 1, 2, 3, 3, 2, 1, 0]]
    hit = int(meta["clips"]["attack"]["hit_frame"])
    # Hold anticipation until the original release time. Twelve frame timings
    # and hit_ms are unchanged; recovery lands on the exact idle frame.
    attack = [actor[0] if i in (0, 11) else
              (actor[4] if i < 3 else actor[5]) if i < hit else
              actor[6] if i < min(hit + 2, 11) else actor[7] for i in range(12)]
    assert len(attack) == 12
    shot = []
    shot_bounds = [cell.getbbox() for cell in cells[8:]]
    effect_scale = 104.0 / max(max(b[2] - b[0], b[3] - b[1]) for b in shot_bounds)
    for index, cell in enumerate(cells[8:]):
        effect = cell.crop(cell.getbbox())
        effect = effect.resize((max(1, round(effect.width * effect_scale)),
                                max(1, round(effect.height * effect_scale))), Image.Resampling.NEAREST)
        frame = Image.new("RGBA", (128, 128))
        # Charge/expansion/impact share a ground baseline and one scale, so a
        # small charge really grows. The final fragments disperse around center.
        zone = UNITS[uid]["bullet"] == "zone"
        y = 112 - effect.height if zone and index < 3 else (128 - effect.height) // 2
        x = (128 - effect.width) // 2 if zone else 116 - effect.width
        frame.paste(effect, (x, y), effect)
        shot.append(frame)
    dst = ROOT / "art/anim" / uid
    meta["name"] = uid + "_roster_v1"
    meta["portrait_id"] = uid
    meta["source"] = "imagegen_roster_v1"
    meta["cell"] = {"w": cell_size, "h": cell_size}
    meta.pop("foot_pin_box", None)
    meta["palette_colors"] = 96
    meta["fixed_feet"] = False
    meta["readability"] = {"version": 2, "source": str((WORK / "source" / (uid + ".png")).relative_to(ROOT)),
                           "method": "image_gen source > keyed matte > foot-baseline and boot-center alignment > shared palette; generated anatomy preserved"}
    meta["readability"]["source_cells"] = rectangles
    meta["readability"]["source_transforms"] = transforms
    muzzle_path = WORK / "muzzle_map.json"
    muzzle_map = json.loads(muzzle_path.read_text()) if muzzle_path.exists() else {}
    if uid in muzzle_map:
        meta["muzzle_at"] = muzzle_map[uid]
    for clip, frames in [("idle", idle), ("attack", attack), ("shot", shot)]:
        size = frames[0].width
        strip = Image.new("RGBA", (size * len(frames), size))
        for i, frame in enumerate(frames):
            strip.paste(frame, (i * size, 0))
        path = dst / (meta["name"] + "_" + clip + ".png")
        strip.save(path)
        info = meta["clips"].setdefault(clip, {})
        if clip == "shot":
            info.update(ms=[100, 100, 100, 100], total_ms=400,
                        loop=UNITS[uid]["bullet"] not in ("zone", "beam"), scale=1.0)
        info.update(frames=len(frames), cell={"w": size, "h": size},
                    sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    # Preserve the previous optional impact clip under the new atlas prefix.
    if "effect" in meta["clips"]:
        old = WORK / "previous" / uid / (uid + "_effect.png")
        new = dst / (meta["name"] + "_effect.png")
        shutil.copy2(old, new)
    (dst / "anim.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n")
    preview = Image.new("RGBA", (cell_size * 4, cell_size * 3), (20, 25, 36, 255))
    for i, frame in enumerate(actor):
        preview.alpha_composite(frame, ((i % 4) * cell_size, (i // 4) * cell_size))
    for i, frame in enumerate(shot):
        preview.alpha_composite(frame.resize((cell_size, cell_size), Image.Resampling.NEAREST), (i * cell_size, cell_size * 2))
    preview.save(ROOT / "build/all-hero-sprites" / (uid + "_contact.png"))
    print(uid, "8 idle / 12 attack / 4 shot; original hit_ms", meta["hit_ms"])


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default=",".join(IDS))
    args = ap.parse_args()
    for uid in args.only.split(","):
        prepare(uid)
