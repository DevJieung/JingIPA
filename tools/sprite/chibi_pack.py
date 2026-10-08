from pathlib import Path
import argparse
import copy
import hashlib
import json
import math
import shutil

import numpy as np
from PIL import Image
from scipy.ndimage import label

from roster_pack import separators, shared_palette

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "art/animation/chibi_v1"


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")


def clean_alpha(image):
    array = np.array(image.convert("RGBA"))
    if array[:, :, 3].min() > 0:
        raise ValueError("Generated image lacks genuine transparency")
    mask = array[:, :, 3] >= 128
    labels, _ = label(mask, np.ones((3, 3)))
    sizes = np.bincount(labels.ravel())
    mask &= sizes[labels] > 4
    array[:, :, 3] = mask.astype(np.uint8) * 255
    array[~mask] = 0
    return Image.fromarray(array)


def extract(image, columns, rows, row_edges=None):
    if row_edges is None:
        row_edges = separators(image, rows, True)
    rectangles = []
    cells = []
    for row in range(rows):
        strip = image.crop((0, row_edges[row], image.width, row_edges[row + 1]))
        array = np.array(strip)
        labels, total = label(array[:, :, 3] > 0, np.ones((3, 3)))
        groups = [[] for column in range(columns)]
        for component in range(1, total + 1):
            positions = np.argwhere(labels == component)
            center = positions[:, 1].mean()
            if positions[:, 1].max() - positions[:, 1].min() > image.width / columns * 1.65:
                raise ValueError("Neighboring generated sprites touch; regenerate source")
            groups[min(columns - 1, int(center / image.width * columns))].append(component)
        for group in groups:
            cell_array = array.copy()
            cell_array[~np.isin(labels, group)] = 0
            cell = Image.fromarray(cell_array)
            bounds = cell.getbbox()
            if bounds is None:
                raise ValueError("Empty generated cell")
            rectangle = (max(0, bounds[0] - 6), row_edges[row], min(image.width, bounds[2] + 6), row_edges[row + 1])
            cells.append(cell.crop((rectangle[0], 0, rectangle[2], strip.height)))
            rectangles.append(rectangle)
    return cells, rectangles


def backup(uid, directory):
    previous = WORK / "previous" / uid
    if not previous.exists():
        shutil.copytree(directory, previous)
        for group in ("portraits", "units", "monsters"):
            original = ROOT / "art" / group / (uid + ".png")
            if original.exists():
                shutil.copy2(original, previous / (group + ".png"))
    return json.loads((previous / "anim.json").read_text())


