#!/usr/bin/env python3
"""Publish the 2026-10-15 mobile LOD candidates into the runtime and record them.

    python3 tools/3d/publish_native_lod.py install --all        # candidates -> art/models, records
    bash tools/godot_import.sh                                  # Godot extracts the new albedo PNGs
    python3 tools/3d/publish_native_lod.py textures             # lossy WebP import settings
    bash tools/godot_import.sh
    python3 tools/3d/publish_native_lod.py summary              # before/after table + imported sizes

`install` (per id, from build/character-3d/lod-2026-10-15/<id>/report.json and
candidates/<id>.glb produced by tools/3d/optimize_native_lod.py --candidates):
  * copies the candidate GLB over the runtime GLB (the reviewed high-poly GLB, its extracted
    textures and .import files are preserved in build/character-3d/highpoly-2026-10-15/)
  * deletes every other extracted texture in that model folder: Godot ships any imported PNG
    under art/, used or not (elder_treant and titan_bloom carried a stale 1024 texture each)
  * writes glb_sha256 into art/models/native_heroes.json / native_monsters.json (checked by
    tests/native_hero_check.gd and native_monster_check.gd) and a `mobile_lod` block into
    the model's provenance.json
  * points the clip tools at the shipped geometry: build/motion-overhaul/glb-base/<id>.glb
    (author_native_motion.py grafts new clips onto it) and Limne's
    build/limne-game-motion/before-motion2/limne.glb (style_animate_limne.py)
`textures` sets compress/mode=1 (lossy WebP) and lossy_quality=0.8 on every *_lod_albedo.png
import: at 1.5x the legacy BattleScreen's maximum zoom lossless, lossy 0.7/0.85 and ETC2 were
indistinguishable (mean difference 0.4-1.0 of 255) and a 512 albedo is 83-119 KB lossy
against 447 KB lossless and 175 KB ETC2. Godot keeps these params when it re-extracts.
"""
import argparse, fcntl, hashlib, json, os, re, shutil, struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / 'build/character-3d/lod-2026-10-15'
HIGHPOLY = ROOT / 'build/character-3d/highpoly-2026-10-15'
HEROES = ROOT / 'art/models/native_heroes.json'
MONSTERS = ROOT / 'art/models/native_monsters.json'
TEXTURE_PARAMS = {'compress/mode': '1', 'compress/lossy_quality': '0.8'}


def all_ids():
    return list(json.loads(HEROES.read_text())['ready_ids']) + ['limne'] + list(json.loads(MONSTERS.read_text())['ready_ids'])


def runtime(cid):
    if cid == 'limne':
        return 'limne', ROOT / 'art/models/limne/limne.glb'
    if cid in json.loads(HEROES.read_text())['heroes']:
        return 'hero', ROOT / 'art/models' / cid / f'{cid}.glb'
    return 'monster', ROOT / 'art/models/monsters' / cid / f'{cid}.glb'


