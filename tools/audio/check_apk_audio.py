#!/usr/bin/env python3
"""Verify shipped audio/visual dependencies before replacing the fixed APK."""
import json
import re
from pathlib import Path
import sys
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[2]

def imported_path(text):
    # Godot ConfigFile also contains Variant dictionaries and a trailing NUL;
    # it is not INI. Read only the exported remap path we need to verify.
    remap = text.split('[remap]', 1)[1].split('\n[', 1)[0]
    path = re.search(r'^path="(res://[^"\n]+)"', remap, re.MULTILINE)
    assert path, 'exported resource has no remap path'
    return path.group(1).removeprefix('res://')

def main():
    with ZipFile(sys.argv[1]) as apk:
        names = set(apk.namelist())
        assert not any(Path(x).name.startswith('.env') or '/art/audio_sources/' in x for x in names), 'private/source files in APK'
        count = 0
        for folder, suffix in [('art/sfx', '*.wav'), ('art/bgm', '*.ogg'), ('art/ui/dealer', '*.png')]:
            for source in (ROOT / folder).glob(suffix):
                meta = source.with_name(source.name + '.import')
                relative = str(meta.relative_to(ROOT))
                assert 'assets/' + relative in names, f'missing import metadata: {relative}'
                imported = imported_path(apk.read('assets/' + relative).decode())
                assert 'assets/' + imported in names, f'missing imported resource: {imported}'
                assert apk.read('assets/' + imported) == (ROOT / imported).read_bytes(), f'stale imported resource: {source.name}'
                count += 1
        themes = json.loads((ROOT / 'tools/roster.json').read_text())['themes']
        for theme in themes:
            relative = 'assets/art/bgm/theme_' + theme['id'] + '.ogg.import'
            assert relative in names, f'missing theme music: {theme["id"]}'
        assert count >= 53 + len(themes), 'expected effects, scene/theme BGM and dealer/card artwork'
    print(f'APK assets verified: {count} current resources; .env and raw audio sources excluded.')

if __name__ == '__main__':
    main()
