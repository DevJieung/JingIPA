#!/usr/bin/env python3
"""Check that an exported APK contains the runtime 3D metadata and rendering code."""
import json
from pathlib import Path
import re
import sys
import zipfile


def main():
    with zipfile.ZipFile(sys.argv[1]) as archive:
        names = set(archive.namelist())
        manifest = json.loads(archive.read("assets/art/models/manifest.json"))
        assert len(manifest["heroes"]) == 50, "Incomplete 3D hero profiles"
        for identity in manifest["heroes"]:
            for grade in range(10):
                portrait = f"assets/art/models/portraits/{identity}/{grade:02d}.png"
                check_texture(archive, names, portrait)
            awakened_grade = int(manifest["heroes"][identity]["index"]) // 5
            check_texture(archive, names, f"assets/art/models/portraits/{identity}/{awakened_grade:02d}_awakened.png")
        portraits = {re.sub(r"\.(?:remap|import)$", "", name) for name in names
                     if name.startswith("assets/art/models/portraits/") and name.endswith((".png", ".png.remap", ".png.import"))}
        assert len(portraits) == 550, "Incomplete 3D hero and awakened portrait set"
        for portrait in portraits:
            check_texture(archive, names, portrait)
        for module in ["stellar_models", "stellar_world", "stellar_view", "stellar_portraits", "stellar_backdrop"]:
            source = f"assets/game/3d/{module}.gd"
            assert source in names or source + ".remap" in names, f"Missing 3D renderer: {module}"
        for module in ["core/arena_run", "core/arena_validation", "core/arena_geometry", "game/arena_sim", "game/arena_screen",
                       "game/3d/arena_view", "game/3d/arena_world"]:
            source = f"assets/{module}.gd"
            assert source in names or source + ".remap" in names, f"Missing continuous battle module: {module}"
        check_imported_resource(archive, names, "assets/art/models/arena_ground.gdshader")
        check_imported_resource(archive, names, "assets/art/models/arena_road.gdshader")
        assert not any(name in names for name in ("assets/asis.jpg", "assets/asis.jpg.import",
                       "assets/tobe.png", "assets/tobe.png.import")), "Design references must not ship"
        catalog = json.loads(archive.read("assets/core/locales/ui.json"))
        for locale in ("ko", "en"):
            for key in ("arena.title", "arena.rules.control", "arena.rules.growth", "arena.rules.boss"):
                assert catalog[locale].get(key), f"Missing continuous battle translation: {locale}/{key}"
        adapter = "assets/game/3d/limne_model.gd"
        assert adapter in names or adapter + ".remap" in names, "Missing Limne model adapter"
        check_imported_resource(archive, names, "assets/art/models/limne/limne.glb")
        check_imported_resource(archive, names, "assets/art/models/limne/water_spray.gdshader")
        native = json.loads(archive.read("assets/art/models/native_heroes.json"))
        expected = set(manifest["heroes"]) - {"limne"}
        assert set(native["heroes"]) == expected, "Incomplete native hero roster"
        assert set(native["ready_ids"]) == expected and len(native["ready_ids"]) == len(expected), \
            "Not every native hero passed visual review"
        adapter = "assets/game/3d/native_character_model.gd"
        assert adapter in names or adapter + ".remap" in names, "Missing native character adapter"
        for identity in sorted(expected):
            assert native["heroes"][identity].get("ready") is True, f"Native hero review is incomplete: {identity}"
            path = native["heroes"][identity]["path"]
            assert path == f"res://art/models/{identity}/{identity}.glb", f"Invalid native model path: {identity}"
            check_imported_resource(archive, names, "assets/" + path.removeprefix("res://"))
        roster_path = Path(__file__).resolve().parents[1] / "roster.json"
        expected_monsters = {row["id"] for row in json.loads(roster_path.read_text())["monsters"]}
        assert len(expected_monsters) == 25, "Invalid canonical monster roster"
        monsters = json.loads(archive.read("assets/art/models/native_monsters.json"))
        assert set(monsters["monsters"]) == expected_monsters, "Incomplete native monster roster"
        assert set(monsters["ready_ids"]) == expected_monsters and len(monsters["ready_ids"]) == 25, \
            "Not every native monster passed visual review"
        adapter = "assets/game/3d/native_monster_model.gd"
        assert adapter in names or adapter + ".remap" in names, "Missing native monster adapter"
        for identity in sorted(expected_monsters):
            row = monsters["monsters"][identity]
            assert row.get("ready") is True, f"Native monster review is incomplete: {identity}"
            path = f"res://art/models/monsters/{identity}/{identity}.glb"
            assert row.get("path") == path, f"Invalid native monster path: {identity}"
            check_imported_resource(archive, names, "assets/" + path.removeprefix("res://"))
            check_texture(archive, names, f"assets/art/models/monsters/{identity}.png")
        assert not any(name.startswith("assets/art/models/sources/") or name.endswith(".blend")
                       for name in names), "Offline Blender sources must not ship"
        assert archive.testzip() is None, "Corrupt APK ZIP member"
        print("3D assets verified: 50 native heroes, 25 native monsters, 575 portraits and runtime adapters")


def check_texture(archive, names, path):
    check_imported_resource(archive, names, path)


def check_imported_resource(archive, names, path):
    if path in names:
        return
    for suffix in (".import", ".remap"):
        descriptor = path + suffix
        if descriptor not in names:
            continue
        remap = archive.read(descriptor).decode("utf-8")
        match = re.search(r'^path="res://([^"\r\n]+)"\s*$', remap, re.MULTILINE)
        assert match and "assets/" + match[1] in names, f"Missing imported resource payload: {path}"
        return
    raise AssertionError(f"Missing packaged resource: {path}")


if __name__ == "__main__":
    main()
