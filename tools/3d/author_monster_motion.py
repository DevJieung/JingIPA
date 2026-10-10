#!/usr/bin/env python3
"""Re-author the clip set of finished native monsters (geometry, UV, weights, rig untouched).

    env -u DISPLAY ~/.local/bin/bl -b --factory-startup --python tools/3d/author_monster_motion.py -- --ids blaze_fox,drop_slime
    ... -- --ids all

Opens the editable ``build/character-3d/monster-source/<id>/game.blend`` (the
manually repaired TitanBloom source included), replaces only the actions/NLA
with ``monster_motion.author_clips``, re-exports ``art/models/monsters/<id>/<id>.glb``
and records the new fingerprint in provenance.json, native_monsters.json
(``ready``/``ready_ids`` preserved) and the merged motion parameters in
native_monster_specs.json. Afterwards run ``bash tools/godot_import.sh``.
"""
import argparse
import fcntl
import hashlib
import json
import os
import struct
import sys
import time
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import monster_motion  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SPECS = ROOT / "tools/3d/native_monster_specs.json"
MANIFEST = ROOT / "art/models/native_monsters.json"
LOCK = ROOT / "build/character-3d/monster-manifest.lock"

parser = argparse.ArgumentParser()
parser.add_argument("--ids", required=True, help="comma list or 'all'")
parser.add_argument("--no-export", action="store_true", help="author clips and save the .blend only")
args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])


def geometry_digest(objects, rig):
    digest = hashlib.sha256()
    for ob in objects:
        for vertex in ob.data.vertices:
            digest.update(struct.pack("<3f", *vertex.co))
            for group in vertex.groups:
                digest.update(struct.pack("<if", group.group, group.weight))
        digest.update(str([g.name for g in ob.vertex_groups]).encode())
        digest.update(str(len(ob.data.polygons)).encode())
        digest.update(str([m.name for m in ob.data.materials]).encode())
    for bone in rig.data.bones:
        digest.update(bone.name.encode())
        digest.update(struct.pack("<6f", *bone.head_local, *bone.tail_local))
    return digest.hexdigest()


def locked_json_update(path, mutate):
    with LOCK.open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        data = json.loads(path.read_text())
        mutate(data)
        tmp = path.with_suffix(".tmp." + str(os.getpid()))
        tmp.write_text(json.dumps(data, indent=2) + "\n")
        tmp.replace(path)
        fcntl.flock(lock, fcntl.LOCK_UN)


specs = json.loads(SPECS.read_text())["monsters"]
ids = list(specs) if args.ids == "all" else [i for i in args.ids.split(",") if i]
for cid in ids:
    spec = specs[cid]
    height = float(spec["height"])
    work = ROOT / "build/character-3d/monster-source" / cid
    blend = work / "game.blend"
    if not blend.exists():
        raise SystemExit("Missing editable source " + str(blend))
    bpy.ops.wm.open_mainfile(filepath=str(blend))
    rig = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
    objects = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    before = geometry_digest(objects, rig)
    params = monster_motion.motion_params(spec)
    meta = monster_motion.author_clips(rig, spec, height, params)
    after = geometry_digest(objects, rig)
    if before != after:
        raise SystemExit("Motion authoring changed geometry or weights for " + cid)
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    if args.no_export:
        print("NATIVE_MONSTER_MOTION_BLEND", cid, flush=True)
        continue
    out = ROOT / "art/models/monsters" / cid
    out.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    temp = work / "runtime-export.glb"
    bpy.ops.export_scene.gltf(filepath=str(temp), export_format="GLB", export_apply=False, export_materials="EXPORT",
                              export_extras=True, export_yup=True, export_animations=True, export_nla_strips=True,
                              export_anim_single_armature=True, export_cameras=False, export_lights=False)
    payload = temp.read_bytes()
    dest = out / (cid + ".glb")
    temp.replace(dest)
    size = struct.unpack_from("<I", payload, 12)[0]
    gltf = json.loads(payload[20:20 + size])
    clips = [animation["name"] for animation in gltf.get("animations", [])]
    expected = ["IdleLoop", "MoveLoop", "Attack", "Die"]
    if sorted(clips) != sorted(expected):
        raise SystemExit("Exported clip set mismatch for %s: %s" % (cid, clips))
    sha = hashlib.sha256(payload).hexdigest()
    provenance_path = out / "provenance.json"
    provenance = json.loads(provenance_path.read_text()) if provenance_path.exists() else {"id": cid}
    provenance.update({
        "clips": clips,
        "glb_sha256": sha,
        "glb_bytes": len(payload),
        "game_source": str(blend),
        "motion": dict(meta, authored_at=time.strftime("%Y-%m-%dT%H:%M:%S"), tool="tools/3d/author_monster_motion.py",
                       geometry_digest=after, geometry_unchanged=True),
    })
    provenance_path.write_text(json.dumps(provenance, indent=2) + "\n")

    def update_manifest(manifest):
        row = manifest["monsters"].setdefault(cid, {})
        row.update({"path": "res://art/models/monsters/%s/%s.glb" % (cid, cid), "rig": len(rig.data.bones),
                    "height": height, "shape": spec["shape"], "metallic": spec.get("metallic", 0.0), "clips": clips,
                    "glb_sha256": sha, "motion": monster_motion.runtime_motion(spec, params)})
        row.setdefault("ready", False)

    locked_json_update(MANIFEST, update_manifest)

    def update_specs(data):
        data["monsters"][cid]["motion"] = params

    locked_json_update(SPECS, update_specs)
    print("NATIVE_MONSTER_MOTION", cid, sha, clips, meta["move_cycle_seconds"], flush=True)
