#!/usr/bin/env python3
"""Generate the shared UI materials with the project's local Krea 2 Turbo.

Uses gen_art's scene anchor, deterministic seeds and pixel processing.
Run: python3 tools/gen_ui_refresh.py (existing assets are kept).
"""
import json
from pathlib import Path

import gen_art as art
import gpu_guard

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "art/ui/refuge"
JOBS = {
    "camp": (1024, 640, 640, 400,
        "A welcoming fantasy expedition trading camp inside an ancient ruined stone sanctuary, "
        "teal canvas awnings at both sides, amber hanging lanterns, timber merchant counters, "
        "a small blacksmith forge on the right, playing cards and brass tokens on the left, "
        "distant blue crystal shrine visible through a central archway, no people, "
        "wide composition, clear quiet central space, warm chestnut wood, deep teal shadows, "
        "soft amber light, chunky deliberate pixel clusters, rich midtone colors"),
    "wood": (768, 768, 128, 128,
        "Seamless flat texture of dark chestnut timber planks, straight overhead view, "
        "subtle grain and small worn scratches, three warm brown tones, evenly illuminated, "
        "quiet low contrast surface for a fantasy game equipment board, entire frame is wood"),
    "stone": (768, 768, 128, 128,
        "Seamless flat ground texture of ancient blue slate flagstone tiles, directly overhead, "
        "small moss seams and worn sandstone edges, muted teal gray and warm slate, "
        "quiet low contrast three tone pixel blocks, entire frame is stone"),
    "button": (1024, 256, 256, 64,
        "One long horizontal fantasy game wooden sign plaque fills the entire frame edge to edge, "
        "straight front view, ornate antique brass bevel around chestnut wood center, "
        "small brass corner rivets, symmetrical stepped pixel corners, central seventy percent "
        "is empty dark polished wood for a readable label, amber upper left highlights, "
        "teal inlay at the ends, bold chunky pixel clusters, no lettering"),
}

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = {name: {"model": "Krea 2 Turbo (local)", "seed": art._seed("refuge_" + name),
                      "prompt": job[4] + ", " + art.SCENE} for name, job in JOBS.items()}
    (OUT / "prompts.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    todo = [name for name in JOBS if not (OUT / (name + ".png")).exists()]
    if not todo:
        return
    gpu_guard.claim("krea2")
    from krea2.pipelines.image import Krea2ImagePipeline
    pipe = Krea2ImagePipeline("turbo").load()
    for name in todo:
        w, h, ow, oh, _ = JOBS[name]
        print("[refuge] generating " + name, flush=True)
        img = pipe.generate(manifest[name]["prompt"], width=w, height=h,
                            seed=manifest[name]["seed"])[0].image
        art.pixelize(img, oh, 48, ow).save(OUT / (name + ".png"))
        print("[refuge] saved " + name, flush=True)

if __name__ == "__main__":
    main()
