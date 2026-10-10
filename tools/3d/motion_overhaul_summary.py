#!/usr/bin/env python3
"""Summarize the motion-2 Godot review captures per hero/resolution into one JSON.

    python3 tools/3d/motion_overhaul_summary.py

Counts the actual PNG frames, requires each render.log to be free of ERROR:/!! lines,
records the GLB SHA the capture used (review/report.json) versus the manifest, and
writes build/motion-overhaul/motion2-review-summary.json.
"""
import hashlib, json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REVIEW = ROOT / 'build/character-3d/review'
STATES = ['idle', 'attack', 'walk', 'walk_stop', 'walk_curve', 'turn', 'aim', 'walk_attack']


def main() -> None:
    manifest = json.loads((ROOT / 'art/models/native_heroes.json').read_text())
    report = json.loads((REVIEW / 'report.json').read_text()) if (REVIEW / 'report.json').exists() else {'heroes': {}}
    ids = list(manifest['ready_ids']) + ['limne']
    summary = {'heroes': {}, 'complete': 0, 'render_errors': 0, 'missing': []}
    for cid in ids:
        glb = ROOT / 'art/models' / cid / f'{cid}.glb'
        sha = hashlib.sha256(glb.read_bytes()).hexdigest()
        row = {'glb_sha256': sha, 'manifest_sha_matches': manifest['heroes'].get(cid, {}).get('glb_sha256', sha) == sha, 'resolutions': {}}
        complete = True
        for res in ['1280x800', '1000x625']:
            folder = REVIEW / cid / res
            log = folder / 'render.log'
            text = log.read_text(errors='ignore') if log.exists() else ''
            errors = sum(1 for line in text.splitlines() if line.startswith('ERROR:') or line.startswith('!! '))
            frames = {state: len(list(folder.glob(f'{state}_[0-9][0-9].png'))) for state in STATES}
            ok = all(frames[s] > 0 for s in STATES) and (folder / 'locomotion.gif').exists() and log.exists() and errors == 0
            complete = complete and ok
            summary['render_errors'] += errors
            row['resolutions'][res] = {'png': len(list(folder.glob('*.png'))), 'frames': frames, 'render_log_errors': errors,
                                       'locomotion_gif': (folder / 'locomotion.gif').exists(), 'motion_gif': (folder / 'motion.gif').exists(),
                                       'battle': (folder / 'battle.png').exists() and (folder / 'battle.png').stat().st_mtime > (folder / 'walk_00.png').stat().st_mtime - 3600 if (folder / 'walk_00.png').exists() else False,
                                       'reviewed_sha': report['heroes'].get(cid, {}).get('glb_sha256')}
        row['complete'] = complete
        if complete: summary['complete'] += 1
        else: summary['missing'].append(cid)
        summary['heroes'][cid] = row
    out = ROOT / 'build/motion-overhaul/motion2-review-summary.json'
    out.write_text(json.dumps(summary, indent=2) + '\n')
    print(f"complete {summary['complete']}/{len(ids)}; render_log_errors={summary['render_errors']}; missing={','.join(summary['missing'])}")
    total_png = sum(r['png'] for h in summary['heroes'].values() for r in h['resolutions'].values())
    print('total png', total_png)


main()
