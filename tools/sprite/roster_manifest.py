#!/usr/bin/env python3
"""Record selected image_gen sources, immutable previous assets, and shipped clips."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "art/animation/roster_v1"
jobs = json.loads((WORK / "jobs.json").read_text())
record = json.loads((WORK / "generation-record.json").read_text())
repairs = record["repairs"]
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
generated = Path.home() / ".codex/generated_images"
originals = {sha(p): str(p) for p in generated.rglob("exec-*.png")}
assets = []
for job in jobs["jobs"]:
    uid = job["id"]
    path = ROOT / "art/anim" / uid / "anim.json"
    meta = json.loads(path.read_text())
    source = ROOT / job["source"]
    outputs = [str((path.parent / (meta["name"] + "_" + kind + ".png")).relative_to(ROOT)) for kind in ("idle", "attack", "shot")]
    asset = {**job, "status": "shipped", "source_sha256": sha(source),
             "original_generated_file": originals.get(sha(source)),
             "rgba": str(source.with_name(uid + "_rgba.png").relative_to(ROOT)),
             "outputs": outputs, "output_sha256": {p: sha(ROOT / p) for p in outputs},
             "metadata": str(path.relative_to(ROOT)), "metadata_sha256": sha(path),
             "previous": str((WORK / "previous" / uid).relative_to(ROOT)),
             "anchor": meta["anchor"], "scale": meta["scale"], "static": meta["static"],
             "muzzle_at": meta["muzzle_at"], "hit_ms": meta["hit_ms"],
             "cell": meta["cell"], "clips": meta["clips"], "processing": meta["readability"]}
    if uid in repairs:
        asset["repair"] = repairs[uid]
    assets.append(asset)
    job["status"] = "shipped"
manifest = {"generator": "built-in image_gen", "created": "2026-09-14", "assets": assets,
            "approved_preserved_ids": ["thalassa", "brasa", "sigrid", "lugh", "blank"],
            "pipeline": "imagegen keyed source > binary RGBA matte > transparent gutter extraction > nearest scale > foot baseline and boot-center alignment > shared 96-color actor palette > 8/12/4 frame timing",
            "anatomy": "Original generated limbs/equipment preserved; no lower-body patch copying.",
            "qc": "build/all-hero-sprites/final-qc.json",
            "visual_pages": "build/all-hero-sprites/visual-pages.json"}
(WORK / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
(WORK / "jobs.json").write_text(json.dumps(jobs, ensure_ascii=False, indent=2) + "\n")
registry_path = ROOT / "art/generated-assets.json"
registry = json.loads(registry_path.read_text())
registry["assets"] = [a for a in registry["assets"] if a.get("manifest") != "art/animation/roster_v1/manifest.json"]
for asset in assets:
    registry["assets"].append({"path": asset["outputs"][0], "outputs": asset["outputs"],
                               "source": asset["source"], "prompt": asset["prompt"],
                               "manifest": "art/animation/roster_v1/manifest.json"})
registry_path.write_text(json.dumps(registry, ensure_ascii=False, indent=2) + "\n")
print("Recorded", len(assets), "heroes /", sum(len(a["outputs"]) for a in assets), "new clips")