def pack_hero(uid):
    directory = ROOT / "art/anim" / uid
    original = backup(uid, directory)
    metadata = copy.deepcopy(original)
    generated = Image.open(WORK / "source" / (uid + ".png")).convert("RGBA")
    clean = clean_alpha(generated)
    row_overrides = {"morrigan": [0, 488, 925, 1086], "volcan": [0, 420, 802, 1086]}
    cells, rectangles = extract(clean, 4, 3, row_overrides.get(uid))
    target_height = int(metadata["static"]["h"])
    bounds = cells[0].getbbox()
    factor = target_height / (bounds[3] - bounds[1])
    actors = []
    extents = []
    transforms = []
    for cell in cells[:8]:
        bounds = cell.getbbox()
        boots = cell.crop((0, bounds[3] - 20, cell.width, bounds[3])).getbbox()
        boot_center = (boots[0] + boots[2]) / 2
        resized = cell.resize((round(cell.width * factor), round(cell.height * factor)), Image.Resampling.NEAREST)
        offset = (round(-boot_center * factor), round(-bounds[3] * factor))
        extent = tuple(value + offset[index % 2] for index, value in enumerate(resized.getbbox()))
        actors.append((resized, offset))
        extents.append(extent)
        transforms.append({"factor": factor, "offset": list(offset)})
    anchor_x = max(int(original["anchor"]["x"]), 8 - min(extent[0] for extent in extents))
    anchor_y = max(int(original["anchor"]["y"]), 8 - min(extent[1] for extent in extents))
    cell_size = max(256, math.ceil((anchor_x + max(extent[2] for extent in extents) + 8) / 64) * 64,
                    math.ceil((anchor_y + max(extent[3] for extent in extents) + 8) / 64) * 64)
    frames = []
    for (resized, offset), transform in zip(actors, transforms):
        frame = Image.new("RGBA", (cell_size, cell_size))
        position = (anchor_x + offset[0], anchor_y + offset[1])
        frame.paste(resized, position)
        frames.append(frame)
        transform["offset"] = list(position)
    frames = shared_palette(frames)
    idle = [frames[index] for index in (0, 1, 2, 3, 3, 2, 1, 0)]
    hit_frame = int(metadata["clips"]["attack"]["hit_frame"])
    attack = [frames[0] if index in (0, 11) else (frames[4] if index < 3 else frames[5]) if index < hit_frame
              else frames[6] if index < min(hit_frame + 2, 11) else frames[7] for index in range(12)]
    metadata["source"] = "imagegen_chibi_v1"
    metadata["fixed_feet"] = False
    metadata.pop("foot_pin_box", None)
    metadata["cell"] = {"w": cell_size, "h": cell_size}
    metadata["anchor"] = {"x": anchor_x, "y": anchor_y}
    metadata["palette_colors"] = 96
    metadata["portrait_id"] = uid
    metadata["readability"] = {"version": 3, "source": f"art/animation/chibi_v1/source/{uid}.png",
                               "method": "imagegen chibi repaint; alpha threshold, extraction, nearest sampling, shared palette and foot alignment only",
                               "source_cells": rectangles, "source_transforms": transforms}
    landmarks = json.loads((ROOT / "tools/sprite/chibi_landmarks.json").read_text())
    if uid in landmarks:
        point = landmarks[uid]
        release = transforms[6]
        metadata["muzzle_at"] = {
            "x": round((point[0] - rectangles[6][0]) * factor + release["offset"][0] - anchor_x),
            "y": round((point[1] - rectangles[6][1]) * factor + release["offset"][1] - anchor_y),
        }
        metadata["readability"]["source_muzzle"] = point
    for name, clip_frames in (("idle", idle), ("attack", attack)):
        strip = Image.new("RGBA", (cell_size * len(clip_frames), cell_size))
        for index, frame in enumerate(clip_frames):
            strip.paste(frame, (index * cell_size, 0))
        output = directory / (metadata["name"] + "_" + name + ".png")
        strip.save(output)
        metadata["clips"][name]["cell"] = metadata["cell"].copy()
        metadata["clips"][name]["sha256"] = hashlib.sha256(output.read_bytes()).hexdigest()
    portrait = generated.crop(rectangles[0])
    portrait_bounds = clean.crop(rectangles[0]).getbbox()
    portrait = portrait.crop((max(0, portrait_bounds[0] - 6), max(0, portrait_bounds[1] - 6),
                              min(portrait.width, portrait_bounds[2] + 6), min(portrait.height, portrait_bounds[3] + 6)))
    padded_portrait = Image.new("RGBA", (portrait.width + 16, portrait.height + 16))
    padded_portrait.paste(portrait, (8, 8))
    padded_portrait.save(ROOT / "art/portraits" / (uid + ".png"))
    static = frames[0].crop(frames[0].getbbox())
    static = static.resize((max(1, round(static.width * metadata["scale"])),
                            max(1, round(static.height * metadata["scale"]))), Image.Resampling.NEAREST)
    static.save(ROOT / "art/units" / (uid + ".png"))
    write_json(directory / "anim.json", metadata)
    report = {"id": uid, "source": metadata["readability"]["source"], "cell": metadata["cell"],
              "anchor": metadata["anchor"], "scale": metadata["scale"], "original_muzzle": original["muzzle_at"],
              "release_transform": transforms[6], "release_source_bounds": list(cells[6].getbbox()),
              "status": "packed", "source_sha256": hashlib.sha256((WORK / "source" / (uid + ".png")).read_bytes()).hexdigest()}
    write_json(WORK / "reports" / (uid + ".json"), report)
    print(uid, "packed", metadata["cell"], metadata["anchor"])


