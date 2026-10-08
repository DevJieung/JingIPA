#!/usr/bin/env python3
"""Check that an exported APK contains the runtime 3D metadata and rendering code."""
import json
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
        portraits = {re.sub(r"\.(?:remap|import)$", "", name) for name in names
                     if name.startswith("assets/art/models/portraits/") and name.endswith((".png", ".png.remap", ".png.import"))}
        assert len(portraits) == 550, "Incomplete 3D hero and awakened portrait set"
        for portrait in portraits:
            check_texture(archive, names, portrait)
        for module in ["stellar_models", "stellar_world", "stellar_view", "stellar_portraits", "stellar_backdrop"]:
            source = f"assets/game/3d/{module}.gd"
            assert source in names or source + ".remap" in names, f"Missing 3D renderer: {module}"
        assert archive.testzip() is None, "Corrupt APK ZIP member"
        print("3D assets verified: 50 hero profiles, 550 ranked portraits and five rendering modules")


def check_texture(archive, names, path):
    if path in names:
        return
    for suffix in (".import", ".remap"):
        descriptor = path + suffix
        if descriptor not in names:
            continue
        remap = archive.read(descriptor).decode("utf-8")
        match = re.search(r'^path="res://([^"\r\n]+)"\s*$', remap, re.MULTILINE)
        assert match and "assets/" + match[1] in names, f"Missing imported texture payload: {path}"
        return
    raise AssertionError(f"Missing ranked portrait: {path}")


if __name__ == "__main__":
    main()