def glb_stats(payload):
    length = struct.unpack_from('<I', payload, 12)[0]
    g = json.loads(payload[20:20 + length])
    prims = [p for m in g.get('meshes', []) for p in m['primitives']]
    return {'triangles': sum(g['accessors'][p['indices']]['count'] // 3 for p in prims),
            'vertices': sum(g['accessors'][p['attributes']['POSITION']]['count'] for p in prims),
            'meshes': len(g.get('meshes', [])), 'surfaces': len(prims), 'materials': len(g.get('materials', [])),
            'images': len(g.get('images', [])), 'bytes': len(payload), 'sha256': hashlib.sha256(payload).hexdigest()}


def image_sizes(payload):
    """[width, height] of every embedded PNG of a GLB."""
    length = struct.unpack_from('<I', payload, 12)[0]
    g = json.loads(payload[20:20 + length])
    start = 20 + length + 8
    out = []
    for image in g.get('images', []):
        view = g['bufferViews'][image['bufferView']]
        data = payload[start + view.get('byteOffset', 0):start + view.get('byteOffset', 0) + view['byteLength']]
        out.append(list(struct.unpack('>II', data[16:24])) if data[:8] == b'\x89PNG\r\n\x1a\n' else None)
    return out


def locked_update(path, lock, mutate):
    with lock.open('a') as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        data = json.loads(path.read_text())
        mutate(data)
        tmp = path.with_suffix('.tmp.' + str(os.getpid()))
        tmp.write_text(json.dumps(data, indent=2) + '\n')
        tmp.replace(path)
        fcntl.flock(handle, fcntl.LOCK_UN)


def install(ids):
    for cid in ids:
        kind, dest = runtime(cid)
        report = json.loads((WORK / cid / 'report.json').read_text())
        payload = (WORK / 'candidates' / f'{cid}.glb').read_bytes()
        sha = hashlib.sha256(payload).hexdigest()
        if sha != report['after']['glb_sha256']:
            raise SystemExit(f'{cid}: candidate GLB is not the one its report describes')
        backup = HIGHPOLY / 'art-models' / dest.relative_to(ROOT / 'art/models')
        if not backup.exists():
            raise SystemExit(f'{cid}: high-poly backup missing ({backup})')
        before = glb_stats(backup.read_bytes())
        dest.write_bytes(payload)
        keep = f'{cid}_{cid}_lod_albedo.png'
        removed = []
        for png in sorted(dest.parent.glob('*.png')):
            if png.name == keep: continue
            png.unlink(); Path(str(png) + '.import').unlink(missing_ok=True); removed.append(png.name)
        after = glb_stats(payload)
        prov_path = dest.parent / 'provenance.json'
        prov = json.loads(prov_path.read_text()) if prov_path.exists() else {'id': cid}
        prov['mobile_lod'] = {
            'date': '2026-10-15',
            'request': 'user 2026-10-15: app size first, polygon reduction most of all; judged on real battle captures',
            'tool': 'tools/3d/optimize_native_lod.py + tools/3d/lod_reduce_vtk.py; records by tools/3d/publish_native_lod.py',
            'method': ('visible sheet only (faces seen from >= 3 of 128 directions; the reconstruction\'s hidden inner '
                       'sheets removed), VTK quadric decimation with skin weights interpolated along every collapse, '
                       'xatlas atlas, Cycles EMIT bake of the exact source colour (visible faces first, all sheets as '
                       'fallback), nearest-texel gutter fill, box downsample; clip bytes grafted unchanged from the '
                       'reviewed high-poly GLB (rig, sockets, release timing, grounding unchanged)'),
            'budget': report['budget'],
            'before': dict(before, texture=image_sizes(backup.read_bytes()), texture_import={'compress/mode': '0 (lossless)'}),
            'after': dict(after, texture=report['budget']['texture'], texture_import=TEXTURE_PARAMS),
            'surface_deviation_m': report['deviation_m'],
            'bake': report['bake'], 'atlas': report['atlas'],
            'visible_faces': report.get('bake_source_visibility'),
            'sole': {'before': report['before'].get('sole'), 'after': report['after'].get('sole')},
            'removed_extracted_textures': removed,
            'highpoly_backup': str(backup.relative_to(ROOT)),
            'editable_lod_source': str(Path(report['lod_blend']).relative_to(ROOT)),
        }
        prov['glb_sha256'] = sha
        prov['glb_bytes'] = len(payload)
        prov_path.write_text(json.dumps(prov, indent=2) + '\n')
        if kind == 'hero':
            base = ROOT / 'build/motion-overhaul/glb-base' / f'{cid}.glb'
            base.parent.mkdir(parents=True, exist_ok=True); base.write_bytes(payload)
            locked_update(HEROES, ROOT / 'build/character-3d/native-manifest.lock',
                          lambda m: m['heroes'][cid].__setitem__('glb_sha256', sha))
        elif kind == 'monster':
            locked_update(MONSTERS, ROOT / 'build/character-3d/monster-manifest.lock',
                          lambda m: m['monsters'][cid].__setitem__('glb_sha256', sha))
        else:
            (ROOT / 'build/limne-game-motion/before-motion2/limne.glb').write_bytes(payload)
        print(f'installed {cid}: {before["triangles"]} -> {after["triangles"]} tris, '
              f'{before["surfaces"]} -> {after["surfaces"]} surfaces, removed {removed}')


def textures():
    changed = 0
    for path in sorted((ROOT / 'art/models').rglob('*_lod_albedo.png.import')):
        text = path.read_text()
        new = text
        for key, value in TEXTURE_PARAMS.items():
            new = re.sub(r'^%s=.*$' % re.escape(key), f'{key}={value}', new, flags=re.M)
        if new != text:
            path.write_text(new); changed += 1
    print('texture import settings updated:', changed)


def imported_sizes():
    """Bytes of .godot/imported files behind every model GLB/texture import under art/models."""
    total = {}
    for imp in (ROOT / 'art/models').rglob('*.import'):
        src = Path(str(imp)[:-7])
        if 'portraits' in src.parts or src.parent == ROOT / 'art/models' or src.parent == ROOT / 'art/models/monsters':
            continue
        text = imp.read_text()
        dests = re.findall(r'"res://(\.godot/imported/[^"]+)"', text.split('[deps]')[-1])
        size = sum((ROOT / d).stat().st_size for d in dests if (ROOT / d).exists())
        kind = 'mesh' if src.suffix == '.glb' else 'texture'
        group = 'limne' if 'limne' in src.parts else 'monster' if 'monsters' in src.parts else 'hero'
        total.setdefault(f'{group}_{kind}', [0, 0])
        total[f'{group}_{kind}'][0] += 1
        total[f'{group}_{kind}'][1] += size
    return total


def imported_bytes(folder):
    """Imported (.godot) bytes of the model GLB and of its textures in one model folder."""
    out = {'mesh': 0, 'texture': 0}
    for imp in folder.glob('*.import'):
        dests = re.findall(r'"res://(\.godot/imported/[^"]+)"', imp.read_text().split('[deps]')[-1])
        size = sum((ROOT / d).stat().st_size for d in dests if (ROOT / d).exists())
        out['mesh' if imp.name.endswith('.glb.import') else 'texture'] += size
    return out


def summary():
    rows = {}
    before_files = WORK / 'imported-before-files.json'
    old = {}
    if before_files.exists():
        for src, size, _ in json.loads(before_files.read_text()):
            folder = str(Path(src).parent)
            kind = 'mesh' if src.endswith('.glb') else 'texture'
            old.setdefault(folder, {'mesh': 0, 'texture': 0})[kind] += size
    for cid in all_ids():
        report_path = WORK / cid / 'report.json'
        kind, dest = runtime(cid)
        backup = HIGHPOLY / 'art-models' / dest.relative_to(ROOT / 'art/models')
        before = glb_stats(backup.read_bytes())
        after = glb_stats(dest.read_bytes())
        report = json.loads(report_path.read_text()) if report_path.exists() else {}
        folder = str(dest.parent.relative_to(ROOT))
        rows[cid] = {'kind': kind, 'monster_kind': report.get('budget', {}).get('monster_kind'),
                     'before': {k: before[k] for k in ['triangles', 'vertices', 'surfaces', 'materials', 'bytes']},
                     'after': {k: after[k] for k in ['triangles', 'vertices', 'surfaces', 'materials', 'bytes']},
                     'texture_before': image_sizes(backup.read_bytes()),
                     'texture_after': image_sizes(dest.read_bytes()),
                     'imported_bytes_before': old.get(folder),
                     'imported_bytes_after': imported_bytes(dest.parent),
                     'deviation_p99_m': report.get('deviation_m', {}).get('p99'),
                     'bake_miss_fraction': report.get('bake', {}).get('miss_fraction'),
                     'glb_sha256': after['sha256']}
    baseline = WORK / 'imported-before.json'
    out = {'models': rows, 'imported_after': imported_sizes(),
           'imported_before': json.loads(baseline.read_text()) if baseline.exists() else None}
    (WORK / 'summary.json').write_text(json.dumps(out, indent=1) + '\n')
    lines = ['id,kind,tris_before,tris_after,verts_before,verts_after,surfaces_before,surfaces_after,'
             'texture_before,texture_after,glb_bytes_before,glb_bytes_after,imported_bytes_before,imported_bytes_after']
    for cid, r in rows.items():
        ib = r['imported_bytes_before'] or {}; ia = r['imported_bytes_after']
        lines.append(','.join(str(x) for x in [cid, r['monster_kind'] or r['kind'], r['before']['triangles'], r['after']['triangles'],
                     r['before']['vertices'], r['after']['vertices'], r['before']['surfaces'], r['after']['surfaces'],
                     'x'.join(str(v[0]) for v in r['texture_before'] if v) or '-', 'x'.join(str(v[0]) for v in r['texture_after'] if v) or '-',
                     r['before']['bytes'], r['after']['bytes'], sum(ib.values()) if ib else '', sum(ia.values())]))
    (WORK / 'summary.csv').write_text('\n'.join(lines) + '\n')
    for key in sorted(out['imported_after']):
        b = (out['imported_before'] or {}).get(key, [0, 0])
        a = out['imported_after'][key]
        print(f'{key:16s} files {b[0]:3d} -> {a[0]:3d}   {b[1] / 1e6:8.2f} MB -> {a[1] / 1e6:7.2f} MB')
    print('summary:', WORK / 'summary.json')


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('mode', choices=['install', 'textures', 'summary', 'baseline'])
    p.add_argument('--ids', default='')
    p.add_argument('--all', action='store_true')
    a = p.parse_args()
    if a.mode == 'install':
        ids = all_ids() if a.all else [i for i in a.ids.split(',') if i]
        install(ids)
    elif a.mode == 'textures':
        textures()
    elif a.mode == 'baseline':
        (WORK / 'imported-before.json').write_text(json.dumps(imported_sizes(), indent=1) + '\n')
        print(imported_sizes())
    else:
        summary()


if __name__ == '__main__':
    main()
