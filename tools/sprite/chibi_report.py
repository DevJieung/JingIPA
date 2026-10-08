from pathlib import Path
import hashlib
import json

import numpy as np
from PIL import Image

from chibi_contacts import contact
from chibi_pack import ROOT, WORK, write_json

REVIEW = ROOT / "build/chibi-review"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def first_frame(directory, metadata, clip):
    info = metadata["clips"][clip]
    cell = info.get("cell", metadata["cell"])
    sheet = Image.open(directory / (metadata["name"] + "_" + clip + ".png")).convert("RGBA")
    return sheet.crop((0, 0, cell["w"], cell["h"]))


def main():
    assets = []
    failures = []
    metrics = []
    total_frames = 0
    for monster, pattern in ((False, "*/anim.json"), (True, "monsters/*/anim.json")):
        for path in sorted((ROOT / "art/anim").glob(pattern)):
            metadata = json.loads(path.read_text())
            uid = path.parent.name
            previous = WORK / "previous" / uid
            original = json.loads((previous / "anim.json").read_text())
            if metadata.get("source") != "imagegen_chibi_v1":
                failures.append(uid + ": missing chibi source")
            clips = ["move"] if monster else ["idle", "attack"]
            outputs = [path]
            for clip in clips:
                info = metadata["clips"][clip]
                for key in ("frames", "ms", "loop", "hit_frame"):
                    if info.get(key) != original["clips"][clip].get(key):
                        failures.append(uid + ": changed gameplay timing " + key)
                output = path.parent / (metadata["name"] + "_" + clip + ".png")
                outputs.append(output)
                sheet = Image.open(output).convert("RGBA")
                cell = info.get("cell", metadata["cell"])
                if sheet.size != (cell["w"] * info["frames"], cell["h"]):
                    failures.append(uid + ": incorrect sheet dimensions")
                if digest(output) != info["sha256"]:
                    failures.append(uid + ": incorrect sheet hash")
                if not set(np.unique(np.array(sheet)[:, :, 3])) <= {0, 255}:
                    failures.append(uid + ": nonbinary game alpha")
                unique = set()
                feet = []
                for index in range(info["frames"]):
                    frame = sheet.crop((index * cell["w"], 0, (index + 1) * cell["w"], cell["h"]))
                    bounds = frame.getbbox()
                    total_frames += 1
                    if bounds is None:
                        failures.append(uid + ": empty frame")
                        continue
                    if min(bounds[:2]) <= 0 or bounds[2] >= cell["w"] or bounds[3] >= cell["h"]:
                        failures.append(uid + ": canvas clipping")
                    unique.add(frame.tobytes())
                    feet.append(bounds[3])
                if not monster and max(feet) - min(feet) > 2:
                    failures.append(uid + ": sliding feet")
                if monster and len(unique) < 8:
                    failures.append(uid + ": fewer than eight distinct movement phases")
            if metadata["scale"] != original["scale"] or metadata.get("hit_ms") != original.get("hit_ms"):
                failures.append(uid + ": changed world scale or release time")
            outputs.append(ROOT / ("art/monsters" if monster else "art/units") / (uid + ".png"))
            if not monster:
                outputs.append(ROOT / "art/portraits" / (uid + ".png"))
            source = WORK / "source" / (uid + ".png")
            generation = json.loads(source.with_suffix(".json").read_text())
            repair = source.with_name(uid + "_repair.json")
            if repair.exists():
                generation["repair"] = json.loads(repair.read_text())
            assets.append({"id": uid, "kind": "monster" if monster else "hero",
                           "source": str(source.relative_to(ROOT)), "source_sha256": digest(source),
                           "generation": generation, "outputs": [
                               {"path": str(output.relative_to(ROOT)), "sha256": digest(output)} for output in outputs]})
            clip = clips[0]
            before = first_frame(previous, original, clip)
            after = first_frame(path.parent, metadata, clip)
            before_bounds, after_bounds = before.getbbox(), after.getbbox()
            metrics.append({"id": uid, "kind": "monster" if monster else "hero",
                            "before_bounds": before_bounds, "after_bounds": after_bounds,
                            "width_ratio": round((after_bounds[2] - after_bounds[0]) / (before_bounds[2] - before_bounds[0]), 3),
                            "alpha_area_ratio": round(np.count_nonzero(np.array(after)[:, :, 3]) / np.count_nonzero(np.array(before)[:, :, 3]), 3)})
            if uid in ["limne", "brasa", "sigrid", "rhiannon", "pyre_priest", "glacier_dragon"]:
                directory = REVIEW / "comparison"
                directory.mkdir(parents=True, exist_ok=True)
                before.save(directory / (uid + "_before.png"))
                after.save(directory / (uid + "_after.png"))
    dealer = ROOT / "art/ui/dealer/witch.png"
    source = WORK / "source/dealer.png"
    assets.append({"id": "dealer", "kind": "npc", "source": str(source.relative_to(ROOT)),
                   "source_sha256": digest(source), "generation": json.loads(source.with_suffix(".json").read_text()),
                   "outputs": [{"path": str(dealer.relative_to(ROOT)), "sha256": digest(dealer)}]})
    counts = {kind: sum(asset["kind"] == kind for asset in assets) for kind in ("hero", "monster", "npc")}
    if counts != {"hero": 50, "monster": 25, "npc": 1}:
        failures.append("Incomplete character inventory")
    manifest = {"version": 1, "generator": "built-in image_gen edits", "style": "imagegen_chibi_v1",
                "counts": counts, "postprocessing": "alpha threshold, atlas extraction, nearest scaling, shared palette and foot-origin alignment; no procedural anatomy replacement",
                "preserved": ["identity", "equipment", "element", "world scale", "attack and movement timing", "shot/effect sprites"],
                "assets": assets}
    write_json(ROOT / "art/chibi-manifest.json", manifest)
    write_json(REVIEW / "coverage.json", {"counts": counts, "actor_frames": total_frames, "failures": failures, "metrics": metrics})
    contact(sorted((ROOT / "art/portraits").glob("*.png")), REVIEW / "heroes.png", columns=10, cell=200)
    contact(sorted((ROOT / "art/monsters").glob("*.png")), REVIEW / "monsters.png", columns=5, cell=220)
    comparison = []
    for uid in ["limne", "brasa", "sigrid", "rhiannon", "pyre_priest", "glacier_dragon"]:
        comparison.extend([REVIEW / "comparison" / (uid + "_before.png"), REVIEW / "comparison" / (uid + "_after.png")])
    contact(comparison, REVIEW / "before-after.png", columns=4, cell=240)
    print(json.dumps({"counts": counts, "actor_frames": total_frames, "failures": failures}, ensure_ascii=False))
    raise SystemExit(bool(failures))


if __name__ == "__main__":
    main()