def pack_monster(uid):
    directory = ROOT / "art/anim/monsters" / uid
    original = backup(uid, directory)
    metadata = copy.deepcopy(original)
    generated = clean_alpha(Image.open(WORK / "source" / (uid + ".png")))
    cells, rectangles = extract(generated, 4, 2)
    old_sheet = Image.open(WORK / "previous" / uid / (original["name"] + "_move.png"))
    old_frame = old_sheet.crop((0, 0, original["cell"]["w"], original["cell"]["h"]))
    old_bounds = old_frame.getbbox()
    target_height = old_bounds[3] - old_bounds[1]
    source_bounds = cells[0].getbbox()
    factor = target_height / (source_bounds[3] - source_bounds[1])
    actors = []
    extents = []
    for cell in cells:
        bounds = cell.getbbox()
        center = (bounds[0] + bounds[2]) / 2
        resized = cell.resize((round(cell.width * factor), round(cell.height * factor)), Image.Resampling.NEAREST)
        offset = (round(-center * factor), round(-bounds[3] * factor))
        extents.append(tuple(value + offset[index % 2] for index, value in enumerate(resized.getbbox())))
        actors.append((resized, offset))
    anchor_x = max(int(original["anchor"]["x"]), 8 - min(extent[0] for extent in extents))
    anchor_y = max(int(original["anchor"]["y"]), 8 - min(extent[1] for extent in extents))
    size = max(192, math.ceil((anchor_x + max(extent[2] for extent in extents) + 8) / 64) * 64,
               math.ceil((anchor_y + max(extent[3] for extent in extents) + 8) / 64) * 64)
    frames = []
    for resized, offset in actors:
        frame = Image.new("RGBA", (size, size))
        frame.paste(resized, (anchor_x + offset[0], anchor_y + offset[1]))
        frames.append(frame)
    frames = shared_palette(frames)
    count = int(metadata["clips"]["move"]["frames"])
    phase_map = [min(7, int(index * 8 / count)) for index in range(count)]
    strip = Image.new("RGBA", (size * count, size))
    for index, source_index in enumerate(phase_map):
        strip.paste(frames[source_index], (index * size, 0))
    output = directory / (metadata["name"] + "_move.png")
    strip.save(output)
    metadata["source"] = "imagegen_chibi_v1"
    metadata["cell"] = {"w": size, "h": size}
    metadata["anchor"] = {"x": anchor_x, "y": anchor_y}
    metadata["palette_colors"] = 96
    metadata["clips"]["move"]["cell"] = metadata["cell"].copy()
    metadata["clips"]["move"]["sha256"] = hashlib.sha256(output.read_bytes()).hexdigest()
    metadata["readability"] = {"version": 3, "source": f"art/animation/chibi_v1/source/{uid}.png",
                               "source_cells": rectangles, "phase_map": phase_map,
                               "method": "imagegen chibi movement repaint; alpha threshold, extraction, nearest sampling and shared palette only"}
    metadata["qc"] = {"canvas_clipping": False, "source_clipping": False, "unique_poses": 8,
                      "forward_only": True, "fixed_scale": True, "foot_patches": False}
    static = frames[0].crop(frames[0].getbbox())
    static = static.resize((max(1, round(static.width * metadata["scale"])),
                            max(1, round(static.height * metadata["scale"]))), Image.Resampling.NEAREST)
    static.save(ROOT / "art/monsters" / (uid + ".png"))
    write_json(directory / "anim.json", metadata)
    write_json(WORK / "reports" / (uid + ".json"), {"id": uid, "kind": "monster", "status": "packed",
               "source": metadata["readability"]["source"], "cell": metadata["cell"], "anchor": metadata["anchor"],
               "source_sha256": hashlib.sha256((WORK / "source" / (uid + ".png")).read_bytes()).hexdigest()})
    print(uid, "packed", metadata["cell"], metadata["anchor"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", required=True)
    parser.add_argument("--monsters", action="store_true")
    options = parser.parse_args()
    for unit_id in options.only.split(","):
        if options.monsters:
            pack_monster(unit_id)
        else:
            pack_hero(unit_id)
